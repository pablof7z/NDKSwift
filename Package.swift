// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "NDKSwift",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .tvOS(.v17),
        .watchOS(.v10),
    ],
    products: [
        .library(name: "NDKSwiftCore", targets: ["NDKSwiftCore"]),
        .library(name: "NDKSwiftSQLite", targets: ["NDKSwiftSQLite"]),
        .library(name: "NDKSwiftNostrDB", targets: ["NDKSwiftNostrDB"]),
        .library(name: "NDKSwiftCashu", targets: ["NDKSwiftCashu"]),
        .library(name: "NDKSwiftUI", targets: ["NDKSwiftUI"]),
        .library(name: "NDKSwiftTesting", targets: ["NDKSwiftTesting"]),
    ],
    dependencies: [
        .package(url: "https://github.com/krzyzanowskim/CryptoSwift.git", from: "1.8.0"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.3"),
        .package(url: "https://github.com/pablof7z/CashuSwift.git", branch: "main"),
        .package(url: "https://github.com/21-DOT-DEV/swift-secp256k1", from: "0.19.0"),
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0"),
        .package(url: "https://github.com/onevcat/Kingfisher.git", from: "8.0.0"),
    ],
    targets: [
        .target(
            name: "NostrDB",
            dependencies: [],
            path: "Sources/NostrDB",
            exclude: [
                "ccan/ccan/crypto/sha256/benchmarks",
                "ccan/ccan/tal/benchmark",
                "ccan/ccan/htable/tools",
            ],
            sources: [
                // C sources - root level
                "mdb.c",
                "midl.c",
                "bolt11.c",
                "hash_u5.c",
                "utf8.c",
                "bech32.c",
                "bech32_util.c",
                "amount.c",
                "error.c",
                "node_id.c",
                // C sources - src/
                "src/nostrdb.c",
                "src/block.c",
                "src/content_parser.c",
                "src/nostr_bech32.c",
                "src/invoice.c",
                // FlatCC sources
                "flatcc/builder.c",
                "flatcc/emitter.c",
                "flatcc/json_parser.c",
                "flatcc/json_printer.c",
                "flatcc/refmap.c",
                "flatcc/verifier.c",
                // CCAN sources
                "ccan/ccan/crypto/sha256/sha256.c",
                "ccan/ccan/htable/htable.c",
                "ccan/ccan/list/list.c",
                "ccan/ccan/mem/mem.c",
                "ccan/ccan/str/str.c",
                "ccan/ccan/str/debug.c",
                "ccan/ccan/tal/tal.c",
                "ccan/ccan/tal/str/str.c",
                "ccan/ccan/take/take.c",
            ],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("."),
                .headerSearchPath("src"),
                .headerSearchPath("flatcc"),
                .headerSearchPath("ccan"),
                .headerSearchPath("ccan/ccan"),
                .define("MDB_USE_POSIX_SEM", to: "1"),
                .define("HAVE_UNISTD_H", to: "1"),
            ]
        ),
        .target(
            name: "NDKSwiftCore",
            dependencies: [
                .product(name: "CryptoSwift", package: "CryptoSwift"),
                .product(name: "secp256k1", package: "swift-secp256k1"),
            ]
        ),
        .target(
            name: "NDKSwiftSQLite",
            dependencies: [
                "NDKSwiftCore",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .target(
            name: "NDKSwiftNostrDB",
            dependencies: [
                "NDKSwiftCore",
                "NostrDB",
            ]
        ),
        .target(
            name: "NDKSwiftCashu",
            dependencies: [
                "NDKSwiftCore",
                .product(name: "CashuSwift", package: "CashuSwift"),
            ]
        ),
        .target(
            name: "NDKSwiftUI",
            dependencies: [
                "NDKSwiftCore",
                "NDKSwiftCashu",
                "NDKSwiftNostrDB",
                .product(name: "Kingfisher", package: "Kingfisher"),
            ]
        ),
        .target(
            name: "NDKSwiftTesting",
            dependencies: [
                "NDKSwiftCore",
            ]
        ),
        .testTarget(
            name: "NDKSwiftTests",
            dependencies: [
                "NDKSwiftCore",
                "NDKSwiftSQLite",
                "NDKSwiftNostrDB",
                "NDKSwiftCashu",
                "NDKSwiftUI",
            ],
            exclude: ["DisabledTests"],
            resources: [
                .process("Integration/README_OutboxTests.md"),
                .process("TestHelpers/README.md")
            ]
        ),
    ]
)
