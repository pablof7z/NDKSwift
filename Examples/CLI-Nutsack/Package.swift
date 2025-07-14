// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CLI-Nutsack",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(path: "../.."),
    ],
    targets: [
        .executableTarget(
            name: "CLI-Nutsack",
            dependencies: [
                .product(name: "NDKSwift", package: "NDKSwift"),
            ]
        ),
    ]
)