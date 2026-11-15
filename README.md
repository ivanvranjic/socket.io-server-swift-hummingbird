# socket.io-server-swift-hummingbird

[Hummingbird](https://hummingbird.codes) 2 adapter for [socket.io-server-swift](../socket.io-server-swift).
Lives in its own package because `hummingbird-websocket` requires Swift 6.2 / macOS 14, which would otherwise raise the
platform floor for the Vapor adapter too.

```swift
import Hummingbird
import HummingbirdWebSocket
import SocketIOHummingbird

let io = SocketIOServer()
io.onConnection { socket in
    socket.on("chat", as: String.self) { _, text in socket.broadcast.emit("chat", text) }
}

let wsRouter = Router(context: BasicWebSocketRequestContext.self)
wsRouter.socketIO(io)                                   // mounts /socket.io

let app = Application(
    router: Router(),
    server: .http1WebSocketUpgrade(
        webSocketRouter: wsRouter,
        configuration: .init(ws: .init(maxFrameSize: io.configuration.maxPayload))
    )
)
try await app.runService()
```

Notes:
- Set the WebSocket `maxFrameSize` to at least `io.configuration.maxPayload`; Hummingbird's default (16 KB) rejects larger messages.
- Middleware on `wsRouter` (e.g. authentication) runs before the upgrade, like any Hummingbird WebSocket route. Socket.IO-level auth uses `io.use { ... }` as usual.
- Hummingbird also pings automatically (`autoPing`, 30 s) in addition to Socket.IO's own heartbeat. That is harmless.
- Call `io.shutdown()` when your app shuts down to disconnect clients cleanly.
- Clients must use the WebSocket transport only (see the core README).

## Tests

`Tests/Interop/run.sh` runs the core repo's JS client, Swift client and ping-timeout checks against `Examples/InteropServer`.
