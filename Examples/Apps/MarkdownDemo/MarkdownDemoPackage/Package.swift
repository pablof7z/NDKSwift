// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MarkdownDemoFeature",
    platforms: [.iOS(.v17)],
    products: [
        .library(
            name: "MarkdownDemoFeature",
            targets: ["MarkdownDemoFeature"]
        ),
    ],
    dependencies: [
        .package(path: "../../../..")
    ],
    targets: [
        .target(
            name: "MarkdownDemoFeature",
            dependencies: [
                .product(name: "NDKSwiftCore", package: "master"),
                .product(name: "NDKSwiftUI", package: "master"),
                .product(name: "NDKSwiftSQLite", package: "master"),
                .product(name: "NDKSwiftNostrDB", package: "master")
            ]
        ),
        .testTarget(
            name: "MarkdownDemoFeatureTests",
            dependencies: [
                "MarkdownDemoFeature"
            ]
        ),
    ]
)
