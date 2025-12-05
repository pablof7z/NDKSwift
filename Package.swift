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
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "NDKSwift",
            targets: ["NDKSwift"]
        ),
        .library(
            name: "NDKSwiftUI",
            targets: ["NDKSwiftUI"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/anquii/CryptoSwiftWrapper.git", from: "1.4.3"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.3"),
        .package(url: "https://github.com/pablof7z/CashuSwift.git", branch: "main"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "NostrDB",
            dependencies: [],
            path: "Sources/NostrDB",
            exclude: [
                "Swift",
                "FlatBuffers",
                "ccan/ccan/crypto/sha256/benchmarks",
                "ccan/ccan/tal/benchmark",
                "ccan/ccan/htable/tools",
            ],
            sources: [
                // C sources - root level
                "mdb.c",
                "midl.c",
                // "hex.c", // Excluded - using hex.h inline implementations
                "bolt11.c",
                "list.c",
                "mem.c",
                "hash_u5.c",
                "talstr.c",
                "utf8.c",
                "bech32.c",
                "bech32_util.c",
                "tal.c",
                "take.c",
                "amount.c",
                "error.c",
                "node_id.c",
                "ndb.c",
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
            name: "NDKSwift",
            dependencies: [
                "NostrDB",
                .product(name: "CryptoSwiftWrapper", package: "CryptoSwiftWrapper"),
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "CashuSwift", package: "CashuSwift"),
            ],
            resources: [
                .process("Wallets/Common/README.md")
            ]
        ),
        .target(
            name: "NDKSwiftUI",
            dependencies: [
                "NDKSwift"
            ]
        ),
        .testTarget(
            name: "NDKSwiftTests",
            dependencies: [
                "NDKSwift",
                .product(name: "CashuSwift", package: "CashuSwift"),
            ],
            exclude: ["DisabledTests"],
            resources: [
                .process("Integration/README_OutboxTests.md"),
                .process("TestHelpers/README.md")
            ]
        ),
    ]
)
