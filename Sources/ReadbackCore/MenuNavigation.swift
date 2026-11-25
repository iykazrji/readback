import Foundation

/// The keyboard side of Readback's own menus (the app's `Dropdown`), behaving like a macOS
/// menu: it opens on the chosen item, Up and Down move and stop at the ends, and typing jumps
/// to the first item that starts with what's been typed in the last second. Typing one letter
/// again and again goes round the items that start with it.
public struct MenuNavigation: Equatable {
    /// How long a pause starts a new search.
    public static let typingPause: TimeInterval = 1

    public let titles: [String]
    public private(set) var highlighted: Int?
    private var typed = ""
    private var lastTyped: TimeInterval = -.infinity

    public init(titles: [String], selected: Int?) {
        self.titles = titles
        highlighted = selected.flatMap { titles.indices.contains($0) ? $0 : nil }
    }

    public mutating func moveDown() {
        guard !titles.isEmpty else { return }
        highlighted = min((highlighted ?? -1) + 1, titles.count - 1)
    }

    public mutating func moveUp() {
        guard !titles.isEmpty else { return }
        highlighted = max((highlighted ?? titles.count) - 1, 0)
    }

    public mutating func highlightFirst() {
        highlighted = titles.isEmpty ? nil : 0
    }

    /// A key typed at `time` (seconds, any clock that only goes forward).
    public mutating func type(_ character: Character, at time: TimeInterval) {
        if time - lastTyped > Self.typingPause { typed = "" }
        lastTyped = time
        typed += String(character).lowercased()
        let lower = titles.map { $0.lowercased() }

        // The same letter again: the next item that starts with it, going round.
        if typed.count > 1, Set(typed).count == 1, let letter = typed.first {
            let start = (highlighted ?? -1) + 1
            let order = Array(start..<lower.count) + Array(0..<min(start, lower.count))
            if let next = order.first(where: { lower[$0].hasPrefix(String(letter)) }) { highlighted = next }
            return
        }
        if let match = lower.firstIndex(where: { $0.hasPrefix(typed) }) { highlighted = match }
    }
}
