import Foundation
import Hummingbird

import SocketIOHummingbird

// Same behaviour as the Vapor InteropServer, so the shared client tests can run against it.

var config = SocketIOConfiguration()
if let v = Double(ProcessInfo.processInfo.environment["PING_INTERVAL"] ?? "") { config.pingInterval = v }
if let v = Double(ProcessInfo.processInfo.environment["PING_TIMEOUT"] ?? "") { config.pingTimeout = v }
let port = Int(ProcessInfo.processInfo.environment["PORT"] ?? "") ?? 8099

let io = SocketIOServer(configuration: config)

io.use { socket in
    guard let token = socket.handshake.auth?["token"]?.stringValue, !token.isEmpty else {
        throw SocketIOConnectError("unauthorized")
    }
    socket.setUserInfo("user", token)
}

io.onConnection { socket in
    let user = socket.userInfo["user"] as? String ?? "?"
    socket.emit("welcome", ["user": user])

    socket.on("echo") { event in socket.emit("echo", event.args[0]) }

    socket.on("sum") { event in
        let a: Int = try event.decode(at: 0)
        let b: Int = try event.decode(at: 1)
        try event.ack?(a + b)
    }

    socket.on("ask") { _ in
        let reply = try await socket.emitWithAck("question", "ping")
        socket.emit("asked", reply[0])
    }

    socket.on("join", as: String.self) { _, room in
        socket.join(room)
        socket.emit("joined", room)
    }

    socket.on("to-room") { event in
        let room: String = try event.decode(at: 0)
        let message: String = try event.decode(at: 1)
        socket.to(room).emit("room-msg", message)
    }

    socket.on("shout", as: String.self) { _, text in io.emit("all", text) }

    socket.on("kick") { _ in socket.disconnect() }

    socket.onDisconnect { _ in socket.to("r").emit("left", user) }
}

io.namespace("/admin").onConnection { socket in
    socket.emit("hello-admin", "admin")
}

let wsRouter = Router(context: BasicWebSocketRequestContext.self)
wsRouter.socketIO(io)

let app = Application(
    router: Router(),
    server: .http1WebSocketUpgrade(
        webSocketRouter: wsRouter,
        configuration: .init(ws: .init(maxFrameSize: config.maxPayload))
    ),
    configuration: .init(address: .hostname("127.0.0.1", port: port))
)
try await app.runService()
