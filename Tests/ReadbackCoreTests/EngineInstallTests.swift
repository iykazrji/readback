import Testing
@testable import ReadbackCore

/// Making the engine's Python environment. An install that was cancelled leaves a half-made
/// .venv behind, and uv refuses to make one over it, so every install starts it fresh.
@Suite struct EngineInstallTests {
    @Test func aNewInstallClearsWhateverACancelledOneLeft() {
        let args = EngineInstall.venvArguments(at: "/tmp/runtime/.venv")
        #expect(args.first == "venv")
        #expect(args.contains("--clear"))
        #expect(args.last == "/tmp/runtime/.venv")
    }

    @Test func itAsksForPython3_12WithoutAProject() {
        let args = EngineInstall.venvArguments(at: "/x/.venv")
        #expect(args.containsSequence(["--python", "3.12"]))
        #expect(args.contains("--no-project"))
    }
}

private extension Array where Element == String {
    func containsSequence(_ part: [String]) -> Bool {
        guard part.count <= count else { return false }
        return (0...(count - part.count)).contains { Array(self[$0..<$0 + part.count]) == part }
    }
}
