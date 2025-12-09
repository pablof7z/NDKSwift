// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Olas",
    platforms: [
        .iOS("18.0"),
        .macOS("15.0")
    ],
    products: [
        .library(name: "Olas", targets: ["Olas"])
    ],
    dependencies: [
        .package(path: ".."),  // NDKSwift parent package
        .package(url: "https://github.com/iankoex/UnifiedBlurHash", from: "1.0.0"),
        .package(url: "https://github.com/breez/breez-sdk-spark-swift.git", from: "0.5.2"),
        .package(url: "https://github.com/pengpengliu/BIP39.git", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "Olas",
            dependencies: [
                .product(name: "NDKSwift", package: "master"),
                .product(name: "NDKSwiftUI", package: "master"),
                .product(name: "UnifiedBlurHash", package: "UnifiedBlurHash"),
                .product(name: "BreezSdkSpark", package: "breez-sdk-spark-swift"),
                .product(name: "BIP39", package: "BIP39")
            ],
            exclude: ["OlasApp.swift"]
        ),
        .testTarget(
            name: "OlasTests",
            dependencies: ["Olas"]
        )
    ]
)
