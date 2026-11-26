import Foundation
import Network
import ReadbackCore

/// The control server's sockets, on 127.0.0.1 only. What a request means is ReadbackCore's
/// ControlRequest; what to do about it is the `handle` the app passes in.
final class ControlServer {
    let port = ReadbackApp.port()
    private let handle: @MainActor (ControlRequest) -> Data
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "local.readback.control")

    init(handle: @escaping @MainActor (ControlRequest) -> Data) {
        self.handle = handle
    }

    func start() throws {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        params.allowLocalEndpointReuse = true
        let listener = try NWListener(using: params)
        let port = self.port
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready: Log.info("control server listening on 127.0.0.1:\(port)")
            case .failed(let error): Log.error("control server failed: \(error)")
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.start(queue: queue)
        self.listener = listener
    }

    /// A client gets this long to send its request and read the answer.
    private static let deadline: TimeInterval = 5
    /// Hooks open one connection at a time; anything past this many at once is turned away.
    private static let maxOpen = 16
    /// Touched only on `queue`.
    private var open = 0

    private func accept(_ connection: NWConnection) {
        guard open < Self.maxOpen else {
            Log.error("turned away a control connection: \(open) already open")
            connection.cancel()
            return
        }
        open += 1
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed: connection.cancel()
            case .cancelled: self?.open -= 1
            default: break
            }
        }
        connection.start(queue: queue)
        // One clock for the socket's timer and the handler's check: uptime, which the wall
        // clock moving (sleep, a time change) doesn't touch.
        let expires = ProcessInfo.processInfo.systemUptime + Self.deadline
        queue.asyncAfter(deadline: .now() + Self.deadline) {
            if connection.state != .cancelled { connection.cancel() }
        }
        receive(connection, buffer: Data(), expires: expires)
    }

    private func receive(_ connection: NWConnection, buffer: Data, expires: TimeInterval) {
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
                if isComplete { connection.cancel() } else { self.receive(connection, buffer: buffer, expires: expires) }
            case .invalid(let reason):
                Log.error("rejected a control request: \(reason)")
                self.send(HTTPResponse.json(400, ["error": reason]), on: connection)
            case .complete(let request):
                switch ControlRequest.parse(request, port: self.port) {
                case .failure(let refusal):
                    // The status and Readback's own message: the caller's path and method can hold anything.
                    Log.error("refused a control request: \(refusal.status) \(refusal.message)")
                    self.send(HTTPResponse.json(refusal.status, ["error": refusal.message]), on: connection)
                case .success(let parsed):
                    Task { @MainActor in
                        // The caller gave up at the deadline (and may have tried again): a
                        // request the app only reaches after that isn't carried out.
                        guard ProcessInfo.processInfo.systemUptime < expires else {
                            Log.error("dropped a control request: the app was busy past its \(Int(Self.deadline)) s deadline")
                            connection.cancel()
                            return
                        }
                        self.send(self.handle(parsed), on: connection)
                    }
                }
            }
        }
    }

    private func send(_ data: Data, on connection: NWConnection) {
        connection.send(content: data, completion: .contentProcessed { error in
            if let error { Log.error("control response failed: \(error)") }
            connection.cancel()
        })
    }
}
