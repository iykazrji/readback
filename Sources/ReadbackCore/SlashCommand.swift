import Foundation

/// Slash commands in UI copy (`/readback:speak on`, `/read`) wrap as a whole. macOS may break a
/// line right after a "/", which leaves the slash at the end of one line and the command's name
/// on the next: the Reading page's footer did at the default window width (UI check, 2026-11-26).
/// A word joiner after a command's slash keeps the two together. It's invisible, and VoiceOver
/// skips it.
public enum SlashCommand {
    /// `text` with every command's slash (one that starts a word and is followed by a letter)
    /// joined to its name. Paths like `~/.claude` and words like "and/or" are left as they are.
    public static func keptWhole(in text: String) -> String {
        let characters = Array(text)
        var result = ""
        for (i, character) in characters.enumerated() {
            result.append(character)
            guard character == "/" else { continue }
            let startsWord = i == 0 || characters[i - 1].isWhitespace
            let nameFollows = i + 1 < characters.count && characters[i + 1].isLetter
            if startsWord && nameFollows { result.append("\u{2060}") }
        }
        return result
    }
}
