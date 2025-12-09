// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Olas",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "Olas", targets: ["Olas"])
    ],
    dependencies: [
        .package(path: "..")  // NDKSwift parent package
    ],
    targets: [
        .target(
            name: "Olas",
            dependencies: [
                .product(name: "NDKSwift", package: "master"),
                .product(name: "NDKSwiftUI", package: "master")
            ]
        ),
        .testTarget(
            name: "OlasTests",
            dependencies: ["Olas"]
        )
    ]
)
