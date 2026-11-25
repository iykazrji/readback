import Foundation
import Network
import ReadbackCore

/// Local HTTP endpoint the agent hooks call. Listens on 127.0.0.1 only.
///   GET  /health   -> {"ok","speaking","phase","session","current","count","speed","auto":{tool:bool}}
///   POST /speak    {"text","source","cwd","session"?,"autoplay"?} -> reads it, or keeps it as the last reply
///   POST /stop     {"session"?} -> stops the reading (only that session's, when one is named)
///   POST /session  {"session","enabled"?} -> that session's read-aloud switch, set or read
///   POST /auto     {"tool","enabled"?} -> a tool's read-every-reply switch, set or read
///   POST /voice    {"engine"?,"voice"?,"model"?,"lang"?} -> the voice settings, set or read
///   POST /engine   {"action"?: "install"|"remove"} -> the on-device engine's state, after starting the action
final class ControlServer {
    static let port: UInt16 = 8908

    struct Handlers {
        var speak: @MainActor (SpeakRequest) -> Void
        var stop: @MainActor (_ session: String?) -> Void
        /// Plays the session's newest reply from the history now; false when it has none.
        var replay: @MainActor (_ session: String) -> Bool
        var session: @MainActor (_ id: String, _ enabled: Bool?) -> Bool
        var auto: @MainActor (_ tool: Tool, _ enabled: Bool?) -> Bool
        /// Sets any of engine, voice, model, lang that are given; returns the current voice settings
        /// or an error message.
        var voice: @MainActor (VoiceRequest) -> Result<[String: Any], VoiceRequest.Invalid>
        /// "install", "remove" or nil (just report); returns the engine's state.
        var engine: @MainActor (_ action: String?) -> String
        var status: @MainActor () -> [String: Any]
    }

    private struct EngineRequest: Decodable { var action: String? }

    struct VoiceRequest: Decodable {
        var engine: String?
        var voice: String?
        var model: String?
        var lang: String?
        struct Invalid: Error { let message: String }
    }

    private struct StopRequest: Decodable { var session: String? }
    private struct SessionRequest: Decodable { var session: String; var enabled: Bool? }
    private struct AutoRequest: Decodable { var tool: String; var enabled: Bool? }

    private let handlers: Handlers
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "local.readback.control")

    init(handlers: Handlers) {
        self.handlers = handlers
    }

    func start() throws {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: Self.port)!)
        params.allowLocalEndpointReuse = true
        let listener = try NWListener(using: params)
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready: Log.info("control server listening on 127.0.0.1:\(Self.port)")
            case .failed(let error): Log.error("control server failed: \(error)")
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.start(queue: queue)
        self.listener = listener
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error {
                Log.error("control connection error: \(error)")
                connection.cancel()
                return
            }
            var buffer = buffer
            if let data { buffer.append(data) }
            switch HTTPRequest.parse(buffer) {
            case .incomplete:
                if isComplete { connection.cancel() } else { self.receive(connection, buffer: buffer) }
            case .invalid(let reason):
                Log.error("rejected a control request: \(reason)")
                self.send(HTTPResponse.json(400, ["error": reason]), on: connection)
            case .complete(let request):
                Task { @MainActor in
                    let response = self.route(request)
                    self.send(response, on: connection)
                }
            }
        }
    }

    @MainActor
    private func route(_ request: HTTPRequest) -> Data {
        switch (request.method, request.path) {
        case ("GET", "/health"):
            return HTTPResponse.json(200, handlers.status().merging(["ok": true]) { a, _ in a })
        case ("POST", "/speak"):
            do {
                let speak = try JSONDecoder().decode(SpeakRequest.self, from: request.body)
                handlers.speak(speak)
                return HTTPResponse.json(202, ["accepted": true])
            } catch {
                Log.error("bad /speak body: \(error)")
                return HTTPResponse.json(400, ["error": "expected JSON with a text field"])
            }
        case ("POST", "/stop"):
            let session = request.body.isEmpty ? nil : (try? JSONDecoder().decode(StopRequest.self, from: request.body))?.session
            handlers.stop(session)
            return HTTPResponse.json(200, ["ok": true])
        case ("POST", "/replay"):
            guard let session = (try? JSONDecoder().decode(StopRequest.self, from: request.body))?.session else {
                return HTTPResponse.json(400, ["error": #"expected {"session":"<id>"}"#])
            }
            return HTTPResponse.json(200, ["played": handlers.replay(session)])
        case ("POST", "/session"):
            do {
                let body = try JSONDecoder().decode(SessionRequest.self, from: request.body)
                return HTTPResponse.json(200, ["session": body.session, "enabled": handlers.session(body.session, body.enabled)])
            } catch {
                Log.error("bad /session body: \(error)")
                return HTTPResponse.json(400, ["error": #"expected {"session":"<id>","enabled":true}"#])
            }
        case ("POST", "/auto"):
            guard let body = try? JSONDecoder().decode(AutoRequest.self, from: request.body),
                  let tool = Tool(source: body.tool) else {
                return HTTPResponse.json(400, ["error": #"expected {"tool":"claude|codex|opencode","enabled":true}"#])
            }
            return HTTPResponse.json(200, ["tool": tool.rawValue, "enabled": handlers.auto(tool, body.enabled)])
        case ("POST", "/voice"):
            let body = request.body.isEmpty ? VoiceRequest() : (try? JSONDecoder().decode(VoiceRequest.self, from: request.body))
            guard let body else { return HTTPResponse.json(400, ["error": #"expected {"engine","voice","model","lang"}"#]) }
            switch handlers.voice(body) {
            case .success(let current): return HTTPResponse.json(200, current)
            case .failure(let invalid): return HTTPResponse.json(400, ["error": invalid.message])
            }
        case ("POST", "/engine"):
            let action = request.body.isEmpty ? nil : (try? JSONDecoder().decode(EngineRequest.self, from: request.body))?.action
            guard action == nil || action == "install" || action == "remove" else {
                return HTTPResponse.json(400, ["error": "action is install or remove"])
            }
            return HTTPResponse.json(200, ["runtime": handlers.engine(action)])
        case (_, "/health"), (_, "/speak"), (_, "/stop"), (_, "/replay"), (_, "/session"), (_, "/auto"), (_, "/voice"), (_, "/engine"):
            return HTTPResponse.json(405, ["error": "method not allowed"])
        default:
            return HTTPResponse.json(404, ["error": "not found"])
        }
    }

    private func send(_ data: Data, on connection: NWConnection) {
        connection.send(content: data, completion: .contentProcessed { error in
            if let error { Log.error("control response failed: \(error)") }
            connection.cancel()
        })
    }
}
