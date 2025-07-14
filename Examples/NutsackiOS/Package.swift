// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NutsackiOS",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "NutsackiOS",
            targets: ["NutsackiOS"]
        )
    ],
    dependencies: [
        .package(name: "NDKSwift", path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "NutsackiOS",
            dependencies: [
                .product(name: "NDKSwift", package: "NDKSwift")
            ],
            exclude: ["QR_CODE_IMPROVEMENTS.md", "Info.plist", "LaunchScreen.storyboard", "NutsackiOS.xcconfig"]
        )
    ]
)