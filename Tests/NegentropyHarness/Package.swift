// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "NegentropyHarness",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "NegentropyHarness",
            dependencies: [
                .product(name: "NDKSwift", package: "negentropy")
            ],
            path: ".",
            sources: ["main.swift"]
        )
    ]
)