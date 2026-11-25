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
    public static let maxHeaderBytes = 64_000

    public static func parse(_ data: Data) -> Parse {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerEnd = data.range(of: separator) else {
            return data.count > maxHeaderBytes ? .invalid("headers too large") : .incomplete
        }
        guard headerEnd.lowerBound <= maxHeaderBytes else { return .invalid("headers too large") }
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
        response(status, (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8))
    }

    public static func json<T: Encodable>(_ status: Int, _ value: T) -> Data {
        response(status, (try? JSONEncoder().encode(value)) ?? Data("{}".utf8))
    }

    private static func response(_ status: Int, _ body: Data) -> Data {
        let reason = [200: "OK", 202: "Accepted", 400: "Bad Request", 403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed",
                      415: "Unsupported Media Type", 500: "Internal Server Error"][status] ?? "OK"
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        head += "Content-Type: application/json\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: close\r\n\r\n"
        return Data(head.utf8) + body
    }
}
