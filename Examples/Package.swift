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
                .product(name: "NDKSwift", package: "negentropy")
            ],
            path: "Sources/RelayCollectionDemo"
        ),
        .executableTarget(
            name: "NIP77Demo",
            dependencies: [
                .product(name: "NDKSwift", package: "negentropy")
            ],
            path: "Sources/NIP77Demo"
        ),
        .executableTarget(
            name: "TestNegentropyProtocol",
            dependencies: [
                .product(name: "NDKSwift", package: "negentropy")
            ],
            path: "Sources/TestNegentropyProtocol"
        )
    ]
)