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

        /// "1.24 of 3.08 GB", or "120 MB" while the total isn't known. One width for the whole
        /// download, as long as it's drawn with `.monospacedDigit()`.
        var amount: String { DownloadAmount.text(received: received, total: total) }

        /// "40%", two digits wide, or nil while the total isn't known.
        var percent: String? { fraction.map(DownloadAmount.percent) }
    }

    @Published private(set) var active: Status?
    /// The last download that stopped short, with why, until another one starts.
    @Published private(set) var failure: (model: String, reason: String)?

    func started(_ model: String) {
        failure = nil
        if completed?.model == model { completed = nil }
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

    /// A download that finished and checked out, with when (seconds since the Mac started, which
    /// never runs backwards the way the wall clock can): the install's meter keeps its bytes and
    /// total while the voice warms up, and only for a download made since its voice step began.
    @Published private(set) var completed: (model: String, bytes: Int64, total: Int64?, at: TimeInterval)?

    /// The download of `model` worked (called after its exit and output are checked). It goes from
    /// downloading to done in this one step, so a view drawn in between never sees neither.
    func succeeded(_ model: String) {
        guard let active, active.model == model else { return }
        completed = (model, max(active.received, active.total ?? 0), active.total, ProcessInfo.processInfo.systemUptime)
        self.active = nil
    }

    /// What a download of `model` that finished at or after `since` (systemUptime) came to.
    func finished(_ model: String, since: TimeInterval) -> (bytes: Int64, total: Int64?)? {
        guard let completed, completed.model == model, completed.at >= since, active?.model != model else { return nil }
        return (completed.bytes, completed.total)
    }

    /// The person stopped it: not a failure, so nothing red is left behind.
    func cancelled(_ model: String) {
        if active?.model == model { active = nil }
        if failure?.model == model { failure = nil }
    }

    func status(for model: String?) -> Status? {
        guard let model, active?.model == model else { return nil }
        return active
    }
}
