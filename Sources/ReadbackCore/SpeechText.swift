import Foundation
import NaturalLanguage

/// Turns an agent's markdown reply into text that sounds right read aloud,
/// and splits it into short chunks the player can step through.
public enum SpeechText {
    /// Strips markdown that shouldn't be spoken. Code blocks and tables are replaced
    /// with a short spoken note so the listener knows something was there.
    public static func clean(_ markdown: String) -> String {
        var text = markdown.replacingOccurrences(of: "\r\n", with: "\n")

        text = replace(text, #"```[\s\S]*?```"#, "\n(code block skipped)\n")
        // A leftover opening fence with no close: drop everything after it.
        text = replace(text, #"```[\s\S]*$"#, "\n(code block skipped)\n")
        text = replaceTables(text)
        text = replace(text, #"!\[([^\]]*)\]\([^)]*\)"#, "$1")
        text = replace(text, #"\[([^\]]+)\]\([^)]*\)"#, "$1")
        text = replace(text, #"<?https?://[^\s>)]+>?"#, "link")
        text = replace(text, #"`([^`\n]*)`"#, "$1")
        text = replace(text, #"(?m)^[ \t]*#{1,6}[ \t]+"#, "")
        text = replace(text, #"(?m)^[ \t]*>[ \t]?"#, "")
        text = replace(text, #"(?m)^[ \t]*[-*+][ \t]+"#, "")
        text = replace(text, #"(?m)^[ \t]*[-*_]{3,}[ \t]*$"#, "")
        text = replace(text, #"\*\*|__|~~"#, "")
        // Single * or _ used for emphasis, but not the _ inside snake_case words.
        text = replace(text, #"(?<![\w*])[*_](?=\S)|(?<=\S)[*_](?![\w*])"#, "")
        text = replace(text, #"[ \t]+"#, " ")
        text = replace(text, #"\n{3,}"#, "\n\n")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Splits cleaned text into chunks: never across a line break, never mid-sentence,
    /// and short sentences on the same line merge up to `maxChars` so speech flows.
    public static func chunks(_ text: String, maxChars: Int = 220) -> [String] {
        var result: [String] = []
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            var current = ""
            for sentence in sentences(in: trimmed) {
                if current.isEmpty {
                    current = sentence
                } else if current.count + 1 + sentence.count <= maxChars {
                    current += " " + sentence
                } else {
                    result.append(current)
                    current = sentence
                }
            }
            if !current.isEmpty { result.append(current) }
        }
        return result
    }

    static func sentences(in line: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = line
        var out: [String] = []
        tokenizer.enumerateTokens(in: line.startIndex..<line.endIndex) { range, _ in
            let s = line[range].trimmingCharacters(in: .whitespaces)
            if !s.isEmpty { out.append(s) }
            return true
        }
        return out.isEmpty ? [line] : out
    }

    /// Replaces each run of markdown table lines (lines starting and ending with |) with one note.
    static func replaceTables(_ text: String) -> String {
        var out: [String] = []
        var inTable = false
        for line in text.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            let isTableLine = t.hasPrefix("|") && t.hasSuffix("|") && t.count > 1
            if isTableLine {
                if !inTable { out.append("(table skipped)") }
                inTable = true
            } else {
                inTable = false
                out.append(line)
            }
        }
        return out.joined(separator: "\n")
    }

    private static func replace(_ text: String, _ pattern: String, _ template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            assertionFailure("bad regex: \(pattern)")
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }
}
