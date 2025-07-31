// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "NDKSwift",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .tvOS(.v17),
        .watchOS(.v10),
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "NDKSwift",
            targets: ["NDKSwift"]
        ),
        .library(
            name: "NDKSwiftUI",
            targets: ["NDKSwiftUI"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/anquii/CryptoSwiftWrapper.git", from: "1.4.3"),
        .package(url: "https://github.com/zeugmaster/swift-secp256k1.git", revision: "73cf2403b7a69de8efc612d251a6e0d01211e1c4"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.3"),
        .package(url: "https://github.com/pablof7z/CashuSwift.git", from: "0.1.1"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "NDKSwift",
            dependencies: [
                .product(name: "CryptoSwiftWrapper", package: "CryptoSwiftWrapper"),
                .product(name: "secp256k1", package: "swift-secp256k1"),
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "CashuSwift", package: "CashuSwift"),
            ],
            resources: [
                .process("Wallets/Common/README.md")
            ]
        ),
        .target(
            name: "NDKSwiftUI",
            dependencies: [
                "NDKSwift"
            ]
        ),
        .testTarget(
            name: "NDKSwiftTests",
            dependencies: [
                "NDKSwift",
                .product(name: "CashuSwift", package: "CashuSwift"),
            ],
            resources: [
                .process("Integration/README_OutboxTests.md")
            ]
        ),
    ]
)
