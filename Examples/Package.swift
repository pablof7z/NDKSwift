// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NDKSwiftExamples",
    platforms: [
        .iOS(.v15),
        .macOS(.v14)
    ],
    products: [
        .executable(name: "RelayCollectionDemo", targets: ["RelayCollectionDemo"]),
        .executable(name: "DebugKind0Fetcher", targets: ["DebugKind0Fetcher"]),
        .executable(name: "NIP77Demo", targets: ["NIP77Demo"]),
        .executable(name: "TestNegentropyProtocol", targets: ["TestNegentropyProtocol"]),
        .executable(name: "RealDeclarativeDemo", targets: ["RealDeclarativeDemo"]),
        .executable(name: "TestRealRelay", targets: ["TestRealRelay"]),
        .executable(name: "TestOutboxModel", targets: ["TestOutboxModel"]),
        .executable(name: "E2ETestBasicEventFlow", targets: ["E2ETestBasicEventFlow"]),
        .executable(name: "E2ETestSimple", targets: ["E2ETestSimple"])
    ],
    dependencies: [
        .package(path: "..")
    ],
    targets: [
        .executableTarget(
            name: "RelayCollectionDemo",
            dependencies: [
                .product(name: "NDKSwift", package: "NDKSwift")
            ],
            path: "Sources/RelayCollectionDemo"
        ),
        .executableTarget(
            name: "DebugKind0Fetcher",
            dependencies: [
                .product(name: "NDKSwift", package: "NDKSwift")
            ],
            path: "Sources/DebugKind0Fetcher"
        ),
        .executableTarget(
            name: "NIP77Demo",
            dependencies: [
                .product(name: "NDKSwift", package: "NDKSwift")
            ],
            path: "Sources/NIP77Demo"
        ),
        .executableTarget(
            name: "TestNegentropyProtocol",
            dependencies: [
                .product(name: "NDKSwift", package: "NDKSwift")
            ],
            path: "Sources/TestNegentropyProtocol"
        ),
        .executableTarget(
            name: "RealDeclarativeDemo",
            dependencies: [
                .product(name: "NDKSwift", package: "NDKSwift")
            ],
            path: "Sources/RealDeclarativeDemo"
        ),
        .executableTarget(
            name: "TestRealRelay",
            dependencies: [
                .product(name: "NDKSwift", package: "NDKSwift")
            ],
            path: ".",
            sources: ["TestRealRelay.swift"]
        ),
        .executableTarget(
            name: "TestOutboxModel",
            dependencies: [
                .product(name: "NDKSwift", package: "NDKSwift")
            ],
            path: ".",
            sources: ["TestOutboxModel.swift"]
        ),
        .executableTarget(
            name: "E2ETestBasicEventFlow",
            dependencies: [
                .product(name: "NDKSwift", package: "NDKSwift")
            ],
            path: "Sources/E2ETestBasicEventFlow"
        ),
        .executableTarget(
            name: "E2ETestSimple",
            dependencies: [
                .product(name: "NDKSwift", package: "NDKSwift")
            ],
            path: "Sources/E2ETestSimple"
        )
    ]
)