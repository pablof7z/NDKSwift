// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NutsackiOS",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "NutsackiOS",
            targets: ["NutsackiOS"]
        )
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .target(
            name: "NutsackiOS",
            dependencies: [
                .product(name: "NDKSwift", package: "NDKSwift-z94ws0")
            ],
            exclude: ["Info.plist"]
        )
    ]
)