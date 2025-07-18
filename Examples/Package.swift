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
        .executable(name: "TestNegentropyProtocol", targets: ["TestNegentropyProtocol"])
    ],
    dependencies: [
        .package(path: "..")
    ],
    targets: [
        .executableTarget(
            name: "RelayCollectionDemo",
            dependencies: [
                .product(name: "NDKSwift", package: "NDKSwift-sfodj5")
            ],
            path: "Sources/RelayCollectionDemo"
        ),
        .executableTarget(
            name: "DebugKind0Fetcher",
            dependencies: [
                .product(name: "NDKSwift", package: "NDKSwift-sfodj5")
            ],
            path: "Sources/DebugKind0Fetcher"
        ),
        .executableTarget(
            name: "NIP77Demo",
            dependencies: [
                .product(name: "NDKSwift", package: "NDKSwift-sfodj5")
            ],
            path: "Sources/NIP77Demo"
        ),
        .executableTarget(
            name: "TestNegentropyProtocol",
            dependencies: [
                .product(name: "NDKSwift", package: "NDKSwift-sfodj5")
            ],
            path: "Sources/TestNegentropyProtocol"
        )
    ]
)