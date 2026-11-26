import Foundation
import Testing
@testable import ReadbackCore

/// The sidebar's Check for updates: reading GitHub's latest release, the checks before the swap,
/// the relaunch, and the card's states.
@Suite struct UpdatesTests {
    private func json(tag: String = "v0.6.0", assets: String? = nil) -> Data {
        let assets = assets ?? """
        [{"name": "Readback.zip", "size": 21377960,
          "digest": "sha256:6FD8C1CDA7E1D20BABBA87AC9FE6C96D0E25A2638F78FA5CF4EA909DE2CFEB9F",
          "browser_download_url": "https://github.com/iykazrji/readback/releases/download/\(tag)/Readback.zip"}]
        """
        return Data("""
        {"tag_name": "\(tag)", "html_url": "https://github.com/iykazrji/readback/releases/tag/\(tag)", "assets": \(assets)}
        """.utf8)
    }

    private var release: Release { try! Release.parse(json()) }

    // MARK: Reading the release

    @Test func parsesTheLatestRelease() throws {
        let release = try Release.parse(json())
        #expect(release.version == "0.6.0")
        #expect(release.zip.absoluteString == "https://github.com/iykazrji/readback/releases/download/v0.6.0/Readback.zip")
        #expect(release.sha256 == "6fd8c1cda7e1d20babba87ac9fe6c96d0e25a2638f78fa5cf4ea909de2cfeb9f")
        #expect(release.page.absoluteString == "https://github.com/iykazrji/readback/releases/tag/v0.6.0")
        #expect(release.size == 21_377_960)
    }

    @Test func parseRejectsMissingZip() {
        #expect(throws: (any Error).self) { try Release.parse(json(assets: #"[{"name": "Other.zip", "browser_download_url": "https://x/y"}]"#)) }
        #expect(throws: (any Error).self) { try Release.parse(Data("not json".utf8)) }
    }

