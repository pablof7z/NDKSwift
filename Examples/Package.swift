// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "NDKSwiftExamples",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15),
        .watchOS(.v8)
    ],
    dependencies: [
        .package(path: "..") // NDKSwift package
    ],
    targets: [
        .executableTarget(
            name: "SimpleDemo",
            dependencies: ["NDKSwift"],
            path: ".",
            sources: ["SimpleDemo.swift"]
        ),
        .executableTarget(
            name: "NostrDemo",
            dependencies: ["NDKSwift"],
            path: ".",
            sources: ["NostrDemo.swift"]
        )
    ]
)