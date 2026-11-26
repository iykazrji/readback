import CryptoKit
import Foundation

// Check for updates: a manual check from the sidebar's version card, and an install that swaps
// the app in place and reopens it. The owner chose all of it on 2026-11-26: manual only (no
// check at launch, no timer, so the only network traffic is still what the person asked for),
// install and relaunch rather than a web page, our own updater rather than Sparkle.
// Spec: docs/superpowers/specs/2026-11-26-update-check-design.md.

/// The newest release on GitHub, as the update check needs it.
///
/// This is a contract with how releases are published: the tag is `v<version>`, and the asset
/// named `Readback.zip` holds `Readback/Readback.app`.
public struct Release: Equatable {
    public static let assetName = "Readback.zip"

    public let version: String
    public let zip: URL
    /// The zip's sha256 as GitHub recorded it, lowercase hex; nil when GitHub gave none.
    public let sha256: String?
    /// The release's page, for "What's new" and "Download page".
    public let page: URL
    public let size: Int64?

    public init(version: String, zip: URL, sha256: String?, page: URL, size: Int64?) {
        self.version = version
        self.zip = zip
        self.sha256 = sha256
        self.page = page
        self.size = size
    }

    public struct Unexpected: Error {}

    /// Reads GitHub's `releases/latest` answer.
    public static func parse(_ data: Data) throws -> Release {
        struct Payload: Decodable {
            struct Asset: Decodable {
                let name: String
                let size: Int64?
                let digest: String?
                let browser_download_url: URL
            }
            let tag_name: String
            let html_url: URL
            let assets: [Asset]
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard let zip = payload.assets.first(where: { $0.name == assetName }) else { throw Unexpected() }
        let digest = zip.digest.flatMap { value -> String? in
            let parts = value.split(separator: ":", maxSplits: 1)
            guard parts.count == 2, parts[0].lowercased() == "sha256" else { return nil }
            return parts[1].lowercased()
        }
        return Release(version: Updates.plain(payload.tag_name), zip: zip.browser_download_url, sha256: digest,
                       page: payload.html_url, size: zip.size)
    }
}

public enum Updates {
    public static let defaultURL = URL(string: "https://api.github.com/repos/iykazrji/readback/releases/latest")!

    /// Where the check asks. `READBACK_UPDATES_URL` points it at a fake release for testing.
    public static func latestURL(environment: [String: String]) -> URL {
        environment["READBACK_UPDATES_URL"].flatMap(URL.init(string:)) ?? defaultURL
    }

    /// "v0.6.0" as "0.6.0".
    static func plain(_ version: String) -> String {
        version.hasPrefix("v") || version.hasPrefix("V") ? String(version.dropFirst()) : version
    }

    /// Whether `candidate` is a later version than `current`, part by part ("0.10.0" beats "0.9.0").
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        plain(candidate).compare(plain(current), options: .numeric) == .orderedDescending
    }

    /// A file's sha256 as lowercase hex, read in pieces so a 20 MB zip isn't held at once.
    public static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Why the running copy can't be swapped in place, or nil when it can.
    public static func replaceProblem(bundlePath: String, writable: Bool) -> ReplaceProblem? {
        if !bundlePath.hasSuffix(".app") { return .notAnApp }
        if bundlePath.contains("/AppTranslocation/") { return .translocated }
        return writable ? nil : .readOnly
    }

    /// What's wrong with the unzipped app, from its Info.plist, or nil when it's a newer Readback.
    public static func check(newInfo: [String: Any], bundleID: String, current: String) -> InstallFailure? {
        guard newInfo["CFBundleIdentifier"] as? String == bundleID,
              let version = newInfo["CFBundleShortVersionString"] as? String else { return .wrongApp }
        return isNewer(version, than: current) ? nil : .notNewer
    }

    /// `/bin/sh` arguments that wait for `pid` to exit, then open `app` again, carrying every
    /// `READBACK_*` variable so a test copy comes back as itself and not as the person's app.
    public static func relaunch(pid: Int32, app: String, environment: [String: String]) -> [String] {
        let carried = environment.keys.filter { $0.hasPrefix("READBACK_") }.sorted()
            .flatMap { ["--env", "\($0)=\(environment[$0]!)"] }
        let script = "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; exec /usr/bin/open \"$@\""
        return ["-c", script, "sh"] + carried + [app]
    }
}

/// Why the check didn't get an answer.
public enum CheckFailure: Error, Equatable {
    case offline, busy, unexpected

    public init(status: Int?, error: Error?) {
        if let error = error as? URLError {
            let offline: Set<URLError.Code> = [.notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
                                               .cannotConnectToHost, .timedOut, .dnsLookupFailed, .internationalRoamingOff,
                                               .dataNotAllowed]
            self = offline.contains(error.code) ? .offline : .unexpected
        } else if status == 403 || status == 429 {
            self = .busy
        } else {
            self = .unexpected
        }
    }

    public var message: String {
        switch self {
        case .offline: return "Readback couldn\u{2019}t reach GitHub. Check your internet connection."
        case .busy: return "GitHub is turning requests away for a moment. Try again in a few minutes."
        case .unexpected: return "GitHub sent back something Readback didn\u{2019}t expect."
        }
    }
}

