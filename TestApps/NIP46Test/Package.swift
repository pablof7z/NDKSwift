// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NIP46Test",
    platforms: [
        .macOS(.v14),
    ],
    dependencies: [
        .package(path: "../.."),
    ],
    targets: [
        .executableTarget(
            name: "NIP46Test",
            dependencies: [
                .product(name: "NDKSwiftCore", package: "NDKSwift-z94ws0"),
            ],
            path: "Sources"
        ),
    ]
)
