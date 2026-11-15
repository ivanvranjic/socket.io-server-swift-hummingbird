@_exported import SocketIOCore
import Foundation
import Hummingbird
import HummingbirdWebSocket
import HTTPTypes
import NIOHTTP1

extension RouterMethods where Context: WebSocketRequestContext, Self: _HB_SendableMetatype {
    /// Mounts a Socket.IO server on a WebSocket router.
    ///
    /// ```swift
    /// let io = SocketIOServer()
    /// let wsRouter = Router(context: BasicWebSocketRequestContext.self)
    /// wsRouter.socketIO(io)                                    // /socket.io
    /// let app = Application(
    ///     router: router,
    ///     server: .http1WebSocketUpgrade(
    ///         webSocketRouter: wsRouter,
    ///         configuration: .init(ws: .init(maxFrameSize: io.configuration.maxPayload))
    ///     )
    /// )
    /// ```
    /// Set the WebSocket `maxFrameSize` to at least `io.configuration.maxPayload`, otherwise large messages are rejected.
    @discardableResult
    public func socketIO(_ server: SocketIOServer, path: RouterPath = "socket.io") -> Self {
        ws(path, shouldUpgrade: { request, _ in
            let query = Self.queryItems(of: request)
            guard query["EIO"] == "4", query["transport"] == "websocket" else {
                throw HTTPError(
                    .badRequest,
                    message: "Only Engine.IO v4 over WebSocket is supported. Set transports: [\"websocket\"] on the client."
                )
            }
            return .upgrade([:])
        }, onUpgrade: { inbound, outbound, context in
            let request = context.request
            let transport = HummingbirdTransport()
            let connection = server.accept(
                transport: transport,
                request: SocketIOUpgradeRequest(
                    headers: Self.httpHeaders(of: request),
                    url: request.uri.string,
                    query: Self.queryItems(of: request),
                    remoteAddress: nil
                )
            )
            defer { connection.transportDidClose() }

            try await withThrowingTaskGroup(of: Void.self) { group in
                // Outgoing frames go through one ordered queue, because `SocketIOTransport.send` is synchronous.
                group.addTask {
                    for await item in transport.outgoing {
                        switch item {
                        case .text(let text):
                            try await outbound.write(.text(text))
                        case .close:
                            try await outbound.close(.normalClosure, reason: nil)
                            return
                        }
                    }
                }
                group.addTask {
                    for try await message in inbound.messages(maxSize: server.configuration.maxPayload) {
                        switch message {
                        case .text(let text): connection.receive(text: text)
                        case .binary: connection.receiveBinary()
                        }
                    }
                }
                // Whichever side finishes first (peer closed, or server closed the transport) ends the connection.
                _ = try await group.next()
                transport.finish()
                group.cancelAll()
            }
        })
    }

    private static func queryItems(of request: Request) -> [String: String] {
        var result: [String: String] = [:]
        for item in URLComponents(string: request.uri.string)?.queryItems ?? [] {
            result[item.name] = item.value ?? ""
        }
        return result
    }

    private static func httpHeaders(of request: Request) -> HTTPHeaders {
        var headers = HTTPHeaders()
        for field in request.headers {
            headers.add(name: field.name.rawName, value: field.value)
        }
        return headers
    }
}

/// Bridges the synchronous `SocketIOTransport` API onto Hummingbird's async outbound writer.
final class HummingbirdTransport: SocketIOTransport, Sendable {
    enum Outgoing: Sendable {
        case text(String)
        case close
    }

    let outgoing: AsyncStream<Outgoing>
    private let continuation: AsyncStream<Outgoing>.Continuation

    init() {
        (outgoing, continuation) = AsyncStream.makeStream()
    }

    func send(_ text: String) { continuation.yield(.text(text)) }

    func close() {
        continuation.yield(.close)
        continuation.finish()
    }

    func finish() { continuation.finish() }
}