/// Why an install stopped. Every one stops before the swap, or the swap itself failed and put
/// nothing in place, so the installed copy is as it was.
public enum InstallFailure: Equatable {
    case download(String)
    case noDigest
    case digestMismatch
    case noApp
    case wrongApp
    case notNewer
    case signature
    case swap(String)

    public var message: String {
        let reason: String
        switch self {
        case .download(let why): reason = "The download stopped: \(why)."
        case .noDigest: reason = "GitHub didn\u{2019}t say what the download should be, so Readback couldn\u{2019}t check it."
        case .digestMismatch: reason = "The download didn\u{2019}t match the one on GitHub."
        case .noApp: reason = "The download didn\u{2019}t have Readback in it."
        case .wrongApp: reason = "The download held a different app."
        case .notNewer: reason = "The download wasn\u{2019}t a newer Readback."
        case .signature: reason = "The app in the download failed its signature check."
        case .swap(let why): reason = "Readback couldn\u{2019}t put the new copy in place: \(why)."
        }
        return reason + " Readback left your copy as it is."
    }
}

/// Why Readback can't swap itself where it is.
public enum ReplaceProblem: Equatable {
    case readOnly, translocated, notAnApp

    public var message: String {
        switch self {
        case .readOnly: return "It isn\u{2019}t allowed to change the folder it\u{2019}s in. Download it and replace Readback yourself."
        case .translocated: return "macOS is running it from a temporary copy. Move Readback to Applications, open it, and check again."
        case .notAnApp: return "This copy of Readback isn\u{2019}t an installed app."
        }
    }
}

/// Work that installing would cut off, so Install waits for it. Quitting mid-download throws
/// away a voice the person asked for; mid-Connect could leave a tool's config half-written,
/// which PRODUCT.md's "safe" rules out. (Builder check, 2026-11-26.)
public enum UpdateWait: Equatable {
    case engineInstall, voiceDownload, connecting

    public static func of(voiceDownload: Bool, engineInstall: Bool, connecting: Bool) -> UpdateWait? {
        if engineInstall { return .engineInstall }
        if voiceDownload { return .voiceDownload }
        return connecting ? .connecting : nil
    }

    public var message: String {
        switch self {
        case .engineInstall: return "Install it once the voice engine has finished installing."
        case .voiceDownload: return "Install it once the voice download has finished."
        case .connecting: return "Install it once Connections has finished."
        }
    }
}

/// What the sidebar's version card shows.
public enum UpdateCard: Equatable {
    case rest
    case checking
    case upToDate
    case available(Release)
    case cantReplace(Release, ReplaceProblem)
    case downloading(Release, received: Int64, total: Int64)
    case installing(Release)
    case checkFailed(CheckFailure)
    case installFailed(Release, InstallFailure)
}

/// What the app does next.
public enum UpdateEffect: Equatable {
    case fetch
    case download(Release)
    case cancelDownload
    case expireUpToDate(seconds: Double)
}

/// The version card's states. The app tells it what happened and carries out what it returns,
/// the same way as `ReplyQueue`. Anything that doesn't fit the current state is ignored, so a
/// second click or a late progress report can't jump the card somewhere wrong.
public struct UpdateFlow: Equatable {
    public private(set) var card: UpdateCard = .rest

    public init() {}

    /// "Up to date" shows this long before the card goes back to rest.
    public static let upToDateFor: Double = 3

    public mutating func check() -> UpdateEffect? {
        switch card {
        case .rest, .upToDate, .checkFailed:
            card = .checking
            return .fetch
        default:
            return nil
        }
    }

    public mutating func checked(_ result: Result<Release, CheckFailure>, current: String, problem: ReplaceProblem?) -> UpdateEffect? {
        guard card == .checking else { return nil }
        switch result {
        case .failure(let failure):
            card = .checkFailed(failure)
            return nil
        case .success(let release) where !Updates.isNewer(release.version, than: current):
            card = .upToDate
            return .expireUpToDate(seconds: Self.upToDateFor)
        case .success(let release):
            card = problem.map { .cantReplace(release, $0) } ?? .available(release)
            return nil
        }
    }

    /// Install starts only when nothing else is in the middle of something; `waitingOn` says what.
    public mutating func install(waitingOn wait: UpdateWait? = nil) -> UpdateEffect? {
        guard wait == nil else { return nil }
        switch card {
        case .available(let release), .installFailed(let release, _):
            card = .downloading(release, received: 0, total: release.size ?? 0)
            return .download(release)
        default:
            return nil
        }
    }

    public mutating func progress(received: Int64, total: Int64) {
        guard case .downloading(let release, _, _) = card else { return }
        card = .downloading(release, received: received, total: total)
    }

    /// The zip is in; the checks and the swap run now.
    public mutating func downloaded() {
        guard case .downloading(let release, _, _) = card else { return }
        card = .installing(release)
    }

    public mutating func failed(_ failure: InstallFailure) {
        switch card {
        case .downloading(let release, _, _), .installing(let release):
            card = .installFailed(release, failure)
        default:
            break
        }
    }

    public mutating func cancel() -> UpdateEffect? {
        guard case .downloading(let release, _, _) = card else { return nil }
        card = .available(release)
        return .cancelDownload
    }

    /// "Close" on a failed check.
    public mutating func close() {
        if case .checkFailed = card { card = .rest }
    }

    public mutating func upToDateExpired() {
        if card == .upToDate { card = .rest }
    }
}
