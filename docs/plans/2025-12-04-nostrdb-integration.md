# NostrDB Integration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Integrate nostrdb (from Damus) as a high-performance cache backend for NDKSwift, completely hidden behind the existing NDKCache protocol.

**Architecture:** Copy Damus's battle-tested nostrdb Swift bindings into a new internal `NostrDB` target. Create `NDKNostrDBCache` implementing the `NDKCache` protocol. All nostrdb types remain internal - users interact only through existing NDK APIs.

**Tech Stack:** nostrdb (C library), LMDB, FlatBuffers, Swift C interop

---

## Phase 1: Set Up NostrDB Target

### Task 1: Copy nostrdb Sources from Damus

**Files:**
- Create: `Sources/NostrDB/` (entire directory)
- Create: `Sources/NostrDB/include/` (for public C headers)

**Step 1: Create the NostrDB directory structure**

```bash
mkdir -p Sources/NostrDB/include
mkdir -p Sources/NostrDB/flatcc
mkdir -p Sources/NostrDB/src
mkdir -p Sources/NostrDB/ccan
```

**Step 2: Copy C source files from Damus**

Copy these files from `/Users/pablofernandez/src/damus/nostrdb/` to `Sources/NostrDB/`:

C Implementation Files:
- `mdb.c` - LMDB implementation
- `midl.c` - LMDB internal
- `hex.c` - Hex encoding
- `bolt11.c` - Lightning invoices
- `list.c` - Linked list
- `mem.c` - Memory management
- `hash_u5.c` - Hash utilities
- `talstr.c` - String utilities
- `utf8.c` - UTF-8 handling
- `bech32.c` - Bech32 encoding
- `bech32_util.c` - Bech32 utilities
- `tal.c` - Memory allocator
- `take.c` - Ownership transfer
- `amount.c` - Amount parsing
- `error.c` - Error handling
- `node_id.c` - Node ID handling
- `ndb.c` - NostrDB stub

From `src/` subdirectory:
- `src/nostrdb.c` - Main NostrDB implementation
- `src/block.c` - Block parsing
- `src/content_parser.c` - Content parsing
- `src/nostr_bech32.c` - Nostr-specific bech32
- `src/invoice.c` - Invoice handling

Header Files (copy to `include/`):
- `lmdb.h`
- `nostrdb.h` (from `src/`)
- All other `.h` files

FlatCC (copy entire directory):
- `flatcc/` directory with all `.c` and `.h` files

CCAN utilities:
- `ccan/` directory

**Step 3: Verify file copy**

Run: `ls -la Sources/NostrDB/*.c | wc -l`
Expected: ~15-20 C source files

**Step 4: Commit**

```bash
git add Sources/NostrDB/
git commit -m "feat: add nostrdb C sources from Damus"
```

---

### Task 2: Copy Swift Bindings from Damus

**Files:**
- Create: `Sources/NostrDB/Swift/Ndb.swift`
- Create: `Sources/NostrDB/Swift/NdbNote.swift`
- Create: `Sources/NostrDB/Swift/NdbFilter.swift`
- Create: `Sources/NostrDB/Swift/NdbTxn.swift`
- Create: `Sources/NostrDB/Swift/NdbBlock.swift`
- Create: `Sources/NostrDB/Swift/NdbTagElem.swift`
- Create: `Sources/NostrDB/Swift/NdbTagIterator.swift`
- Create: `Sources/NostrDB/Swift/NdbTagsIterator.swift`
- Create: `Sources/NostrDB/Swift/UnownedNdbNote.swift`
- Create: `Sources/NostrDB/Swift/AsciiCharacter.swift`
- Create: `Sources/NostrDB/Swift/NonCopyableLinkedList.swift`
- Create: `Sources/NostrDB/FlatBuffers/NdbProfile.swift`
- Create: `Sources/NostrDB/FlatBuffers/NdbMeta.swift`

**Step 1: Create Swift directories**

```bash
mkdir -p Sources/NostrDB/Swift
mkdir -p Sources/NostrDB/FlatBuffers
```

**Step 2: Copy Swift files from Damus**

From `/Users/pablofernandez/src/damus/nostrdb/`:
- `Ndb.swift` → `Sources/NostrDB/Swift/`
- `NdbNote.swift` → `Sources/NostrDB/Swift/`
- `NdbFilter.swift` → `Sources/NostrDB/Swift/`
- `NdbTxn.swift` → `Sources/NostrDB/Swift/`
- `NdbBlock.swift` → `Sources/NostrDB/Swift/`
- `NdbTagElem.swift` → `Sources/NostrDB/Swift/`
- `NdbTagIterator.swift` → `Sources/NostrDB/Swift/`
- `NdbTagsIterator.swift` → `Sources/NostrDB/Swift/`
- `UnownedNdbNote.swift` → `Sources/NostrDB/Swift/`
- `AsciiCharacter.swift` → `Sources/NostrDB/Swift/`
- `NonCopyableLinkedList.swift` → `Sources/NostrDB/Swift/`

