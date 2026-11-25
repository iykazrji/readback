import Foundation

/// JSON that keeps object keys in the order they were written, so editing someone's
/// settings file changes only what Readback adds or removes. Numbers keep their original
/// text. Output is two-space indented, the same layout `jq .` writes.
public indirect enum JSONValue: Equatable {
    case object([(key: String, value: JSONValue)])
    case array([JSONValue])
    case string(String)
    case number(String)
    case bool(Bool)
    case null

    public static func == (lhs: JSONValue, rhs: JSONValue) -> Bool {
        switch (lhs, rhs) {
        case let (.object(a), .object(b)):
            return a.count == b.count && zip(a, b).allSatisfy { $0.key == $1.key && $0.value == $1.value }
        case let (.array(a), .array(b)): return a == b
        case let (.string(a), .string(b)): return a == b
        case let (.number(a), .number(b)): return a == b
        case let (.bool(a), .bool(b)): return a == b
        case (.null, .null): return true
        default: return false
        }
    }

    // MARK: Reading and changing

    public subscript(key: String) -> JSONValue? {
        guard case .object(let pairs) = self else { return nil }
        return pairs.first { $0.key == key }?.value
    }

    /// Sets `key` on an object, in place if it exists, appended if not.
    public mutating func set(_ key: String, _ value: JSONValue) {
        guard case .object(var pairs) = self else { return }
        if let i = pairs.firstIndex(where: { $0.key == key }) {
            pairs[i].value = value
        } else {
            pairs.append((key, value))
        }
        self = .object(pairs)
    }

    public mutating func remove(_ key: String) {
        guard case .object(let pairs) = self else { return }
        self = .object(pairs.filter { $0.key != key })
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let items) = self { return items }
        return nil
    }

    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    public var isObject: Bool {
        if case .object = self { return true }
        return false
    }

    // MARK: Parsing

    public struct ParseError: Error, CustomStringConvertible, Equatable {
        public let message: String
        public let offset: Int
        public var description: String { "\(message) at character \(offset)" }
    }

    public static func parse(_ text: String) throws -> JSONValue {
        var parser = Parser(Array(text.unicodeScalars))
        parser.skipSpace()
        let value = try parser.value()
        parser.skipSpace()
        guard parser.atEnd else { throw parser.fail("unexpected text after the JSON") }
        return value
    }

    private struct Parser {
        let s: [Unicode.Scalar]
        var i = 0
        init(_ s: [Unicode.Scalar]) { self.s = s }

        var atEnd: Bool { i >= s.count }
        func fail(_ message: String) -> ParseError { ParseError(message: message, offset: i) }

        mutating func skipSpace() {
            while i < s.count, [" ", "\n", "\r", "\t"].contains(s[i]) { i += 1 }
        }

        mutating func expect(_ c: Unicode.Scalar) throws {
            guard i < s.count, s[i] == c else { throw fail("expected \(c)") }
            i += 1
        }

        mutating func literal(_ word: String, _ value: JSONValue) throws -> JSONValue {
            for c in word.unicodeScalars { try expect(c) }
            return value
        }

        mutating func value() throws -> JSONValue {
            guard i < s.count else { throw fail("unexpected end") }
            switch s[i] {
            case "{": return try object()
            case "[": return try array()
            case "\"": return .string(try string())
            case "t": return try literal("true", .bool(true))
            case "f": return try literal("false", .bool(false))
            case "n": return try literal("null", .null)
            case "-", "0"..."9": return try number()
            default: throw fail("unexpected character \(s[i])")
            }
        }

        mutating func object() throws -> JSONValue {
            try expect("{")
            var pairs: [(key: String, value: JSONValue)] = []
            skipSpace()
            if i < s.count, s[i] == "}" { i += 1; return .object(pairs) }
            while true {
                skipSpace()
                let key = try string()
                skipSpace()
                try expect(":")
                skipSpace()
                pairs.append((key, try value()))
                skipSpace()
                guard i < s.count else { throw fail("unexpected end in an object") }
                if s[i] == "," { i += 1; continue }
                try expect("}")
                return .object(pairs)
            }
        }

        mutating func array() throws -> JSONValue {
            try expect("[")
            var items: [JSONValue] = []
            skipSpace()
            if i < s.count, s[i] == "]" { i += 1; return .array(items) }
            while true {
                skipSpace()
                items.append(try value())
                skipSpace()
                guard i < s.count else { throw fail("unexpected end in an array") }
                if s[i] == "," { i += 1; continue }
                try expect("]")
                return .array(items)
            }
        }

        mutating func string() throws -> String {
            try expect("\"")
            var out = String.UnicodeScalarView()
            while true {
                guard i < s.count else { throw fail("unterminated string") }
                let c = s[i]; i += 1
                if c == "\"" { return String(out) }
                if c != "\\" {
                    guard c.value >= 0x20 else { throw fail("control character in a string") }
                    out.append(c)
                    continue
                }
                guard i < s.count else { throw fail("unterminated escape") }
                let e = s[i]; i += 1
                switch e {
                case "\"": out.append("\"")
                case "\\": out.append("\\")
                case "/": out.append("/")
                case "b": out.append("\u{08}")
                case "f": out.append("\u{0C}")
                case "n": out.append("\n")
                case "r": out.append("\r")
                case "t": out.append("\t")
                case "u":
                    var code = try hex4()
                    if (0xD800...0xDBFF).contains(code) {
                        // A surrogate pair: 😀
                        guard i + 1 < s.count, s[i] == "\\", s[i + 1] == "u" else { throw fail("lone surrogate") }
                        i += 2
                        let low = try hex4()
                        guard (0xDC00...0xDFFF).contains(low) else { throw fail("bad surrogate pair") }
                        code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                    }
                    guard let scalar = Unicode.Scalar(code) else { throw fail("bad \\u escape") }
                    out.append(scalar)
                default: throw fail("bad escape \\\(e)")
                }
            }
        }

        mutating func hex4() throws -> UInt32 {
            guard i + 4 <= s.count else { throw fail("short \\u escape") }
            var code: UInt32 = 0
            for _ in 0..<4 {
                guard let digit = UInt32(String(s[i]), radix: 16) else { throw fail("bad hex digit") }
                code = code * 16 + digit
                i += 1
            }
            return code
        }

        mutating func number() throws -> JSONValue {
            let start = i
            if s[i] == "-" { i += 1 }
            while i < s.count, ("0"..."9").contains(s[i]) || [".", "e", "E", "+", "-"].contains(s[i]) { i += 1 }
            let text = String(String.UnicodeScalarView(s[start..<i]))
            guard Double(text) != nil else { throw fail("bad number \(text)") }
            return .number(text)
        }
    }

    // MARK: Writing

    /// Pretty JSON with a trailing newline, the layout `jq .` writes.
    public func formatted() -> String {
        var out = ""
        write(into: &out, indent: 0)
        return out + "\n"
    }

    private func write(into out: inout String, indent: Int) {
        let pad = String(repeating: "  ", count: indent)
        let inner = String(repeating: "  ", count: indent + 1)
        switch self {
        case .object(let pairs):
            if pairs.isEmpty { out += "{}"; return }
            out += "{\n"
            for (n, pair) in pairs.enumerated() {
                out += inner + Self.quote(pair.key) + ": "
                pair.value.write(into: &out, indent: indent + 1)
                out += n == pairs.count - 1 ? "\n" : ",\n"
            }
            out += pad + "}"
        case .array(let items):
            if items.isEmpty { out += "[]"; return }
            out += "[\n"
            for (n, item) in items.enumerated() {
                out += inner
                item.write(into: &out, indent: indent + 1)
                out += n == items.count - 1 ? "\n" : ",\n"
            }
            out += pad + "]"
        case .string(let s): out += Self.quote(s)
        case .number(let n): out += n
        case .bool(let b): out += b ? "true" : "false"
        case .null: out += "null"
        }
    }

    static func quote(_ s: String) -> String {
        var out = "\""
        for c in s.unicodeScalars {
            switch c {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if c.value < 0x20 || c.value == 0x7F {
                    out += String(format: "\\u%04x", c.value)
                } else {
                    out.unicodeScalars.append(c)
                }
            }
        }
        return out + "\""
    }
}
