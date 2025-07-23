// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Olas",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "Olas",
            dependencies: [
                .product(name: "NDKSwift", package: "NDKSwift")
            ],
            path: "Olas"
        )
    ]
)