// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "OutboxDebugger",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "outbox-debug", targets: ["OutboxDebugger"])
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
        )
    ]
)