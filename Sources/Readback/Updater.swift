import AppKit
import ReadbackCore

/// Carries out Check for updates: asks GitHub for the latest release, downloads it, checks it,
/// swaps it in place and reopens. `UpdateFlow` (Core) decides what the card shows and what
/// happens next; this only does the work. Nothing here runs unless the person clicked.
@MainActor
final class Updater: ObservableObject {
    @Published private(set) var flow = UpdateFlow()
    var card: UpdateCard { flow.card }

    /// What Install would cut off right now, if anything. Set by the app delegate.
    var waitingOn: () -> UpdateWait? = { nil }

    /// The version an update is leaving, noted just before the swap and read on the next launch.
    static let leavingKey = "updateLeavingVersion"

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        // Only the app and its version: nothing about the person or their Mac.
        config.httpAdditionalHeaders = ["User-Agent": "Readback/\(Bundle.main.version)"]
        return URLSession(configuration: config)
    }()
    private var downloading: Task<Void, Never>?
    private var expiry: Task<Void, Never>?

    // MARK: What the card's buttons do

    func check() { carryOut(flow.check()) }
    func install() { carryOut(flow.install(waitingOn: waitingOn())) }
    func cancel() { carryOut(flow.cancel()) }
    func close() { flow.close() }
    func openPage(_ release: Release) { NSWorkspace.shared.open(release.page) }

    private func carryOut(_ effect: UpdateEffect?) {
        switch effect {
        case .fetch: Task { await fetch() }
        case .download(let release): downloading = Task { await download(release) }
        case .cancelDownload:
            downloading?.cancel()
            downloading = nil
            Log.info("update: download cancelled")
        case .expireUpToDate(let seconds):
            expiry?.cancel()
            expiry = Task {
                try? await Task.sleep(for: .seconds(seconds))
                if !Task.isCancelled { flow.upToDateExpired() }
            }
        case nil: break
        }
    }

    // MARK: The check

    private func fetch() async {
        let url = Updates.latestURL(environment: ProcessInfo.processInfo.environment)
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let result: Result<Release, CheckFailure>
        do {
            let (data, response) = try await session.data(for: request)
            // A file:// release (READBACK_UPDATES_URL, for testing) has no HTTP status.
            let status = (response as? HTTPURLResponse)?.statusCode ?? 200
            if status == 200, let release = try? Release.parse(data) {
                result = .success(release)
            } else {
                result = .failure(CheckFailure(status: status, error: nil))
            }
        } catch {
            result = .failure(CheckFailure(status: nil, error: error))
        }
        switch result {
        case .success(let release): Log.info("update: latest is \(release.version), this is \(Bundle.main.version)")
        case .failure(let failure): Log.error("update: check failed (\(failure))")
        }
        let bundle = Bundle.main.bundleURL
        let problem = Updates.replaceProblem(bundlePath: bundle.path, writable: Self.canReplace(bundle))
        carryOut(flow.checked(result, current: Bundle.main.version, problem: problem))
    }

    /// The app can be swapped when both it and the folder it's in can be changed.
    private static func canReplace(_ bundle: URL) -> Bool {
        let files = FileManager.default
        return files.isWritableFile(atPath: bundle.path) && files.isWritableFile(atPath: bundle.deletingLastPathComponent().path)
    }

    // MARK: The install

    private func download(_ release: Release) async {
        Log.info("update: downloading \(release.version) from \(release.zip.absoluteString)")
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("Readback-update-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            let zip = try await fetchZip(release.zip, into: work)
            guard !Task.isCancelled else { return cleanUp(work) }
            flow.downloaded()
            let app = try await Task.detached { try Self.unpackAndCheck(zip: zip, release: release, into: work) }.value
            try swapAndRelaunch(with: app, leaving: Bundle.main.version, work: work)
        } catch is CancellationError {
            cleanUp(work)
        } catch let error as URLError where error.code == .cancelled {
            cleanUp(work)
        } catch let failure as InstallFailure {
            Log.error("update: install stopped: \(failure.message)")
            flow.failed(failure)
            cleanUp(work)
        } catch {
            Log.error("update: download failed: \(error.localizedDescription)")
            flow.failed(.download(error.localizedDescription))
            cleanUp(work)
        }
    }

    /// Downloads the zip, reporting progress to the card every fifth of a second.
    private func fetchZip(_ url: URL, into folder: URL) async throws -> URL {
        let watcher = TaskWatcher()
        let meter = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                if let task = watcher.task, task.countOfBytesReceived > 0 {
                    self?.flow.progress(received: task.countOfBytesReceived,
                                        total: max(task.countOfBytesExpectedToReceive, self?.expectedSize ?? 0))
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
        defer { meter.cancel() }
        let (temporary, response) = try await session.download(from: url, delegate: watcher)
        if let status = (response as? HTTPURLResponse)?.statusCode, status != 200 {
            throw InstallFailure.download("GitHub sent error \(status).")
        }
        let zip = folder.appendingPathComponent(Release.assetName)
        try FileManager.default.moveItem(at: temporary, to: zip)
        return zip
    }

    private var expectedSize: Int64 {
        if case .downloading(let release, _, _) = flow.card { return release.size ?? 0 }
        return 0
    }

    /// Everything before the swap, off the main thread: the digest, the unzip, what the new app
    /// says it is, its signature, and clearing the download flag so macOS will open it.
    nonisolated private static func unpackAndCheck(zip: URL, release: Release, into work: URL) throws -> URL {
        guard let expected = release.sha256 else { throw InstallFailure.noDigest }
        guard (try? Updates.sha256(of: zip)) == expected else { throw InstallFailure.digestMismatch }

        let unpacked = work.appendingPathComponent("unpacked")
        guard run("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path]) == 0 else { throw InstallFailure.noApp }
        guard let app = findApp(in: unpacked) else { throw InstallFailure.noApp }

        let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")) as? [String: Any] ?? [:]
        // Its executable's slices, so a build for another Mac never replaces one that works here.
        let executable = (info["CFBundleExecutable"] as? String).map { app.appendingPathComponent("Contents/MacOS/\($0)").path }
        let architectures = executable.flatMap { output("/usr/bin/lipo", ["-archs", $0]) }?
            .split(whereSeparator: \.isWhitespace).map(String.init) ?? []
        if let failure = Updates.check(newInfo: info, bundleID: Bundle.main.bundleIdentifier ?? "", current: Bundle.main.version,
                                       offered: release.version, architectures: architectures) {
            throw failure
        }
        guard run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path]) == 0 else { throw InstallFailure.signature }
        // Not fatal on its own: a download that never got the flag has nothing to clear.
        _ = run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", app.path])
        return app
    }

    /// `Readback/Readback.app`, as the release zip holds it, or else the only app at the top.
    nonisolated private static func findApp(in folder: URL) -> URL? {
        let expected = folder.appendingPathComponent("Readback/Readback.app")
        if FileManager.default.fileExists(atPath: expected.path) { return expected }
        for place in [folder, folder.appendingPathComponent("Readback")] {
            let apps = ((try? FileManager.default.contentsOfDirectory(at: place, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == "app" }
            if apps.count == 1 { return apps[0] }
        }
        return nil
    }

    /// The swap is one atomic exchange (the old copy goes away with it), so there's never a
    /// moment with no Readback in place. Then a small shell waits for this process to end and
    /// opens the new copy, and the app quits.
    private func swapAndRelaunch(with app: URL, leaving version: String, work: URL) throws {
        // Asked again here, not only at the click: a download, an engine install or a Connect
        // started while the zip came in would be cut off by the quit (deep review, P2-5).
        if let wait = waitingOn() { throw InstallFailure.busy(wait) }
        let installed = Bundle.main.bundleURL
        let files = FileManager.default
        UserDefaults.standard.set(version, forKey: Self.leavingKey)
        var staging: URL?
        do {
            // Staged on the installed copy's own volume: the swap can't cross volumes, and the
            // download sits on the startup disk (deep review, P2-6).
            let folder = try files.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: installed, create: true)
            staging = folder
            let staged = folder.appendingPathComponent(installed.lastPathComponent)
            try files.moveItem(at: app, to: staged)
            _ = try files.replaceItemAt(installed, withItemAt: staged)
        } catch {
            UserDefaults.standard.removeObject(forKey: Self.leavingKey)
            if let staging { try? files.removeItem(at: staging) }
            throw InstallFailure.swap(error.localizedDescription)
        }
        if let staging { try? files.removeItem(at: staging) }
        // Versions only: where the app lives can name the person (deep review, P2-4).
        // The new copy logs "updated from … to …" when it starts.
        Log.info("update: the new version is in place of \(version); reopening")
        cleanUp(work)   // the zip and what's left of the unpacked folder
        let waiter = Process()
        waiter.executableURL = URL(fileURLWithPath: "/bin/sh")
        waiter.arguments = Updates.relaunch(pid: ProcessInfo.processInfo.processIdentifier, app: installed.path,
                                            environment: ProcessInfo.processInfo.environment)
        do {
            try waiter.run()
        } catch {
            // The new copy is in place; it just won't open by itself. Say so and quit anyway.
            Log.error("update: couldn't start the reopen step: \(error.localizedDescription); open Readback again by hand")
        }
        UserDefaults.standard.synchronize()
        NSApp.terminate(nil)
    }

    private func cleanUp(_ folder: URL) {
        try? FileManager.default.removeItem(at: folder)
    }

    /// Runs a tool and returns what it printed, or nil when it failed.
    nonisolated private static func output(_ tool: String, _ arguments: [String]) -> String? {
        let process = Process()
        let out = Pipe()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
    }

    /// Runs a tool and returns its exit status, or -1 when it couldn't start.
    nonisolated private static func run(_ tool: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return -1 }
        process.waitUntilExit()
        return process.terminationStatus
    }

    // MARK: After an update

    /// Called at launch. After an update the "lower other sounds" permission may belong to the
    /// old copy's signature, and it's only asked for when the switch is flipped, so it could stop
    /// working silently. Asking once is silent when the grant still holds and prompts when it
    /// doesn't (builder check, 2026-11-26).
    func afterLaunch(lowerOtherAudio: Bool, askPermission: () -> Void) {
        guard let leaving = UserDefaults.standard.string(forKey: Self.leavingKey) else { return }
        UserDefaults.standard.removeObject(forKey: Self.leavingKey)
        Log.info("update: updated from \(leaving) to \(Bundle.main.version)")
        if lowerOtherAudio { askPermission() }
    }
}

/// Hands the download's URLSessionTask over so its byte counts can be read for the meter.
private final class TaskWatcher: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var _task: URLSessionTask?
    var task: URLSessionTask? { lock.lock(); defer { lock.unlock() }; return _task }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        lock.lock(); _task = task; lock.unlock()
    }
}
