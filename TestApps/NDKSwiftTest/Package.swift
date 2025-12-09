// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NDKSwiftTest",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "NDKSwiftTest",
            targets: ["NDKSwiftTest"]
        )
    ],
    dependencies: [
        .package(path: "../..") // NDKSwift package
    ],
    targets: [
        .executableTarget(
            name: "NDKSwiftTest",
            dependencies: [
                .product(name: "NDKSwift", package: "NDKSwift")
            ],
            path: ".",
            sources: [
                "NDKSwiftTestApp.swift",
                "ContentView.swift",
                "UserProfileView.swift"
            ]
        )
    ]
)
