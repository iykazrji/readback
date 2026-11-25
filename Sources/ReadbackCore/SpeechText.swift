import Foundation
import NaturalLanguage

/// Turns an agent's markdown reply into text that sounds right read aloud,
/// and splits it into short chunks the player can step through.
public enum SpeechText {
    /// Whether a reply has anything to read once it's cleaned.
    public static func isSpeakable(_ markdown: String) -> Bool {
        !chunks(clean(markdown)).isEmpty
    }

    /// Strips markdown that shouldn't be spoken. Code blocks and tables are replaced
    /// with a short spoken note so the listener knows something was there.
    public static func clean(_ markdown: String) -> String {
        var text = markdown.replacingOccurrences(of: "\r\n", with: "\n")

        text = replaceFences(text)
        // Backtick runs that aren't fences (mid-line): a closed pair, then an unclosed one,
        // which drops everything after it.
        text = replace(text, #"```[\s\S]*?```"#, "\n(code block skipped)\n")
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

    /// Replaces each fenced code block with one note. A fence is a line starting with three or
    /// more backticks or tildes; it closes on a line of the same character at least as long, so
    /// a ```` block can hold ``` examples. An unclosed fence runs to the end.
    static func replaceFences(_ text: String) -> String {
        var out: [String] = []
        var open: (mark: Character, length: Int)?
        for line in text.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            // Four or more columns in (a tab is four) is indented text (CommonMark), not a fence.
            let indent = line.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
            let mark = indent <= 3 ? t.first : nil
            let run = mark.map { m in t.prefix { $0 == m }.count } ?? 0
            if let fence = open {
                if mark == fence.mark, run >= fence.length, t.dropFirst(run).trimmingCharacters(in: .whitespaces).isEmpty {
                    open = nil
                }
                continue
            }
            if let mark, mark == "`" || mark == "~", run >= 3, !(mark == "`" && t.dropFirst(run).contains("`")) {
                open = (mark, run)
                out += ["", "(code block skipped)", ""]
                continue
            }
            out.append(line)
        }
        return out.joined(separator: "\n")
    }

    /// Replaces each markdown table with one note: lines starting and ending with |, or a header
    /// line with a | followed by a delimiter row (`--- | :---:`), through the last line with a |.
    static func replaceTables(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var out: [String] = []
        var inTable = false
        for (i, line) in lines.enumerated() {
            let t = line.trimmingCharacters(in: .whitespaces)
            let edged = t.hasPrefix("|") && t.hasSuffix("|") && t.count > 1
            let startsGitHubTable = cells(t).count > 1 && i + 1 < lines.count
                && delimiterWidth(lines[i + 1]) == cells(t).count
            if edged || startsGitHubTable || (inTable && t.contains("|")) {
                if !inTable { out.append("(table skipped)") }
                inTable = true
            } else {
                inTable = false
                out.append(line)
            }
        }
        return out.joined(separator: "\n")
    }

    /// A row's cells, without the edge pipes.
    private static func cells(_ line: String) -> [String] {
        var row = line.trimmingCharacters(in: .whitespaces)
        if row.hasPrefix("|") { row.removeFirst() }
        if row.hasSuffix("|"), !row.hasSuffix("\\|") { row.removeLast() }
        // `\|` is a pipe inside a cell, not a column break.
        var cells: [String] = [], cell = "", escaped = false
        for ch in row {
            if ch == "|", !escaped { cells.append(cell); cell = "" } else { cell.append(ch) }
            escaped = ch == "\\" && !escaped
        }
        cells.append(cell)
        return cells.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// How many columns a delimiter row (`--- | :---: | ---:`, edge pipes or not) has; nil when
    /// the line isn't one.
    private static func delimiterWidth(_ line: String) -> Int? {
        guard line.contains("|") else { return nil }
        let row = cells(line)
        let isDelimiter = row.allSatisfy { cell in
            let core = cell.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            return !core.isEmpty && core.allSatisfy { $0 == "-" }
        }
        return isDelimiter ? row.count : nil
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
