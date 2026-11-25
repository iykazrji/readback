import Foundation

/// The small slice of HTTP/1.1 the local control server needs: one request per connection,
/// body sized by Content-Length.
public struct HTTPRequest: Equatable {
    public var method: String
    public var path: String
    public var headers: [String: String]
    public var body: Data

    public enum Parse: Equatable {
        case incomplete
        case invalid(String)
        case complete(HTTPRequest)
    }

    public static let maxBodyBytes = 2_000_000

    public static func parse(_ data: Data) -> Parse {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerEnd = data.range(of: separator) else {
            return data.count > 64_000 ? .invalid("headers too large") : .incomplete
        }
        guard let head = String(data: data[..<headerEnd.lowerBound], encoding: .utf8) else {
            return .invalid("headers aren't UTF-8")
        }
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { return .invalid("bad request line") }

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            headers[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }

        let length = Int(headers["content-length"] ?? "0") ?? -1
        guard length >= 0 else { return .invalid("bad content-length") }
        guard length <= maxBodyBytes else { return .invalid("body too large") }
        let bodyStart = headerEnd.upperBound
        guard data.count - bodyStart >= length else { return .incomplete }

        let path = String(requestLine[1]).components(separatedBy: "?")[0]
        return .complete(HTTPRequest(
            method: String(requestLine[0]).uppercased(),
            path: path,
            headers: headers,
            body: Data(data[bodyStart..<(bodyStart + length)])
        ))
    }
}

public enum HTTPResponse {
    public static func json(_ status: Int, _ object: [String: Any]) -> Data {
        let body = (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
        let reason = [200: "OK", 202: "Accepted", 400: "Bad Request", 404: "Not Found", 405: "Method Not Allowed"][status] ?? "OK"
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        head += "Content-Type: application/json\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: close\r\n\r\n"
        return Data(head.utf8) + body
    }
}

/// What the hooks send to POST /speak.
public struct SpeakRequest: Decodable, Equatable {
    public var text: String
    public var source: String?
    public var cwd: String?
    /// true: read it now. false: only keep it as the last reply. Absent: the app decides
    /// from that tool's auto-read switch.
    public var autoplay: Bool?
    /// The tool's session id, when it sent one: lets a session switch read-aloud on for itself
    /// and stop only its own reading.
    public var session: String?

    public init(text: String, source: String? = nil, cwd: String? = nil, autoplay: Bool? = nil, session: String? = nil) {
        self.text = text
        self.source = source
        self.cwd = cwd
        self.autoplay = autoplay
        self.session = session
    }

    public var tool: Tool? { source.flatMap(Tool.init(source:)) }

    /// "Claude Code · inkine": the tool, then the project folder it ran in.
    public var title: String {
        let tool = self.tool?.name ?? ((source?.isEmpty == false) ? source! : "Agent")
        guard let cwd, !cwd.isEmpty else { return tool }
        let folder = URL(fileURLWithPath: cwd).lastPathComponent
        return folder.isEmpty || folder == "/" ? tool : "\(tool) · \(folder)"
    }
}
