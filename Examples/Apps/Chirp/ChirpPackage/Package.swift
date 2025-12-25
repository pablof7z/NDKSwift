// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ChirpFeature",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(
            name: "ChirpFeature",
            targets: ["ChirpFeature"]
        ),
    ],
    dependencies: [
        .package(path: "../../../..")
    ],
    targets: [
        .target(
            name: "ChirpFeature",
            dependencies: [
                .product(name: "NDKSwiftCore", package: "NDKSwift-observable-relays"),
                .product(name: "NDKSwiftUI", package: "NDKSwift-observable-relays"),
                .product(name: "NDKSwiftNostrDB", package: "NDKSwift-observable-relays"),
                .product(name: "NDKSwiftCashu", package: "NDKSwift-observable-relays")
            ]
        ),
        .testTarget(
            name: "ChirpFeatureTests",
            dependencies: [
                "ChirpFeature"
            ]
        ),
    ]
)
