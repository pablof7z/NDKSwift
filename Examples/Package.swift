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
        .executable(name: "DeclarativeDemo", targets: ["DeclarativeDemo"]),
        .executable(name: "ComprehensiveDeclarativeDemo", targets: ["ComprehensiveDeclarativeDemo"]),
        .executable(name: "BasicDataSourceDemo", targets: ["BasicDataSourceDemo"]),
        .executable(name: "MinimalDeclarativeDemo", targets: ["MinimalDeclarativeDemo"])
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
            name: "DeclarativeDemo",
            dependencies: [
                .product(name: "NDKSwift", package: "NDKSwift")
            ],
            path: ".",
            sources: ["DeclarativeDemo.swift"]
        ),
        .executableTarget(
            name: "ComprehensiveDeclarativeDemo",
            dependencies: [
                .product(name: "NDKSwift", package: "NDKSwift")
            ],
            path: ".",
            sources: ["ComprehensiveDeclarativeDemo.swift"]
        ),
        .executableTarget(
            name: "BasicDataSourceDemo",
            dependencies: [
                .product(name: "NDKSwift", package: "NDKSwift")
            ],
            path: ".",
            sources: ["FeatureShowcase.swift"]
        ),
        .executableTarget(
            name: "MinimalDeclarativeDemo",
            dependencies: [
                .product(name: "NDKSwift", package: "NDKSwift")
            ],
            path: ".",
            sources: ["MinimalDeclarativeDemo.swift"]
        )
    ]
)