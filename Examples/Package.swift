// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "NDKSwiftExamples",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15),
        .watchOS(.v8),
    ],
    dependencies: [
        .package(name: "NDKSwift", path: ".."), // NDKSwift package
    ],
    targets: [
        .executableTarget(
            name: "SimpleDemo",
            dependencies: [
                .product(name: "NDKSwift", package: "NDKSwift"),
            ],
            path: ".",
            exclude: ["StandaloneDemo.swift", "BasicUsage.swift", "SimpleDemo.swift", "NostrDemo.swift", "README.md", "FileCacheDemo.swift"],
            sources: ["SimpleDemoMain.swift"]
        ),
        .executableTarget(
            name: "NostrDemo",
            dependencies: [
                .product(name: "NDKSwift", package: "NDKSwift"),
            ],
            path: ".",
            exclude: ["StandaloneDemo.swift", "BasicUsage.swift", "SimpleDemo.swift", "NostrDemo.swift", "README.md", "FileCacheDemo.swift"],
            sources: ["NostrDemoMain.swift"]
        ),
        .executableTarget(
            name: "FileCacheDemo",
            dependencies: [
                .product(name: "NDKSwift", package: "NDKSwift"),
            ],
            path: ".",
            exclude: ["StandaloneDemo.swift", "BasicUsage.swift", "SimpleDemo.swift", "NostrDemo.swift", "README.md", "SimpleDemoMain.swift", "NostrDemoMain.swift", "CacheExample.swift"],
            sources: ["FileCacheDemo.swift"]
        ),
        .executableTarget(
            name: "CacheExample",
            dependencies: [
                .product(name: "NDKSwift", package: "NDKSwift"),
            ],
            path: ".",
            exclude: ["StandaloneDemo.swift", "BasicUsage.swift", "SimpleDemo.swift", "NostrDemo.swift", "README.md", "SimpleDemoMain.swift", "NostrDemoMain.swift", "FileCacheDemo.swift"],
            sources: ["CacheExample.swift"]
        ),
        .executableTarget(
            name: "iOSNostrAppDemo",
            dependencies: [
                .product(name: "NDKSwift", package: "NDKSwift"),
            ],
            path: ".",
            exclude: ["StandaloneDemo.swift", "BasicUsage.swift", "SimpleDemo.swift", "NostrDemo.swift", "README.md", "SimpleDemoMain.swift", "NostrDemoMain.swift", "FileCacheDemo.swift"],
            sources: ["iOSNostrAppDemo.swift"]
        ),
        .executableTarget(
            name: "BunkerDemo",
            dependencies: [
                .product(name: "NDKSwift", package: "NDKSwift"),
            ],
            path: ".",
            exclude: ["StandaloneDemo.swift", "BasicUsage.swift", "SimpleDemo.swift", "NostrDemo.swift", "README.md", "SimpleDemoMain.swift", "NostrDemoMain.swift", "FileCacheDemo.swift", "iOSNostrAppDemo.swift", "PaymentDemo.swift", "EncodeDemo.swift", "BlossomDemo.swift", "RuniOSApp.swift", "TestBunker.swift"],
            sources: ["BunkerDemo.swift"]
        ),
        .executableTarget(
            name: "TestBunker",
            dependencies: [
                .product(name: "NDKSwift", package: "NDKSwift"),
            ],
            path: ".",
            exclude: ["StandaloneDemo.swift", "BasicUsage.swift", "SimpleDemo.swift", "NostrDemo.swift", "README.md", "SimpleDemoMain.swift", "NostrDemoMain.swift", "FileCacheDemo.swift", "iOSNostrAppDemo.swift", "PaymentDemo.swift", "EncodeDemo.swift", "BlossomDemo.swift", "RuniOSApp.swift", "BunkerDemo.swift", "TestiOSBunker.swift", "iOSBunkerDemo.swift", "TestBunkerParsing.swift"],
            sources: ["TestBunker.swift"]
        ),
        .executableTarget(
            name: "TestiOSBunker",
            dependencies: [
                .product(name: "NDKSwift", package: "NDKSwift"),
            ],
            path: ".",
            exclude: ["StandaloneDemo.swift", "BasicUsage.swift", "SimpleDemo.swift", "NostrDemo.swift", "README.md", "SimpleDemoMain.swift", "NostrDemoMain.swift", "FileCacheDemo.swift", "iOSNostrAppDemo.swift", "PaymentDemo.swift", "EncodeDemo.swift", "BlossomDemo.swift", "RuniOSApp.swift", "BunkerDemo.swift", "TestBunker.swift", "iOSBunkerDemo.swift", "TestBunkerParsing.swift", "FetchEventCLI.swift"],
            sources: ["TestiOSBunker.swift"]
        ),
        .executableTarget(
            name: "FetchEventCLI",
            dependencies: [
                .product(name: "NDKSwift", package: "NDKSwift"),
            ],
            path: ".",
            exclude: ["StandaloneDemo.swift", "BasicUsage.swift", "SimpleDemo.swift", "NostrDemo.swift", "README.md", "SimpleDemoMain.swift", "NostrDemoMain.swift", "FileCacheDemo.swift", "iOSNostrAppDemo.swift", "PaymentDemo.swift", "EncodeDemo.swift", "BlossomDemo.swift", "RuniOSApp.swift", "BunkerDemo.swift", "TestBunker.swift", "iOSBunkerDemo.swift", "TestBunkerParsing.swift", "TestiOSBunker.swift"],
            sources: ["FetchEventCLI.swift"]
        ),
        .executableTarget(
            name: "SecureChatCLI",
            dependencies: [
                .product(name: "NDKSwift", package: "NDKSwift"),
            ],
            path: ".",
            exclude: ["StandaloneDemo.swift", "BasicUsage.swift", "SimpleDemo.swift", "NostrDemo.swift", "README.md", "SimpleDemoMain.swift", "NostrDemoMain.swift", "FileCacheDemo.swift", "iOSNostrAppDemo.swift", "PaymentDemo.swift", "EncodeDemo.swift", "BlossomDemo.swift", "RuniOSApp.swift", "BunkerDemo.swift", "TestBunker.swift", "iOSBunkerDemo.swift", "TestBunkerParsing.swift", "TestiOSBunker.swift", "FetchEventCLI.swift", "MircStyleChat.swift"],
            sources: ["SecureChatCLI.swift"]
        ),
        .executableTarget(
            name: "MircStyleChat",
            dependencies: [
                .product(name: "NDKSwift", package: "NDKSwift"),
            ],
            path: ".",
            exclude: ["StandaloneDemo.swift", "BasicUsage.swift", "SimpleDemo.swift", "NostrDemo.swift", "README.md", "SimpleDemoMain.swift", "NostrDemoMain.swift", "FileCacheDemo.swift", "iOSNostrAppDemo.swift", "PaymentDemo.swift", "EncodeDemo.swift", "BlossomDemo.swift", "RuniOSApp.swift", "BunkerDemo.swift", "TestBunker.swift", "iOSBunkerDemo.swift", "TestBunkerParsing.swift", "TestiOSBunker.swift", "FetchEventCLI.swift", "SecureChatCLI.swift"],
            sources: ["MircStyleChat.swift"]
        ),
    ]
)
