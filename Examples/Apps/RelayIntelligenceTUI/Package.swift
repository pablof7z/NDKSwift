// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RelayIntelligenceTUI",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(path: "../../../")
    ],
    targets: [
        .executableTarget(
            name: "RelayIntelligenceTUI",
            dependencies: [
                .product(name: "NDKSwiftCore", package: "relay-intelligence")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        )
    ]
)
