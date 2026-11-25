/// The steps of installing the on-device engine that don't need the app to describe.
public enum EngineInstall {
    /// `uv venv` for the engine's Python environment. `--clear` because an install that was
    /// cancelled leaves a half-made .venv, and uv refuses to make one over it ("A virtual
    /// environment already exists"), so Install after Cancel failed every time (found
    /// 2026-11-25). An install only runs while the engine isn't installed (no receipt), so
    /// there's never a working environment to lose.
    public static func venvArguments(at path: String) -> [String] {
        ["venv", "--clear", "--python", "3.12", "--no-project", path]
    }
}
