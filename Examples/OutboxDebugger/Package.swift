// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "OutboxDebugger",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "outbox-debug", targets: ["OutboxDebugger"]),
        .executable(name: "test-publisher", targets: ["TestPublisher"])
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "OutboxDebugger",
            dependencies: [
                .product(name: "NDKSwift", package: "NDKSwift")
            ]
        ),
        .executableTarget(
            name: "TestPublisher",
            dependencies: [
                .product(name: "NDKSwift", package: "NDKSwift")
            ]
        )
    ]
)