// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OfflineDemo",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(path: "../../../")
    ],
    targets: [
        .executableTarget(
            name: "OfflineDemo",
            dependencies: [
                .product(name: "NDKSwiftCore", package: "relay-intelligence"),
                .product(name: "NDKSwiftNostrDB", package: "relay-intelligence")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
                .unsafeFlags(["-parse-as-library"])
            ]
        )
    ]
)
