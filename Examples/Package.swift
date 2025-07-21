// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NDKSwiftExamples",
    platforms: [
        .iOS(.v15),
        .macOS(.v14)
    ],
    products: [
        // Getting Started
        .executable(name: "GettingStarted", targets: ["GettingStarted"]),
        
        // Feature demos
        .executable(name: "RelayCollectionDemo", targets: ["RelayCollectionDemo"]),
        .executable(name: "DebugKind0Fetcher", targets: ["DebugKind0Fetcher"]),
        .executable(name: "NIP77Demo", targets: ["NIP77Demo"]),
        .executable(name: "TestNegentropyProtocol", targets: ["TestNegentropyProtocol"]),
        .executable(name: "RealDeclarativeDemo", targets: ["RealDeclarativeDemo"]),
        .executable(name: "OptimisticPublishingDemo", targets: ["OptimisticPublishingDemo"]),
        .executable(name: "DebugSubscription", targets: ["DebugSubscription"]),
        .executable(name: "NIP60Wallet", targets: ["NIP60Wallet"]),
        .executable(name: "DebugOutbox", targets: ["DebugOutbox"]),
        .executable(name: "NIP92MediaDemo", targets: ["NIP92MediaDemo"]),
        .executable(name: "ProfileCachingDemo", targets: ["ProfileCachingDemo"]),
        .executable(name: "TestNIP46Publishing", targets: ["TestNIP46Publishing"])
    ],
    dependencies: [
        .package(path: "..")
    ],
    targets: [
        .executableTarget(
            name: "GettingStarted",
            dependencies: [
                .product(name: "NDKSwift", package: "NDKSwift")
            ],
            path: "GettingStarted",
            sources: ["main.swift", "Example01_ConnectToRelay.swift", "Example02_PublishEvent.swift", "Example03_Subscribe.swift", "Example03_1_SimpleObserver.swift", "Example03_2_GroupedSubscriptions.swift", "Example04_UserProfile.swift", "Example05_EncryptedMessages.swift", "Example06_OutboxModel.swift", "Example07_MultipleObservers.swift", "Example08_PublishWithNIP46.swift"],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        ),
        .executableTarget(
            name: "RelayCollectionDemo",
            dependencies: [
                .product(name: "NDKSwift", package: "NDKSwift")
            ],
            path: "Features/RelayCollectionDemo"
        ),
        .executableTarget(
            name: "DebugKind0Fetcher",
            dependencies: [
                .product(name: "NDKSwift", package: "NDKSwift")
            ],
            path: "Features/DebugKind0Fetcher"
        ),
        .executableTarget(
            name: "NIP77Demo",
            dependencies: [
                .product(name: "NDKSwift", package: "NDKSwift")
            ],
            path: "Features/NIP77Demo"
        ),
        .executableTarget(
            name: "TestNegentropyProtocol",
            dependencies: [
                .product(name: "NDKSwift", package: "NDKSwift")
            ],
            path: "Features/TestNegentropyProtocol"
        ),
        .executableTarget(
            name: "RealDeclarativeDemo",
            dependencies: [
                .product(name: "NDKSwift", package: "NDKSwift")
            ],
            path: "Features/RealDeclarativeDemo"
        ),
        .executableTarget(
            name: "OptimisticPublishingDemo",
            dependencies: [
                .product(name: "NDKSwift", package: "NDKSwift")
            ],
            path: "Features/OptimisticPublishingDemo"
        ),
        .executableTarget(
            name: "DebugSubscription",
            dependencies: [
                .product(name: "NDKSwift", package: "NDKSwift")
            ],
            path: ".",
            sources: ["DebugSubscription.swift"]
        ),
        .executableTarget(
            name: "NIP60Wallet",
            dependencies: [
                .product(name: "NDKSwift", package: "NDKSwift")
            ],
            path: ".",
            sources: ["NIP60Wallet.swift"]
        ),
        .executableTarget(
            name: "DebugOutbox",
            dependencies: [
                .product(name: "NDKSwift", package: "NDKSwift")
            ],
            path: ".",
            sources: ["DebugOutbox.swift"]
        ),
        .executableTarget(
            name: "NIP92MediaDemo",
            dependencies: [
                .product(name: "NDKSwift", package: "NDKSwift")
            ],
            path: "Features/NIP92MediaDemo"
        ),
        .executableTarget(
            name: "ProfileCachingDemo",
            dependencies: [
                .product(name: "NDKSwift", package: "NDKSwift")
            ],
            path: ".",
            sources: ["ProfileCachingDemo.swift"]
        ),
        .executableTarget(
            name: "TestNIP46Publishing",
            dependencies: [
                .product(name: "NDKSwift", package: "NDKSwift")
            ],
            path: ".",
            sources: ["TestNIP46Publishing.swift"]
        )
    ]
)