# NDKSwift Module Refactoring Design

## Problem

NDKSwift is monolithic - apps pay for dependencies they don't use:
- GRDB (~3.5MB) for SQLite caching
- NostrDB C library for NostrDB caching
- CashuSwift for wallet functionality

Apps wanting only `MemoryCache` or custom `NDKCache` still pull all dependencies.

## Solution

Split into 5 focused modules:

| Module | Dependencies | Purpose |
|--------|--------------|---------|
| NDKSwiftCore | CryptoSwift | Foundation - events, relays, subscriptions, encryption, NWC wallet |
| NDKSwiftSQLite | NDKSwiftCore, GRDB | SQLite cache implementation |
| NDKSwiftNostrDB | NDKSwiftCore, NostrDB | NostrDB cache implementation |
| NDKSwiftCashu | NDKSwiftCore, CashuSwift | NIP-60 wallet, nutzaps, Cashu events |
| NDKSwiftUI | NDKSwiftCore | SwiftUI components |

## Key Design Decisions

### 1. Cache Protocol with Generic KV Store

The `NDKCache` protocol stays in Core with no CashuSwift dependency. Instead of Cashu-specific methods, it provides a generic key-value store:

```swift
public protocol NDKCache: Actor {
    // Existing event/profile/NIP-05 methods unchanged...

    // Generic KV store for module-specific data
    func setValue(_ value: Data, forKey key: String, namespace: String) async throws
    func getValue(forKey key: String, namespace: String) async -> Data?
    func deleteValue(forKey key: String, namespace: String) async throws
    func getValues(namespace: String, keyPrefix: String?) async -> [String: Data]
}
```

The Cashu module uses this internally via a helper:

```swift
// Internal to NDKSwiftCashu
struct CashuCacheHelper {
    let cache: NDKCache
    private let namespace = "cashu"

    func saveMintInfo(_ info: NDKMintInfo, url: String) async throws {
        let data = try JSONEncoder().encode(info)
        try await cache.setValue(data, forKey: "mint:\(url)", namespace: namespace)
    }

    func getMintInfo(url: String) async -> NDKMintInfo? {
        guard let data = await cache.getValue(forKey: "mint:\(url)", namespace: namespace) else { return nil }
        return try? JSONDecoder().decode(NDKMintInfo.self, from: data)
    }
    // ... keyset methods similar
}
```

### 2. Zaps Split

- Core zap infrastructure (LNURL, base types) stays in NDKSwiftCore
- NWC wallet stays in NDKSwiftCore (no Cashu dependency)
- Nutzap functionality moves to NDKSwiftCashu

### 3. No Backwards Compatibility

No umbrella target. Apps explicitly import what they need:

```swift
// Minimal app
import NDKSwiftCore

// App with SQLite cache
import NDKSwiftCore
import NDKSwiftSQLite

// App with wallet support
import NDKSwiftCore
import NDKSwiftSQLite
import NDKSwiftCashu
```

## Package Structure

```swift
let package = Package(
    name: "NDKSwift",
    platforms: [.iOS(.v17), .macOS(.v14), .tvOS(.v17), .watchOS(.v10)],
    products: [
        .library(name: "NDKSwiftCore", targets: ["NDKSwiftCore"]),
        .library(name: "NDKSwiftSQLite", targets: ["NDKSwiftSQLite"]),
        .library(name: "NDKSwiftNostrDB", targets: ["NDKSwiftNostrDB"]),
        .library(name: "NDKSwiftCashu", targets: ["NDKSwiftCashu"]),
        .library(name: "NDKSwiftUI", targets: ["NDKSwiftUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/krzyzanowskim/CryptoSwift.git", from: "1.8.0"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.3"),
        .package(url: "https://github.com/pablof7z/CashuSwift.git", branch: "main"),
    ],
    targets: [
        .target(name: "NostrDB", ...),
        .target(
            name: "NDKSwiftCore",
            dependencies: [.product(name: "CryptoSwift", package: "CryptoSwift")]
        ),
        .target(
            name: "NDKSwiftSQLite",
            dependencies: ["NDKSwiftCore", .product(name: "GRDB", package: "GRDB.swift")]
        ),
        .target(
            name: "NDKSwiftNostrDB",
            dependencies: ["NDKSwiftCore", "NostrDB"]
        ),
        .target(
            name: "NDKSwiftCashu",
            dependencies: ["NDKSwiftCore", .product(name: "CashuSwift", package: "CashuSwift")]
        ),
        .target(
            name: "NDKSwiftUI",
            dependencies: ["NDKSwiftCore"]
        ),
    ]
)
```

## Directory Structure

```
Sources/
├── NostrDB/                    # C library (unchanged)
├── NDKSwiftCore/
│   ├── Core/
│   ├── Models/                 # No Cashu models
│   ├── Encryption/
│   ├── DataSource/
│   ├── Outbox/
│   ├── Relay/
│   ├── Signers/
│   ├── Auth/
│   ├── Subscription/
│   ├── Negentropy/
│   ├── NIP05/
│   ├── NIP77/
│   ├── Blossom/
│   ├── LNURL/
│   ├── RPC/
│   ├── Zaps/                   # Core zap types, no nutzap
│   ├── Wallets/NWC/            # NWC wallet
│   ├── Cache/
│   │   ├── NDKCache.swift      # Protocol with KV store
│   │   ├── MemoryCache.swift
│   │   └── CacheType.swift
│   ├── Utils/
│   ├── Errors/
│   └── Extensions/             # No CashuSwift extensions
├── NDKSwiftSQLite/
│   ├── NDKSQLiteCache.swift
│   ├── SQLiteQueryBuilder.swift
│   └── Migrations/
├── NDKSwiftNostrDB/
│   ├── NDKNostrDBCache.swift
│   └── NostrDB/                # Swift wrappers
├── NDKSwiftCashu/
│   ├── CashuCacheHelper.swift
│   ├── Wallet/                 # NIP-60 wallet
│   ├── Models/                 # NDKNutzap, NDKCashuEvents
│   ├── Zaps/                   # Nutzap functionality
│   └── Extensions/             # CashuSwift+Extensions
└── NDKSwiftUI/                 # Unchanged
```

## Migration for Consumers

Before:
```swift
import NDKSwift
let ndk = try await NDK(cacheType: .sqlite)
```

After:
```swift
import NDKSwiftCore
import NDKSwiftSQLite
let cache = try await NDKSQLiteCache()
let ndk = NDK(cache: cache)
```

## Implementation Order

1. Create directory structure
2. Modify NDKCache protocol (remove Cashu methods, add KV store)
3. Update MemoryCache with KV store implementation
4. Move files to NDKSwiftCore
5. Move SQLite files to NDKSwiftSQLite, update with KV store
6. Move NostrDB files to NDKSwiftNostrDB
7. Move Cashu files to NDKSwiftCashu, create CashuCacheHelper
8. Update Package.swift
9. Fix imports and access modifiers across all modules
10. Update tests