    @Test func aReleaseWithoutADigestParsesWithNone() throws {
        let release = try Release.parse(json(assets: #"[{"name": "Readback.zip", "browser_download_url": "https://x/Readback.zip"}]"#))
        #expect(release.sha256 == nil)
    }

    @Test func latestURLCanBePointedElsewhereForTests() {
        #expect(Updates.latestURL(environment: [:]).absoluteString == "https://api.github.com/repos/iykazrji/readback/releases/latest")
        #expect(Updates.latestURL(environment: ["READBACK_UPDATES_URL": "http://127.0.0.1:9/latest.json"]).absoluteString == "http://127.0.0.1:9/latest.json")
    }

    @Test func newerIsNumeric() {
        #expect(Updates.isNewer("0.10.0", than: "0.9.0"))
        #expect(Updates.isNewer("0.6.0", than: "0.5.0"))
        #expect(Updates.isNewer("v0.6.0", than: "0.5.0"))
        #expect(!Updates.isNewer("0.5.0", than: "0.5.0"))
        #expect(!Updates.isNewer("0.4.0", than: "0.5.0"))
        #expect(Updates.isNewer("1.0", than: "0.9.9"))
    }

    // MARK: Checks before the swap

    @Test func sha256OfAFile() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("abc".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(try Updates.sha256(of: file) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test func theNewAppMustBeReadbackAndNewer() {
        let ok: [String: Any] = ["CFBundleIdentifier": "local.readback", "CFBundleShortVersionString": "0.6.0"]
        #expect(Updates.check(newInfo: ok, bundleID: "local.readback", current: "0.5.0") == nil)
        #expect(Updates.check(newInfo: ok, bundleID: "local.readback.uitest", current: "0.5.0") == .wrongApp)
        #expect(Updates.check(newInfo: ok, bundleID: "local.readback", current: "0.6.0") == .notNewer)
        #expect(Updates.check(newInfo: [:], bundleID: "local.readback", current: "0.5.0") == .wrongApp)
    }

    @Test func replaceProblems() {
        #expect(Updates.replaceProblem(bundlePath: "/Applications/Readback.app", writable: true) == nil)
        #expect(Updates.replaceProblem(bundlePath: "/Applications/Readback.app", writable: false) == .readOnly)
        #expect(Updates.replaceProblem(bundlePath: "/private/var/folders/x/AppTranslocation/ABC/d/Readback.app", writable: true) == .translocated)
        #expect(Updates.replaceProblem(bundlePath: "/Users/x/readback/.build/debug", writable: true) == .notAnApp)
    }

    // MARK: Relaunch

    /// A test copy runs with its own port and home. A plain `open` would reopen it against the
    /// person's real ones (seen in a spike, 2026-11-26), so every READBACK_ variable goes along.
    @Test func relaunchCarriesReadbackVariables() {
        let args = Updates.relaunch(pid: 4242, app: "/Users/x/Applications/Readback.app",
                                    environment: ["READBACK_PORT": "8918", "READBACK_HOME": "/tmp/h", "HOME": "/Users/x", "PATH": "/bin"])
        #expect(args.first == "-c")
        #expect(args[1].contains("kill -0 4242"))
        #expect(args[1].contains("/usr/bin/open"))
        let rest = Array(args.dropFirst(3))
        #expect(rest == ["--env", "READBACK_HOME=/tmp/h", "--env", "READBACK_PORT=8918", "/Users/x/Applications/Readback.app"])
    }

    @Test func relaunchWithoutVariablesJustOpensTheApp() {
        let args = Updates.relaunch(pid: 1, app: "/Applications/Readback.app", environment: ["HOME": "/Users/x"])
        #expect(Array(args.dropFirst(3)) == ["/Applications/Readback.app"])
    }

    // MARK: Failures

    @Test func checkFailureReasons() {
        #expect(CheckFailure(status: nil, error: URLError(.notConnectedToInternet)) == .offline)
        #expect(CheckFailure(status: nil, error: URLError(.timedOut)) == .offline)
        #expect(CheckFailure(status: 403, error: nil) == .busy)
        #expect(CheckFailure(status: 429, error: nil) == .busy)
        #expect(CheckFailure(status: 404, error: nil) == .unexpected)
        #expect(CheckFailure(status: 200, error: DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: ""))) == .unexpected)
    }

    @Test func installFailuresSayTheCopyIsUntouched() {
        for failure in [InstallFailure.noDigest, .digestMismatch, .noApp, .wrongApp, .notNewer, .signature, .download("x"), .swap("x")] {
            #expect(failure.message.hasSuffix("Readback left your copy as it is."))
        }
    }

    // MARK: The card's states

    @Test func checkThenUpToDate() {
        var flow = UpdateFlow()
        #expect(flow.check() == .fetch)
        #expect(flow.card == .checking)
        #expect(flow.checked(.success(try! Release.parse(json(tag: "v0.5.0"))), current: "0.5.0", problem: nil) == .expireUpToDate(seconds: 3))
        #expect(flow.card == .upToDate)
        flow.upToDateExpired()
        #expect(flow.card == .rest)
    }

    @Test func checkFindsANewerOne() {
        var flow = UpdateFlow()
        _ = flow.check()
        #expect(flow.checked(.success(release), current: "0.5.0", problem: nil) == nil)
        #expect(flow.card == .available(release))
    }

    @Test func aNewerOneThatCantBeInstalledHere() {
        var flow = UpdateFlow()
        _ = flow.check()
        _ = flow.checked(.success(release), current: "0.5.0", problem: .readOnly)
        #expect(flow.card == .cantReplace(release, .readOnly))
        #expect(flow.install() == nil)
    }

    @Test func checkFailsThenTryAgain() {
        var flow = UpdateFlow()
        _ = flow.check()
        _ = flow.checked(.failure(.offline), current: "0.5.0", problem: nil)
        #expect(flow.card == .checkFailed(.offline))
        #expect(flow.check() == .fetch)
        _ = flow.checked(.failure(.offline), current: "0.5.0", problem: nil)
        flow.close()
        #expect(flow.card == .rest)
    }

    @Test func installDownloadsThenInstalls() {
        var flow = UpdateFlow()
        _ = flow.check()
        _ = flow.checked(.success(release), current: "0.5.0", problem: nil)
        #expect(flow.install() == .download(release))
        #expect(flow.card == .downloading(release, received: 0, total: 21_377_960))
        flow.progress(received: 1000, total: 2000)
        #expect(flow.card == .downloading(release, received: 1000, total: 2000))
        flow.downloaded()
        #expect(flow.card == .installing(release))
    }

    @Test func cancelGoesBackToAvailable() {
        var flow = UpdateFlow()
        _ = flow.check()
        _ = flow.checked(.success(release), current: "0.5.0", problem: nil)
        _ = flow.install()
        #expect(flow.cancel() == .cancelDownload)
        #expect(flow.card == .available(release))
    }

    @Test func installFailsThenTryAgain() {
        var flow = UpdateFlow()
        _ = flow.check()
        _ = flow.checked(.success(release), current: "0.5.0", problem: nil)
        _ = flow.install()
        flow.failed(.digestMismatch)
        #expect(flow.card == .installFailed(release, .digestMismatch))
        #expect(flow.install() == .download(release))
    }

    @Test func flowIgnoresRepeats() {
        var flow = UpdateFlow()
        _ = flow.check()
        #expect(flow.check() == nil, "a second click while checking does nothing")
        _ = flow.checked(.success(release), current: "0.5.0", problem: nil)
        _ = flow.install()
        #expect(flow.install() == nil, "Install while downloading does nothing")
        #expect(flow.check() == nil, "no check in the middle of an install")
        flow.downloaded()
        #expect(flow.cancel() == nil, "too late to cancel once it's installing")
        #expect(flow.card == .installing(release))
    }

    /// Quitting mid-download would throw away a voice the person asked for, and mid-Connect could
    /// leave a tool's config half-written, so Install waits for those to finish.
    @Test func installWaitsForOtherWork() {
        #expect(UpdateWait.of(voiceDownload: false, engineInstall: false, connecting: false) == nil)
        #expect(UpdateWait.of(voiceDownload: true, engineInstall: true, connecting: true) == .engineInstall)
        #expect(UpdateWait.of(voiceDownload: true, engineInstall: false, connecting: true) == .voiceDownload)
        #expect(UpdateWait.of(voiceDownload: false, engineInstall: false, connecting: true) == .connecting)
        var flow = UpdateFlow()
        _ = flow.check()
        _ = flow.checked(.success(release), current: "0.5.0", problem: nil)
        #expect(flow.install(waitingOn: .voiceDownload) == nil)
        #expect(flow.card == .available(release))
        #expect(flow.install(waitingOn: nil) == .download(release))
    }

    @Test func lateProgressAfterCancelIsIgnored() {
        var flow = UpdateFlow()
        _ = flow.check()
        _ = flow.checked(.success(release), current: "0.5.0", problem: nil)
        _ = flow.install()
        _ = flow.cancel()
        flow.progress(received: 5, total: 10)
        flow.downloaded()
        flow.failed(.download("cancelled"))
        #expect(flow.card == .available(release))
    }
}
