// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NutsackiOS",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .executable(
            name: "NutsackiOS",
            targets: ["NutsackiOS"]
        )
    ],
    dependencies: [
        .package(path: "../.."),
        .package(url: "https://github.com/apple/swift-markdown.git", from: "0.5.0"),
        .package(url: "https://github.com/aheze/Popovers", from: "1.3.2"),
        .package(url: "https://github.com/Kitura/Swift-JWT.git", from: "4.0.1")
    ],
    targets: [
        .executableTarget(
            name: "NutsackiOS",
            dependencies: [
                .product(name: "NDKSwift", package: "NDKSwift"),
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "Popovers", package: "Popovers"),
                .product(name: "SwiftJWT", package: "Swift-JWT")
            ],
            resources: [
                .process("Resources")
            ]
        )
    ]
)