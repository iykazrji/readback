import Foundation

/// Rewrites a cleaned reply (`SpeechText.clean`) so it sounds like a person reading it rather
/// than a parser: a path says only its file, a file says its dot, commit hashes go, and code
/// symbols become words. Plain prose passes through untouched. Rules only, on purpose: instant,
/// on the Mac, and the same every time. The owner chose this first step on 2026-11-25, after
/// hearing replies read paths and ".py" literally; a summarising model may come later.
public enum SpokenText {
    public static func rewrite(_ text: String) -> String {
        var out = rewriteWords(text)
        out = joinHashes(out)
        out = rewriteSymbols(out)
        return tidy(out)
    }

    // MARK: Word by word

    /// Stands in for a removed commit hash until the sentence around it is tidied.
    private static let hashMark = "\u{1}"

    private static func rewriteWords(_ text: String) -> String {
        let words = try! NSRegularExpression(pattern: #"\S+"#)
        var out = text
        let ns = text as NSString
        let matches = words.matches(in: text, range: NSRange(location: 0, length: ns.length))
        var previous: [String] = matches.map { ns.substring(with: $0.range) }
        for (index, match) in matches.enumerated().reversed() {
            let word = ns.substring(with: match.range)
            let before = index > 0 ? previous[index - 1] : ""
            guard let spoken = rewriteWord(word, after: before), spoken != word else { continue }
            out = (out as NSString).replacingCharacters(in: match.range, with: spoken)
            previous[index] = spoken
        }
        return out
    }

    /// One whitespace-separated word, its leading brackets and quotes and trailing punctuation
    /// kept as they were.
    private static func rewriteWord(_ word: String, after before: String) -> String? {
        let lead = word.prefix { "([{\"'“‘".contains($0) }
        var rest = word.dropFirst(lead.count)
        let trail = String(rest.reversed().prefix { ".,;:!?)]}\"'”’".contains($0) }.reversed())
        rest = rest.dropLast(trail.count)
        let core = String(rest)
        guard !core.isEmpty, let spoken = rewriteCore(core, trail: trail, after: before) else { return nil }
        return String(lead) + spoken.text + (spoken.keepsTrail ? trail : "")
    }

    private static func rewriteCore(_ core: String, trail: String, after before: String) -> (text: String, keepsTrail: Bool)? {
        if isWebAddress(core) { return ("link", true) }
        if let file = fileAndLine(core) {
            let name = spokenFileName(file.path)
            guard let line = file.line else { return (name, true) }
            // "See X.swift:433 for it." → "See X dot swift, line 433, for it."
            return ("\(name), line \(line)" + (trail.isEmpty ? "," : trail), false)
        }
        if isCommitHash(core) { return (hashMark, true) }
        // ".py" on its own: the extension, said as one.
        if core.hasPrefix("."), extensions.contains(core.dropFirst().lowercased()) { return ("dot " + core.dropFirst(), true) }
        if core.hasPrefix("--"), core.count > 2, core.dropFirst(2).allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }),
           core.dropFirst(2).first?.isLetter == true {
            return (String(core.dropFirst(2)), true)
        }
        if core.hasPrefix("#"), core.count > 1, core.dropFirst().allSatisfy(\.isNumber) {
            let label = before.lowercased().trimmingCharacters(in: .punctuationCharacters)
            let number = String(core.dropFirst())
            return (["pr", "issue", "pull", "request", "ticket", "card"].contains(label) ? number : "number \(number)", true)
        }
        if core.contains("|"), let piped = replacing(core, #"(?<=\w)\|(?=\w)"#, " or "), piped != core {
            return (piped, true)
        }
        return nil
    }

    // MARK: Paths and files

    /// Extensions said as "dot ext"; anything else after a dot (e.g., 3.8, v2.0) isn't a file.
    private static let extensions: Set<String> = [
        "swift", "py", "ts", "tsx", "js", "jsx", "mjs", "cjs", "json", "md", "sh", "zsh", "bash", "toml",
        "yml", "yaml", "txt", "png", "jpg", "jpeg", "gif", "svg", "html", "css", "scss", "plist", "log",
        "ips", "zip", "go", "rs", "rb", "java", "kt", "c", "h", "cpp", "hpp", "m", "mm", "sql", "csv",
        "env", "lock", "xml", "pdf", "ipynb", "dart", "vue", "tsv", "ini", "cfg", "conf", "pem", "app",
    ]

    /// A path or a file name, with its line when it ends in `:123` or `:12-34`.
    private static func fileAndLine(_ core: String) -> (path: String, line: String?)? {
        var path = core, line: String?
        if let m = firstMatch(core, #"^(.+\.[A-Za-z][A-Za-z0-9]{0,7}):(\d+)(?:-\d+)?$"#) {
            path = m[1]; line = m[2]
        }
        if path.contains("/") {
            guard !path.contains("://"), isPath(path) else { return nil }
            return (path, line)
        }
        return hasFileExtension(path) ? (path, line) : nil
    }

    /// Which slashes are a file-system path worth shortening to its last part:
    /// - one that ends in a file, or starts with ~/ ./ ../;
    /// - a relative one with two or more slashes that looks like folders (ends in /, or a part
    ///   has . _ - ~ or a digit), so "Close/Esc/Stop" stays a list.
    /// Left alone: one slash between words (on/off, fix/branch), a command (/readback:speak),
    /// and an absolute path with no file (/workspace/departments/[slug]), which is often the
    /// very thing the sentence is about. (Rules checked against the owner's History, 2026-11-25.)
    private static func isPath(_ path: String) -> Bool {
        let parts = path.split(separator: "/").map(String.init)
        if let last = parts.last, hasFileExtension(last) { return true }
        if path.hasPrefix("~/") || path.hasPrefix("./") || path.hasPrefix("../") { return true }
        if path.hasPrefix("/") { return false }
        guard parts.count >= 3 else { return false }
        return path.hasSuffix("/") || parts.contains { $0.contains(where: { "._-~".contains($0) || $0.isNumber }) }
    }

    private static func hasFileExtension(_ name: String) -> Bool {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return false }
        let stem = name[..<dot], ext = name[name.index(after: dot)...]
        return extensions.contains(ext.lowercased()) && stem.contains(where: \.isLetter)
            && stem.allSatisfy { $0.isLetter || $0.isNumber || "_-+@.".contains($0) }
    }

    /// "Sources/Window/SetupSheet.swift" → "SetupSheet dot swift"; "~/Library/Logs/" → "Logs";
    /// "Readback.app" → "Readback app".
    private static func spokenFileName(_ path: String) -> String {
        let name = path.split(separator: "/").last.map(String.init) ?? path
        guard hasFileExtension(name), let dot = name.lastIndex(of: ".") else { return name }
        let stem = String(name[..<dot]), ext = String(name[name.index(after: dot)...])
        return ext.lowercased() == "app" ? "\(stem) app" : "\(stem) dot \(ext)"
    }

    private static let webEndings = "com|io|dev|org|net|ai|co|sh|me|so|gg|tv|edu|gov|uk|us|de|page|site|cloud|xyz|run|fm"

    /// A web address without its https:// (cleaned replies already say "link" for full URLs).
    private static func isWebAddress(_ core: String) -> Bool {
        firstMatch(core, #"^/?(?:[A-Za-z0-9-]+\.)+(?:\#(webEndings))/\S*$"#) != nil
    }

    /// 7 to 40 lowercase hex characters with at least one digit and one letter: a commit.
    private static func isCommitHash(_ core: String) -> Bool {
        (7...40).contains(core.count) && core.allSatisfy { $0.isHexDigit && !$0.isUppercase }
            && core.contains(where: \.isNumber) && core.contains(where: \.isLetter)
    }

    // MARK: Whole text

    /// Removes the hashes: a range of them goes whole ("f3f6f2e to e3cbc37"), and so does the
    /// little word that led into one ("Committed as d0bf2ea." → "Committed.").
    private static func joinHashes(_ text: String) -> String {
        var out = text
        out = replacing(out, "\(hashMark)\\s*(?:to|→|->|\\.\\.\\.?)\\s*\(hashMark)", hashMark) ?? out
        out = replacing(out, "\\s+(?:as|in|at|is)\\s+\(hashMark)", "") ?? out
        out = replacing(out, "\\s*\(hashMark)", "") ?? out
        return out
    }

    private static func rewriteSymbols(_ text: String) -> String {
        var out = text
        let rules: [(String, String)] = [
            // snake_case words: email_address → email address
            (#"\b([a-z][a-z0-9]*)_(?=[a-z0-9])"#, "$1 "),
            (#"\s*(?:→|->|=>)\s*"#, " to "),
            (#"\s*(?:←|<-)\s*"#, " from "),
            (#"(\d)\s*×\s*(\d)"#, "$1 by $2"),
            (#"\s*&&\s*"#, " and "),
            (#"\s+&\s+"#, " and "),
            (#"\b(\d+(?:\.\d+)?)\s?ms\b"#, "$1 milliseconds"),
            (#"\b(1)\s?pt\b"#, "$1 point"),
            (#"\b(\d+(?:\.\d+)?)\s?pt\b"#, "$1 points"),
            (#"\b(1)\s?px\b"#, "$1 pixel"),
            (#"\b(\d+(?:\.\d+)?)\s?px\b"#, "$1 pixels"),
            (#"\b(1)s\b"#, "$1 second"),
            (#"\b(\d{1,3}(?:\.\d+)?)s\b"#, "$1 seconds"),
        ]
        // snake_case runs repeat until every underscore in the word is gone.
        for (pattern, template) in rules {
            var previous: String
            repeat {
                previous = out
                out = replacing(out, pattern, template) ?? out
            } while out != previous && pattern.contains("_(?=")
        }
        return out
    }

    private static func tidy(_ text: String) -> String {
        var out = text
        out = replacing(out, #"\(\s+"#, "(") ?? out
        // A space before closing punctuation, left by a removed hash ("checked out at e4d46ce0.");
        // only before punctuation that ends a word, so ".local/" and ".tint" keep their space.
        out = replacing(out, #"\s+([.,;:!?)\]])(?=\s|$)"#, "$1") ?? out
        out = replacing(out, #"[ \t]{2,}"#, " ") ?? out
        return out
    }

    // MARK: Regex helpers

    private static func replacing(_ text: String, _ pattern: String, _ template: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    private static func firstMatch(_ text: String, _ pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            Range(m.range(at: i), in: text).map { String(text[$0]) } ?? ""
        }
    }
}

extension SpeechText {
    /// A reply as the voice reads it: markdown cleaned, then rewritten for the ear.
    public static func spoken(_ markdown: String) -> String {
        SpokenText.rewrite(clean(markdown))
    }
}
