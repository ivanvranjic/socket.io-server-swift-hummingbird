// swift-tools-version:6.2
import PackageDescription

// Separate package from socket.io-server-swift because hummingbird-websocket requires Swift 6.2 / macOS 14,
// and a package-wide platform bump would break consumers (e.g. Vapor apps targeting macOS 13).
let package = Package(
    name: "socket.io-server-swift-hummingbird",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "SocketIOHummingbird", targets: ["SocketIOHummingbird"]),
    ],
    dependencies: [
        .package(path: "../socket.io-server-swift"),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.20.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird-websocket.git", from: "2.8.0"),
    ],
    targets: [
        .target(
            name: "SocketIOHummingbird",
            dependencies: [
                .product(name: "SocketIOCore", package: "socket.io-server-swift"),
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdWebSocket", package: "hummingbird-websocket"),
            ]
        ),
        .executableTarget(
            name: "InteropServer",
            dependencies: [
                .target(name: "SocketIOHummingbird"),
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdWebSocket", package: "hummingbird-websocket"),
            ],
            path: "Examples/InteropServer"
        ),
    ]
)
