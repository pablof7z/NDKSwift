// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "NDKSwiftUI-Example",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    dependencies: [
        .package(path: "../.."),
    ],
    targets: [
        .executableTarget(
            name: "NDKSwiftUI-Example",
            dependencies: [
                .product(name: "NDKSwiftUI", package: "NDKSwift"),
            ]
        ),
    ]
)