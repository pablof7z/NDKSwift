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
        .package(path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "NutsackiOS",
            dependencies: [
                .product(name: "NDKSwift", package: "NDKSwift-z94ws0")
            ],
            exclude: ["QR_CODE_IMPROVEMENTS.md", "Info.plist"]
        )
    ]
)