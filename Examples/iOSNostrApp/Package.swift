// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "iOSNostrApp",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "iOSNostrApp",
            targets: ["iOSNostrApp"]
        )
    ],
    dependencies: [
        .package(name: "NDKSwift", path: "../..")
    ],
    targets: [
        .target(
            name: "iOSNostrApp",
            dependencies: [
                .product(name: "NDKSwift", package: "NDKSwift")
            ],
            path: ".",
            sources: ["iOSNostrApp.swift", "ContentView.swift", "NostrViewModel.swift"]
        )
    ]
)