From `/Users/pablofernandez/src/damus/nostrdb/src/bindings/swift/`:
- `NdbProfile.swift` → `Sources/NostrDB/FlatBuffers/`
- `NdbMeta.swift` → `Sources/NostrDB/FlatBuffers/`

**Step 3: Do NOT copy Damus-specific files**

Skip these (they have Damus dependencies):
- `Ndb+.swift` (references `NostrFilter`, `RelayURL`)
- `NdbNote+.swift` (references Damus types)

**Step 4: Verify file copy**

Run: `ls Sources/NostrDB/Swift/*.swift | wc -l`
Expected: 11 files

**Step 5: Commit**

```bash
git add Sources/NostrDB/Swift/ Sources/NostrDB/FlatBuffers/
git commit -m "feat: add nostrdb Swift bindings from Damus"
```

---

### Task 3: Update Package.swift with NostrDB Target

**Files:**
- Modify: `Package.swift`

**Step 1: Read current Package.swift**

Review the current structure to understand the pattern.

**Step 2: Add NostrDB target and FlatBuffers dependency**

Add to `dependencies` array:

```swift
.package(url: "https://github.com/nicklockwood/FlatBuffers.git", from: "0.4.0"),
.package(url: "https://github.com/jb55/secp256k1.swift.git", branch: "main"),
```

Add new target before NDKSwift target:

```swift
.target(
    name: "NostrDB",
    dependencies: [
        .product(name: "FlatBuffers", package: "FlatBuffers"),
        .product(name: "secp256k1", package: "secp256k1.swift"),
    ],
    path: "Sources/NostrDB",
    exclude: [
        "Test",
        "Makefile",
        "copy-ndb",
        "test.c",
        "bench-ingest-many.c",
    ],
    sources: [
        // C sources
        "mdb.c",
        "midl.c",
        "hex.c",
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
        "src/nostrdb.c",
        "src/block.c",
        "src/content_parser.c",
        "src/nostr_bech32.c",
        "src/invoice.c",
        // FlatCC
        "flatcc/builder.c",
        "flatcc/emitter.c",
        "flatcc/json_parser.c",
        "flatcc/json_printer.c",
        "flatcc/refmap.c",
        "flatcc/verifier.c",
        // Swift sources
        "Swift/Ndb.swift",
        "Swift/NdbNote.swift",
        "Swift/NdbFilter.swift",
        "Swift/NdbTxn.swift",
        "Swift/NdbBlock.swift",
        "Swift/NdbTagElem.swift",
        "Swift/NdbTagIterator.swift",
        "Swift/NdbTagsIterator.swift",
        "Swift/UnownedNdbNote.swift",
        "Swift/AsciiCharacter.swift",
        "Swift/NonCopyableLinkedList.swift",
        "FlatBuffers/NdbProfile.swift",
        "FlatBuffers/NdbMeta.swift",
    ],
    publicHeadersPath: "include",
    cSettings: [
        .headerSearchPath("."),
        .headerSearchPath("src"),
        .headerSearchPath("flatcc"),
        .headerSearchPath("ccan"),
        .define("MDB_USE_POSIX_SEM", to: "1"),
        .define("HAVE_UNISTD_H", to: "1"),
    ]
),
```

Update NDKSwift target dependencies:

```swift
.target(
    name: "NDKSwift",
    dependencies: [
        "NostrDB",  // Add this
        .product(name: "CryptoSwiftWrapper", package: "CryptoSwiftWrapper"),
        // ... existing deps
    ],
    // ... rest unchanged
),
```

**Step 3: Build to verify**

Run: `swift build 2>&1 | head -50`
Expected: Build starts (may have errors to fix in next tasks)

**Step 4: Commit**

```bash
git add Package.swift
git commit -m "feat: add NostrDB target to Package.swift"
```

---

### Task 4: Fix Damus-Specific References in Swift Files

**Files:**
- Modify: `Sources/NostrDB/Swift/Ndb.swift`
- Modify: `Sources/NostrDB/Swift/NdbNote.swift`
- Modify: `Sources/NostrDB/Swift/NdbFilter.swift`

**Step 1: Remove Damus-specific imports and types**

