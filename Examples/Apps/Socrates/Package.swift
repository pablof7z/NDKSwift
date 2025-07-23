// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Socrates",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "Socrates",
            targets: ["Socrates"]
        )
    ],
    dependencies: [
        .package(path: "../../../")
    ],
    targets: [
        .executableTarget(
            name: "Socrates",
            dependencies: [
                .product(name: "NDKSwift", package: "NDKSwift")
            ],
            path: "Sources"
        )
    ]
)