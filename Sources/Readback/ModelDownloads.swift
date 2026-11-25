import Foundation
import ReadbackCore

/// The model download under way, if any, for the player and the Voices page to show.
@MainActor
final class ModelDownloads: ObservableObject {
    struct Status: Equatable {
        let model: String
        var received: Int64
        /// What the whole download comes to; nil until it's known.
        var total: Int64?

        /// 0...1, held just short of 1 until the download says it's finished.
        var fraction: Double? {
            guard let total, total > 0 else { return nil }
            return min(Double(received) / Double(total), 0.99)
        }

        /// "1.2 GB of 3.1 GB", or "120 MB" while the total isn't known.
        var amount: String {
            let got = received.formatted(.byteCount(style: .file))
            guard let total else { return got }
            return "\(got) of \(total.formatted(.byteCount(style: .file)))"
        }
    }

    @Published private(set) var active: Status?
    /// The last download that stopped short, with why, until another one starts.
    @Published private(set) var failure: (model: String, reason: String)?

    func started(_ model: String) {
        failure = nil
        active = Status(model: model, received: 0, total: VoiceCatalog.downloadBytes(for: model))
    }

    func failed(_ model: String, reason: String) {
        failure = (model, reason)
    }

    /// A known model's measured size wins over the running total, which grows as each file starts.
    func progress(_ model: String, received: Int64, total: Int64) {
        // Updates hop over from the pipe's queue; one landing after the download ended is stale.
        guard active?.model == model else { return }
        let known = VoiceCatalog.downloadBytes(for: model)
        let best = max(known ?? 0, total)
        active = Status(model: model, received: received, total: best > 0 ? best : nil)
    }

    func ended(_ model: String) {
        if active?.model == model { active = nil }
    }

    func status(for model: String?) -> Status? {
        guard let model, active?.model == model else { return nil }
        return active
    }
}
