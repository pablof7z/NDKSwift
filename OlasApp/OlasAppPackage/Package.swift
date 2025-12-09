// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OlasAppFeature",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(
            name: "OlasAppFeature",
            targets: ["OlasAppFeature"]
        ),
    ],
    dependencies: [
        .package(path: "../../Olas"),  // Reference the Olas library
        .package(path: "../..")        // NDKSwift parent package
    ],
    targets: [
        .target(
            name: "OlasAppFeature",
            dependencies: [
                .product(name: "Olas", package: "Olas"),
                .product(name: "NDKSwift", package: "master")
            ]
        ),
        .testTarget(
            name: "OlasAppFeatureTests",
            dependencies: [
                "OlasAppFeature"
            ]
        ),
    ]
)
