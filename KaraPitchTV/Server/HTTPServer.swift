import Foundation
import Network
import os

/// A small HTTP/1.1 server on Network.framework: one request per connection, then close.
/// Advertised over Bonjour as `_http._tcp` "Kara Pitch".
final class HTTPServer: @unchecked Sendable {
    static let port: UInt16 = 8080
    static let requestTimeout: Duration = .seconds(10)

    private let router: Router
    private let queue = DispatchQueue(label: "dev.ytkara.tv.server")
    /// Only touched on `queue`.
    private var listener: NWListener?

    init(router: Router) {
        self.router = router
    }

    /// Starts listening, or restarts a listener that failed (e.g. while the app was suspended).
    func start() {
        queue.async { self.startOnQueue() }
    }

    private func startOnQueue() {
        if let listener, listener.state != .cancelled, !Self.isFailed(listener.state) { return }
        listener?.cancel()
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: Self.port)!)
            listener.service = NWListener.Service(name: "Kara Pitch", type: "_http._tcp")
            listener.stateUpdateHandler = { [weak self] state in
                Logger.server.notice("listener \(String(describing: state), privacy: .public)")
                guard Self.isFailed(state), let self else { return }
                // Try again shortly: the port can stay busy for a moment after a restart.
                self.queue.asyncAfter(deadline: .now() + 2) { [weak self] in self?.startOnQueue() }
            }
            listener.newConnectionHandler = { [weak self] connection in self?.serve(connection) }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            Logger.server.error("can't listen on \(Self.port): \(String(describing: error), privacy: .public)")
        }
    }

    private static func isFailed(_ state: NWListener.State) -> Bool {
        if case .failed = state { true } else { false }
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        let router = router
        Task {
            let timeout = Task {
                try await Task.sleep(for: Self.requestTimeout)
                connection.cancel()
            }
            defer { timeout.cancel() }
            let response: HTTPResponse
            switch await Self.readRequest(connection) {
            case let .complete(request):
                response = await router.handle(request)
                Logger.server.debug("\(request.method, privacy: .public) \(request.path, privacy: .public) → \(response.status)")
            case .invalid:
                response = HTTPResponse(status: 400)
            case .incomplete:
                connection.cancel()
                return
            }
            connection.send(content: response.serialized(), contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    /// Reads until a whole request has arrived. `.incomplete` means the peer closed first.
    private static func readRequest(_ connection: NWConnection) async -> HTTPRequest.Parse {
        var buffer = Data()
        while true {
            let (chunk, done) = await withCheckedContinuation { (continuation: CheckedContinuation<(Data?, Bool), Never>) in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
                    continuation.resume(returning: (data, isComplete || error != nil))
                }
            }
            if let chunk { buffer.append(chunk) }
            let parsed = HTTPRequest.parse(buffer)
            if parsed != .incomplete || done { return parsed }
        }
    }
}