In `Ndb.swift`, remove or stub:
- `APPLICATION_GROUP_IDENTIFIER` - make configurable
- `Log.error/debug/info` - replace with simple print or remove
- `NostrFilter` references - remove the extension methods (we'll add our own)
- Any Damus-specific types

Replace this at top of `Ndb.swift`:

```swift
import Foundation
import OSLog

// MARK: - Logging (stub for Damus's Log)
internal enum Log {
    static func error(_ message: String, for category: LogCategory, _ args: CVarArg...) {
        #if DEBUG
        print("[NostrDB ERROR] \(String(format: message, arguments: args))")
        #endif
    }
    static func debug(_ message: String, for category: LogCategory, _ args: CVarArg...) {
        #if DEBUG
        print("[NostrDB DEBUG] \(String(format: message, arguments: args))")
        #endif
    }
    static func info(_ message: String, for category: LogCategory, _ args: CVarArg...) {
        #if DEBUG
        print("[NostrDB INFO] \(String(format: message, arguments: args))")
        #endif
    }

    enum LogCategory {
        case storage
        case ndb
    }
}
```

**Step 2: Make APPLICATION_GROUP_IDENTIFIER configurable**

Replace hardcoded group identifier with configurable path:

```swift
// Replace:
// fileprivate let APPLICATION_GROUP_IDENTIFIER = "group.com.damus"

// With:
/// Configuration for NostrDB paths
public struct NdbConfig {
    /// Custom database path. If nil, uses app's document directory.
    public let dbPath: String?

    /// Application group identifier for shared container access.
    /// Set this if you need to share the database with app extensions.
    public let appGroupIdentifier: String?

    public init(dbPath: String? = nil, appGroupIdentifier: String? = nil) {
        self.dbPath = dbPath
        self.appGroupIdentifier = appGroupIdentifier
    }
}
```

**Step 3: Remove NostrFilter extension (we'll add our own)**

In `Ndb.swift`, the extension using `NostrFilter` should be removed - we'll create NDK-specific filter conversion.

**Step 4: Fix NdbNote.swift references**

Remove Damus-specific extensions:
- `NostrKind` references - stub or remove
- `ThreadReply` - remove
- `Keypair`/`Privkey` - stub minimal versions or use protocol

**Step 5: Build and fix remaining errors**

Run: `swift build 2>&1 | grep error | head -20`

Fix each error by either:
- Removing the Damus-specific code
- Creating minimal stubs
- Making internal what doesn't need to be public

**Step 6: Commit**

```bash
git add Sources/NostrDB/
git commit -m "fix: remove Damus-specific dependencies from NostrDB"
```

---

### Task 5: Create Minimal Type Stubs for NostrDB

**Files:**
- Create: `Sources/NostrDB/Swift/Types.swift`

**Step 1: Create minimal types needed by nostrdb Swift**

```swift
// Sources/NostrDB/Swift/Types.swift

import Foundation

// MARK: - Basic Types

/// Note key is an internal database identifier
public typealias NoteKey = UInt64

/// Profile key is an internal database identifier
public typealias ProfileKey = UInt64

// MARK: - Identifier Types

/// 32-byte note ID
public struct NoteId: Equatable, Hashable {
    public let id: Data

    public init(_ data: Data) {
        precondition(data.count == 32, "NoteId must be 32 bytes")
        self.id = data
    }

    public init?(_ hex: String) {
        guard let data = Data(hexString: hex), data.count == 32 else {
            return nil
        }
        self.id = data
    }

    public func hex() -> String {
        return id.hexEncodedString()
    }

    public func withUnsafePointer<T>(_ body: (UnsafePointer<UInt8>) throws -> T) rethrows -> T {
        return try id.withUnsafeBytes { buffer in
            try body(buffer.baseAddress!.assumingMemoryBound(to: UInt8.self))
        }
    }
}

/// 32-byte public key
public struct Pubkey: Equatable, Hashable, Codable {
    public let id: Data

    public init(_ data: Data) {
        precondition(data.count == 32, "Pubkey must be 32 bytes")
        self.id = data
    }

    public init?(_ hex: String) {
        guard let data = Data(hexString: hex), data.count == 32 else {
            return nil
        }
        self.id = data
    }

    public func hex() -> String {
        return id.hexEncodedString()
    }

    public var bytes: [UInt8] {
        return Array(id)
    }

    public func withUnsafePointer<T>(_ body: (UnsafePointer<UInt8>) throws -> T) rethrows -> T {
        return try id.withUnsafeBytes { buffer in
            try body(buffer.baseAddress!.assumingMemoryBound(to: UInt8.self))
        }
    }
}

/// 64-byte signature
public struct Signature: Equatable, Hashable {
    public let data: Data

    public init(_ data: Data) {
        precondition(data.count == 64, "Signature must be 64 bytes")
        self.data = data
    }

    public init?(_ hex: String) {
        guard let data = Data(hexString: hex), data.count == 64 else {
            return nil
        }
        self.data = data
    }

    public func hex() -> String {
        return data.hexEncodedString()
    }
}

// MARK: - Profile Record

public struct ProfileRecord {
    public let data: NdbProfileRecord
    public let key: ProfileKey

    public init(data: NdbProfileRecord, key: ProfileKey) {
        self.data = data
        self.key = key
    }
}

// MARK: - Data Extensions

extension Data {
    init?(hexString: String) {
        let len = hexString.count / 2
        var data = Data(capacity: len)
        var index = hexString.startIndex

        for _ in 0..<len {
            let nextIndex = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<nextIndex], radix: 16) else {
                return nil
            }
            data.append(byte)
            index = nextIndex
        }

        self = data
    }

    func hexEncodedString() -> String {
        return map { String(format: "%02x", $0) }.joined()
    }

    var byteArray: [UInt8] {
        return Array(self)
    }
}

// MARK: - C Interop Types

/// Wrapper for ndb_t pointer
public struct ndb_t {
    public var ndb: OpaquePointer?

    public init(ndb: OpaquePointer?) {
        self.ndb = ndb
    }
}

/// Wrapper for note pointer
public struct ndb_note_ptr {
    public var ptr: OpaquePointer?

    public init(ptr: OpaquePointer? = nil) {
        self.ptr = ptr
    }
}
```

**Step 2: Build to check**

Run: `swift build 2>&1 | grep error | head -20`

**Step 3: Commit**

```bash
git add Sources/NostrDB/Swift/Types.swift
git commit -m "feat: add minimal type stubs for NostrDB"
```

---

### Task 6: Build and Fix Remaining Compilation Errors

**Files:**
- Modify: Various files in `Sources/NostrDB/Swift/`

**Step 1: Build and collect errors**

Run: `swift build 2>&1 | tee build_errors.txt`

**Step 2: Fix each error iteratively**

Common fixes needed:
- Missing type references → Add to Types.swift
- Damus-specific code → Remove or stub
- secp256k1 imports → Use the swift-secp256k1 package
- FlatBuffers imports → Ensure correct import

**Step 3: Verify clean build**

Run: `swift build`
Expected: Build succeeds

**Step 4: Commit**

```bash
git add Sources/NostrDB/
git commit -m "fix: resolve NostrDB compilation errors"
```

---

## Phase 2: Create NDK Integration Layer

### Task 7: Create NDKNostrDBCache Implementation

**Files:**
- Create: `Sources/NDKSwift/Cache/NDKNostrDBCache.swift`

**Step 1: Write the failing test**

Create: `Tests/NDKSwiftTests/Unit/Cache/NDKNostrDBCacheTests.swift`

```swift
import XCTest
@testable import NDKSwift
@testable import NostrDB

final class NDKNostrDBCacheTests: XCTestCase {
    var cache: NDKNostrDBCache!
    var tempDir: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        cache = try await NDKNostrDBCache(path: tempDir.path)
    }

    override func tearDown() async throws {
        cache = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testSaveAndRetrieveEvent() async throws {
        // Create a test event
        let event = NDKEvent(
            id: "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
            pubkey: "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789",
            createdAt: 1700000000,
            kind: 1,
            tags: [["p", "fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210"]],
            content: "Hello, Nostr!",
            sig: String(repeating: "ab", count: 64)
        )

        // Save
        try await cache.saveEvent(event)

        // Retrieve
        let retrieved = await cache.getEvent(id: event.id)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.id, event.id)
        XCTAssertEqual(retrieved?.content, event.content)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter NDKNostrDBCacheTests 2>&1 | head -20`
Expected: FAIL - NDKNostrDBCache not found

**Step 3: Write the implementation**

```swift
// Sources/NDKSwift/Cache/NDKNostrDBCache.swift

import Foundation
import NostrDB

/// NostrDB-backed cache implementation
///
/// This provides a high-performance alternative to SQLite using LMDB
/// with zero-copy event access. All nostrdb types are internal -
/// users interact only through the NDKCache protocol.
public actor NDKNostrDBCache: NDKCache {

    // MARK: - Private Properties

    private let ndb: Ndb
    private let debugMode: Bool

    // MARK: - Initialization

    /// Initialize NostrDB cache with optional custom path
    /// - Parameters:
    ///   - path: Custom database path (uses app documents if nil)
    ///   - debugMode: Enable debug logging
    public init(path: String? = nil, debugMode: Bool = false) async throws {
        self.debugMode = debugMode

        guard let ndb = Ndb(path: path) else {
            throw NDKNostrDBCacheError.failedToOpen
        }
        self.ndb = ndb
    }

    // MARK: - Event Operations

    public func saveEvent(_ event: NDKEvent) async throws {
        // Convert NDKEvent to JSON and process into nostrdb
        let json = try event.toRelayJSON()
        let success = ndb.process_event(json)

        if !success && debugMode {
            print("[NDKNostrDBCache] Failed to process event: \(event.id)")
        }
    }

    public func getEvent(id: String) async -> NDKEvent? {
        guard let noteId = NoteId(id) else { return nil }
        guard let txn = ndb.lookup_note(noteId) else { return nil }

        let ndbNote = txn.unsafeUnownedValue
        guard let note = ndbNote else { return nil }

        return convertToNDKEvent(note)
    }

    public func queryEvents(_ filter: NDKFilter) async throws -> [NDKEvent] {
        // Convert NDKFilter to NdbFilter
        let ndbFilter = try convertToNdbFilter(filter)

        guard let txn = NdbTxn(ndb: ndb) else {
            throw NDKNostrDBCacheError.transactionFailed
        }

        let noteKeys = try ndb.query(with: txn, filters: [ndbFilter], maxResults: filter.limit ?? 500)

        var events: [NDKEvent] = []
        for key in noteKeys {
            if let note = ndb.lookup_note_by_key_with_txn(key, txn: txn),
               let event = convertToNDKEvent(note) {
                events.append(event)
            }
        }

        return events
    }

    public func deleteEvent(id: String) async throws {
        // NostrDB doesn't support direct deletion - events are immutable
        // Deletion is handled via NIP-09 deletion events
        if debugMode {
            print("[NDKNostrDBCache] Direct deletion not supported, use NIP-09")
        }
    }

    // MARK: - Observation (Reactive)

    public func observeEvents(
        matching filter: NDKFilter,
        includeExisting: Bool
    ) async -> AsyncThrowingStream<[NDKEvent], Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let ndbFilter = try convertToNdbFilter(filter)
                    let stream = try ndb.subscribe(filters: [ndbFilter])

                    var accumulatedEvents: [NDKEvent] = []

                    for await item in stream {
                        switch item {
                        case .eose:
                            if includeExisting && !accumulatedEvents.isEmpty {
                                continuation.yield(accumulatedEvents)
                                accumulatedEvents = []
                            }
                        case .event(let noteKey):
                            if let txn = NdbTxn(ndb: ndb),
                               let note = ndb.lookup_note_by_key_with_txn(noteKey, txn: txn),
                               let event = convertToNDKEvent(note) {
                                continuation.yield([event])
                            }
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func observeProfile(
        pubkey: String,
        includeExisting: Bool
    ) async -> AsyncThrowingStream<NDKUserMetadata?, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                // Subscribe to kind 0 events from this author
                let filter = NDKFilter(authors: [pubkey], kinds: [0])

                for await events in await observeEvents(matching: filter, includeExisting: includeExisting) {
                    for event in events {
                        if let metadata = try? JSONDecoder().decode(NDKUserMetadata.self, from: event.content.data(using: .utf8) ?? Data()) {
                            continuation.yield(metadata)
                        }
                    }
                }

                continuation.finish()
            }
        }
    }

    // MARK: - Cache Management

    public func clear() async throws {
        // NostrDB doesn't support clearing - would need to close and delete files
        ndb.close()
        throw NDKNostrDBCacheError.clearNotSupported
    }

    // MARK: - Conversion Helpers

    private func convertToNDKEvent(_ note: NdbNote) -> NDKEvent? {
        // Extract tags
        var tags: [[String]] = []
        for tag in note.tags {
            var tagArray: [String] = []
            for elem in tag {
                if let str = elem.string() {
                    tagArray.append(str)
                }
            }
            if !tagArray.isEmpty {
                tags.append(tagArray)
            }
        }

        return NDKEvent(
            id: note.id.hex(),
            pubkey: note.pubkey.hex(),
            createdAt: Timestamp(note.created_at),
            kind: Kind(note.kind),
            tags: tags,
            content: note.content,
            sig: note.sig.hex()
        )
    }

    private func convertToNdbFilter(_ filter: NDKFilter) throws -> NdbFilter {
        // Build NdbFilter from NDKFilter
        // This mirrors Damus's NdbFilter.swift conversion logic

        var ndbFilter = ndb_filter()
        guard ndb_filter_init(&ndbFilter) == 1 else {
            throw NDKNostrDBCacheError.filterConversionFailed
        }

        // Add IDs
        if let ids = filter.ids {
            guard ndb_filter_start_field(&ndbFilter, NDB_FILTER_IDS) == 1 else {
                throw NDKNostrDBCacheError.filterConversionFailed
            }
            for id in ids {
                guard let noteId = NoteId(id) else { continue }
                try noteId.withUnsafePointer { ptr in
                    if ndb_filter_add_id_element(&ndbFilter, ptr) != 1 {
                        throw NDKNostrDBCacheError.filterConversionFailed
                    }
                }
            }
            ndb_filter_end_field(&ndbFilter)
        }

        // Add authors
        if let authors = filter.authors {
            guard ndb_filter_start_field(&ndbFilter, NDB_FILTER_AUTHORS) == 1 else {
                throw NDKNostrDBCacheError.filterConversionFailed
            }
            for author in authors {
                guard let pubkey = Pubkey(author) else { continue }
                try pubkey.withUnsafePointer { ptr in
                    if ndb_filter_add_id_element(&ndbFilter, ptr) != 1 {
                        throw NDKNostrDBCacheError.filterConversionFailed
                    }
                }
            }
            ndb_filter_end_field(&ndbFilter)
        }

        // Add kinds
        if let kinds = filter.kinds {
            guard ndb_filter_start_field(&ndbFilter, NDB_FILTER_KINDS) == 1 else {
                throw NDKNostrDBCacheError.filterConversionFailed
            }
            for kind in kinds {
                if ndb_filter_add_int_element(&ndbFilter, UInt64(kind)) != 1 {
                    throw NDKNostrDBCacheError.filterConversionFailed
                }
            }
            ndb_filter_end_field(&ndbFilter)
        }

        // Add since
        if let since = filter.since {
            guard ndb_filter_start_field(&ndbFilter, NDB_FILTER_SINCE) == 1 else {
                throw NDKNostrDBCacheError.filterConversionFailed
            }
            if ndb_filter_add_int_element(&ndbFilter, UInt64(since)) != 1 {
                throw NDKNostrDBCacheError.filterConversionFailed
            }
            ndb_filter_end_field(&ndbFilter)
        }

        // Add until
        if let until = filter.until {
            guard ndb_filter_start_field(&ndbFilter, NDB_FILTER_UNTIL) == 1 else {
                throw NDKNostrDBCacheError.filterConversionFailed
            }
            if ndb_filter_add_int_element(&ndbFilter, UInt64(until)) != 1 {
                throw NDKNostrDBCacheError.filterConversionFailed
            }
            ndb_filter_end_field(&ndbFilter)
        }

        // Add limit
        if let limit = filter.limit {
            guard ndb_filter_start_field(&ndbFilter, NDB_FILTER_LIMIT) == 1 else {
                throw NDKNostrDBCacheError.filterConversionFailed
            }
            if ndb_filter_add_int_element(&ndbFilter, UInt64(limit)) != 1 {
                throw NDKNostrDBCacheError.filterConversionFailed
            }
            ndb_filter_end_field(&ndbFilter)
        }

        // Finalize
        guard ndb_filter_end(&ndbFilter) == 1 else {
            throw NDKNostrDBCacheError.filterConversionFailed
        }

        return NdbFilter(ndbFilter: ndbFilter)
    }
}

// MARK: - Errors

public enum NDKNostrDBCacheError: Error, LocalizedError {
    case failedToOpen
    case transactionFailed
    case filterConversionFailed
    case clearNotSupported

    public var errorDescription: String? {
        switch self {
        case .failedToOpen:
            return "Failed to open NostrDB database"
        case .transactionFailed:
            return "Failed to create database transaction"
        case .filterConversionFailed:
            return "Failed to convert filter to NostrDB format"
        case .clearNotSupported:
            return "NostrDB does not support clearing - delete database files manually"
        }
    }
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter NDKNostrDBCacheTests`
Expected: PASS

**Step 5: Commit**

```bash
git add Sources/NDKSwift/Cache/NDKNostrDBCache.swift
git add Tests/NDKSwiftTests/Unit/Cache/NDKNostrDBCacheTests.swift
git commit -m "feat: add NDKNostrDBCache implementing NDKCache protocol"
```

---

### Task 8: Add Missing NDKCache Protocol Methods to NDKNostrDBCache

**Files:**
- Modify: `Sources/NDKSwift/Cache/NDKNostrDBCache.swift`

**Step 1: Review NDKCache protocol for missing methods**

The NDKCache protocol has many methods. Add stubs for methods that nostrdb doesn't naturally support.

**Step 2: Add stub implementations for unsupported features**

Add to `NDKNostrDBCache`:

```swift
// MARK: - Optimistic Publishing (use defaults)
// NostrDB doesn't track publishing state - use protocol defaults

// MARK: - Decrypted Content Cache
// NostrDB doesn't store decrypted content separately - use protocol defaults

// MARK: - Mint Cache Operations
// These require additional tables - use protocol defaults for now

// MARK: - Profile Metadata

public func saveProfileMetadata(pubkey: String, metadata: [String: Any], updatedAt: Timestamp, eventId: String) async throws {
    // NostrDB automatically parses kind 0 events into profiles
    // This is a no-op as nostrdb handles it internally
}

public func getProfileMetadata(pubkey: String) async -> (metadata: [String: Any], updatedAt: Timestamp, eventId: String)? {
    guard let pk = Pubkey(pubkey) else { return nil }
    guard let txn = ndb.lookup_profile(pk) else { return nil }

    let profileRecord = txn.unsafeUnownedValue
    guard let record = profileRecord, let profile = record.data.profile else { return nil }

    var metadata: [String: Any] = [:]
    if let name = profile.name { metadata["name"] = name }
    if let about = profile.about { metadata["about"] = about }
    if let picture = profile.picture { metadata["picture"] = picture }
    if let displayName = profile.displayName { metadata["display_name"] = displayName }
    if let website = profile.website { metadata["website"] = website }
    if let banner = profile.banner { metadata["banner"] = banner }
    if let nip05 = profile.nip05 { metadata["nip05"] = nip05 }
    if let lud16 = profile.lud16 { metadata["lud16"] = lud16 }
    if let lud06 = profile.lud06 { metadata["lud06"] = lud06 }

    return (metadata: metadata, updatedAt: Timestamp(record.data.receivedAt), eventId: "")
}

public func getMultipleProfileMetadata(pubkeys: [String]) async -> [String: (metadata: [String: Any], updatedAt: Timestamp, eventId: String)] {
    var results: [String: (metadata: [String: Any], updatedAt: Timestamp, eventId: String)] = [:]
    for pubkey in pubkeys {
        if let metadata = await getProfileMetadata(pubkey: pubkey) {
            results[pubkey] = metadata
        }
    }
    return results
}

// MARK: - Relay Sources

public func processEvent(_ event: NDKEvent, from relay: String, subscriptionId: String) async throws {
    // NostrDB tracks relay sources internally when processing events
    let json = "[\"\(relay)\",\(try event.toRelayJSON())]"
    _ = ndb.process_event(json, originRelayURL: relay)
}

public func getRelaySources(eventId: String) async -> Set<String> {
    // NostrDB has this data but API is via ndb_note_seen_on_relay
    // Return empty for now - can be implemented with specific relay checks
    return []
}

// MARK: - Full Text Search (NostrDB bonus feature!)

/// Search events using NostrDB's full-text search
/// - Parameters:
///   - query: Search query string
///   - limit: Maximum results
///   - order: Sort order (newest or oldest first)
/// - Returns: Array of matching events
public func textSearch(_ query: String, limit: Int = 50, order: NdbSearchOrder = .newest_first) async -> [NDKEvent] {
    let noteKeys = ndb.text_search(query: query, limit: limit, order: order)

    guard let txn = NdbTxn(ndb: ndb) else { return [] }

    var events: [NDKEvent] = []
    for key in noteKeys {
        if let note = ndb.lookup_note_by_key_with_txn(key, txn: txn),
           let event = convertToNDKEvent(note) {
            events.append(event)
        }
    }

    return events
}
```

**Step 3: Build to verify**

Run: `swift build`
Expected: Build succeeds

**Step 4: Commit**

```bash
git add Sources/NDKSwift/Cache/NDKNostrDBCache.swift
git commit -m "feat: add remaining NDKCache protocol methods to NDKNostrDBCache"
```

---

### Task 9: Add Cache Type Configuration to NDK

**Files:**
- Modify: `Sources/NDKSwift/Core/NDK.swift` (or wherever NDK is initialized)
- Create: `Sources/NDKSwift/Cache/CacheType.swift`

**Step 1: Create cache type enum**

```swift
// Sources/NDKSwift/Cache/CacheType.swift

import Foundation

/// Available cache implementations
public enum NDKCacheType: Sendable {
    /// SQLite-based cache (default, more features)
    case sqlite

    /// NostrDB-based cache (faster, uses LMDB)
    case nostrdb

    /// In-memory cache (no persistence)
    case memory

    /// Custom cache implementation
    case custom(any NDKCache)
}
```

**Step 2: Update NDK initialization to accept cache type**

Add to NDK's configuration:

```swift
/// Create cache instance based on type
internal func createCache(type: NDKCacheType, path: String?) async throws -> any NDKCache {
    switch type {
    case .sqlite:
        return try await NDKSQLiteCache(path: path)
    case .nostrdb:
        return try await NDKNostrDBCache(path: path)
    case .memory:
        return MemoryCache()
    case .custom(let cache):
        return cache
    }
}
```

**Step 3: Commit**

```bash
git add Sources/NDKSwift/Cache/CacheType.swift
git add Sources/NDKSwift/Core/NDK.swift
git commit -m "feat: add cache type configuration to NDK"
```

---

## Phase 3: Testing and Validation

### Task 10: Add Comprehensive Tests for NDKNostrDBCache

**Files:**
- Modify: `Tests/NDKSwiftTests/Unit/Cache/NDKNostrDBCacheTests.swift`

**Step 1: Add query tests**

```swift
func testQueryEventsByKind() async throws {
    // Save multiple events of different kinds
    let textNote = createTestEvent(kind: 1, content: "Text note")
    let metadata = createTestEvent(kind: 0, content: "{\"name\":\"test\"}")

    try await cache.saveEvent(textNote)
    try await cache.saveEvent(metadata)

    // Query for kind 1 only
    let filter = NDKFilter(kinds: [1])
    let results = try await cache.queryEvents(filter)

    XCTAssertEqual(results.count, 1)
    XCTAssertEqual(results.first?.kind, 1)
}

func testQueryEventsByAuthor() async throws {
    let pubkey1 = String(repeating: "a", count: 64)
    let pubkey2 = String(repeating: "b", count: 64)

    let event1 = createTestEvent(pubkey: pubkey1, content: "From author 1")
    let event2 = createTestEvent(pubkey: pubkey2, content: "From author 2")

    try await cache.saveEvent(event1)
    try await cache.saveEvent(event2)

    let filter = NDKFilter(authors: [pubkey1])
    let results = try await cache.queryEvents(filter)

    XCTAssertEqual(results.count, 1)
    XCTAssertEqual(results.first?.pubkey, pubkey1)
}

func testTextSearch() async throws {
    let event1 = createTestEvent(content: "Bitcoin is digital gold")
    let event2 = createTestEvent(content: "Lightning network is fast")

    try await cache.saveEvent(event1)
    try await cache.saveEvent(event2)

    // Wait for indexing
    try await Task.sleep(nanoseconds: 100_000_000)

    let results = await cache.textSearch("bitcoin", limit: 10)

    XCTAssertEqual(results.count, 1)
    XCTAssertTrue(results.first?.content.lowercased().contains("bitcoin") ?? false)
}

// Helper to create test events
private func createTestEvent(
    id: String? = nil,
    pubkey: String = String(repeating: "ab", count: 32),
    kind: Int = 1,
    content: String = "Test content"
) -> NDKEvent {
    let eventId = id ?? UUID().uuidString.replacingOccurrences(of: "-", with: "").padding(toLength: 64, withPad: "0", startingAt: 0)
    return NDKEvent(
        id: eventId,
        pubkey: pubkey,
        createdAt: Timestamp(Date().timeIntervalSince1970),
        kind: Kind(kind),
        tags: [],
        content: content,
        sig: String(repeating: "cd", count: 64)
    )
}
```

**Step 2: Run all cache tests**

Run: `swift test --filter NDKNostrDBCacheTests`
Expected: All tests PASS

**Step 3: Commit**

```bash
git add Tests/NDKSwiftTests/Unit/Cache/NDKNostrDBCacheTests.swift
git commit -m "test: add comprehensive tests for NDKNostrDBCache"
```

---

### Task 11: Run Full Test Suite

**Step 1: Run all tests**

Run: `swift test`
Expected: All tests pass

**Step 2: Fix any failures**

If tests fail, investigate and fix.

**Step 3: Final commit**

```bash
git add -A
git commit -m "feat: complete nostrdb integration"
```

---

## Phase 4: Documentation and Cleanup

### Task 12: Update CHANGELOG

**Files:**
- Modify: `CHANGELOG.md`

**Step 1: Add entry for nostrdb integration**

```markdown
## [Unreleased]

### Added
- NostrDB cache backend (`NDKNostrDBCache`) as high-performance alternative to SQLite
- Full-text search via NostrDB's built-in search capabilities
- `NDKCacheType` enum for selecting cache implementation at initialization
- Zero-copy event access through LMDB memory mapping

### Changed
- NDK initialization now accepts optional `cacheType` parameter (defaults to `.sqlite`)

### Internal
- Added `NostrDB` target with C/Swift bindings from Damus
- All nostrdb types remain internal - no user-facing API changes
```

**Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: add nostrdb integration to CHANGELOG"
```

---

### Task 13: Update CLAUDE.md with NostrDB Notes

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Add NostrDB section**

Add under Architecture section:

```markdown
### NostrDB Integration

NDKSwift supports two cache backends:

1. **SQLite (default)**: Uses GRDB for full-featured caching including:
   - Migrations
   - Profile metadata
   - Wallet data
   - NIP-05 caching
   - Relay preferences

2. **NostrDB**: High-performance LMDB backend from Damus:
   - Zero-copy event access
   - Built-in full-text search
   - Faster queries for large datasets
   - Limited to event storage (no wallet/profile metadata)

**Architecture:**
- All nostrdb code is in `Sources/NostrDB/` (internal target)
- `NDKNostrDBCache` wraps nostrdb behind `NDKCache` protocol
- Users never interact with nostrdb types directly
- Cache type is selected at NDK initialization
```

**Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: add NostrDB architecture notes to CLAUDE.md"
```

---

## Summary

**Total Tasks:** 13
**Estimated Phases:** 4

**Phase 1 (Tasks 1-6):** Set up NostrDB target - copy sources, configure SPM, fix compilation
**Phase 2 (Tasks 7-9):** Create NDK integration - implement NDKNostrDBCache, add configuration
**Phase 3 (Tasks 10-11):** Testing - comprehensive tests, full suite validation
**Phase 4 (Tasks 12-13):** Documentation - CHANGELOG, CLAUDE.md updates

**Key Files Created:**
- `Sources/NostrDB/` - Entire nostrdb C/Swift codebase
- `Sources/NDKSwift/Cache/NDKNostrDBCache.swift` - Cache implementation
- `Sources/NDKSwift/Cache/CacheType.swift` - Cache type enum
- `Tests/NDKSwiftTests/Unit/Cache/NDKNostrDBCacheTests.swift` - Tests

**Key Modifications:**
- `Package.swift` - Add NostrDB target and dependencies
- `Sources/NDKSwift/Core/NDK.swift` - Add cache type configuration

---

Plan complete and saved to `docs/plans/2025-12-04-nostrdb-integration.md`. Two execution options:

**1. Subagent-Driven (this session)** - I dispatch fresh subagent per task, review between tasks, fast iteration

**2. Parallel Session (separate)** - Open new session with executing-plans, batch execution with checkpoints

Which approach?
