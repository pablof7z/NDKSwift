// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "NDKSwift",
    platforms: [
        .iOS(.v15),
        .macOS(.v14),
        .tvOS(.v15),
        .watchOS(.v8),
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "NDKSwift",
            targets: ["NDKSwift"]
        ),
        .executable(
            name: "E2ECashuTest",
            targets: ["E2ECashuTest"]
        ),
        .executable(
            name: "SimpleCashuTest",
            targets: ["SimpleCashuTest"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/anquii/CryptoSwiftWrapper.git", from: "1.4.3"),
        .package(url: "https://github.com/GigaBitcoin/secp256k1.swift.git", from: "0.21.0"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.3"),
        .package(url: "https://github.com/zeugmaster/CashuSwift.git", branch: "main"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "NDKSwift",
            dependencies: [
                .product(name: "CryptoSwiftWrapper", package: "CryptoSwiftWrapper"),
                .product(name: "P256K", package: "secp256k1.swift"),
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "CashuSwift", package: "CashuSwift"),
            ],
            exclude: [
                "Outbox/README.md",
                "Outbox/IMPLEMENTATION_SUMMARY.md"
            ]
        ),
        .testTarget(
            name: "NDKSwiftTests",
            dependencies: ["NDKSwift"]
        ),
        .executableTarget(
            name: "E2ECashuTest",
            dependencies: ["NDKSwift"]
        ),
        .executableTarget(
            name: "SimpleCashuTest",
            dependencies: ["NDKSwift"]
        ),
    ]
)
