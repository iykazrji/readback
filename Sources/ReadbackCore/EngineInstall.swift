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

    /// Where the engine stands, as the nudge needs it.
    public enum Situation: Equatable {
        case unsupported, notInstalled, installed
        /// A fresh install, ending with a voice: the download the person asked for.
        case installing
        /// New packages into an engine that's there; brief, and no voice to download.
        case updating
        case failed
        /// A removal that didn't finish: Voices says so, and it's not a download to retry.
        case removalFailed
    }

    /// What Home's Voice chip and the player say about the natural voice while replies fall
    /// back to the macOS voice. Without it, someone who skipped the download only hears the flat
    /// voice and never learns there's another (owner, 2026-11-26). Each opens Voices, where
    /// Install shows the size first, so nothing big downloads without the person's click.
    public enum Nudge: Equatable {
        /// They want a natural voice and the engine isn't here.
        case getIt
        /// The install they started is under way.
        case downloading
        /// The install they started stopped short.
        case didntFinish
    }

    /// `wantsNatural`: the voice picked needs the engine. Someone who picked the macOS voice is
    /// never asked to get the engine; an install or failure they started still shows.
    public static func nudge(wantsNatural: Bool, engine: Situation) -> Nudge? {
        switch engine {
        case .notInstalled: return wantsNatural ? .getIt : nil
        case .installing: return .downloading
        case .failed: return .didntFinish
        case .unsupported, .installed, .updating, .removalFailed: return nil
        }
    }

    /// How far a whole install has got, as one meter.
    public struct Progress: Equatable {
        public let received: Int64
        public let total: Int64

        /// 0...1, held just short of full until the install ends.
        public var fraction: Double {
            total > 0 ? min(Double(received) / Double(total), 0.99) : 0
        }

        /// "0.45 of 1.86 GB", one width throughout (DownloadAmount).
        public var amount: String { DownloadAmount.text(received: received, total: total) }
    }

    /// One meter for the engine's packages and then the voice's model. The setup sheet and Voices
    /// both draw this, so closing the sheet mid-install leaves the same numbers on Voices (owner,
    /// 2026-11-26: the download carries on in the background and Voices shows it going).
    ///
    /// - engineFetched: what the engine steps have fetched so far, measured on disk.
    /// - engineTotal: what they come to (Runtime's measured figure).
    /// - modelReceived: the voice's download so far; nil while it isn't downloading.
    /// - modelTotal: the voice's size; 0 when it isn't known (a custom model).
    public static func progress(step: Step?, engineFetched: Int64, engineTotal: Int64,
                                modelReceived: Int64?, modelTotal: Int64) -> Progress {
        // At the voice step the engine is in, whether it was fetched now or before (a Try again).
        let engine = step == .voice ? engineTotal : min(max(engineFetched, 0), engineTotal)
        let modelAll = max(modelTotal, modelReceived ?? 0)
        // The voice step with nothing downloading: the model was on disk already.
        let model = modelReceived ?? (step == .voice ? modelAll : 0)
        return Progress(received: engine + model, total: engineTotal + modelAll)
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
