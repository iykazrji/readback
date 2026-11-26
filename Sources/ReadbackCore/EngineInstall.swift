import Foundation

/// The steps of installing the on-device engine that don't need the app to describe.
public enum EngineInstall {
    /// Getting Python, installing the engine's packages (then its receipt), downloading the voice.
    public enum Step: Equatable { case python, engine, voice }

    /// Where an install starts. Once the engine is installed (its receipt and server are there),
    /// only the voice is left: a Try again after the voice's download failed resumes there, so
    /// it never clears an environment that works (deep review 2026-11-26, P2-1).
    public static func firstStep(engineInstalled: Bool) -> Step {
        engineInstalled ? .voice : .python
    }

    /// `uv venv` for the engine's Python environment. `--clear` because an install that was
    /// cancelled leaves a half-made .venv, and uv refuses to make one over it ("A virtual
    /// environment already exists"), so Install after Cancel failed every time (found
    /// 2026-11-25). It only runs from `firstStep` `.python`, while the engine isn't installed, so
    /// there's never a working environment to lose.
    public static func venvArguments(at path: String) -> [String] {
        ["venv", "--clear", "--python", "3.12", "--no-project", path]
    }
}

extension ReadbackPaths {
    /// The one meaning of "the engine is installed": its receipt, written once its packages are
    /// in, and a server that can run. A server without the receipt is an install cut short.
    public var engineIsInstalled: Bool {
        FileManager.default.fileExists(atPath: runtimeReceipt.path)
            && FileManager.default.isExecutableFile(atPath: voiceServer.path)
    }
}
