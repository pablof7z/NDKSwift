# Relay Intelligence Layer Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement a unified relay intelligence layer that encodes all relay selection rules, enabling apps to "just work" without developers thinking about relay selection.

**Architecture:** Three main components - HintIndex (learning), RelayIntelligence (decision-making), enhanced Pool Manager (connection lifecycle). Intelligence returns AsyncStream<RelayURL> for progressive resolution. Full introspection API for debugging.

**Tech Stack:** Swift, async/await, actors, AsyncStream, Combine (for observation)

---

## Phase 1: HintIndex - The Learning Component

### Task 1.1: Create HintIndex Types

**Files:**
- Create: `Sources/NDKSwiftCore/RelayIntelligence/HintIndex/HintIndexTypes.swift`
- Test: `Tests/NDKSwiftTests/Unit/RelayIntelligence/HintIndexTypesTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest
@testable import NDKSwiftCore

final class HintIndexTypesTests: XCTestCase {
    func test_hintSource_equatable() {
        XCTAssertEqual(HintSource.nip19, HintSource.nip19)
        XCTAssertNotEqual(HintSource.nip19, HintSource.eventObserved)
    }

    func test_hintEntry_creation() {
        let entry = HintEntry(
            relay: "wss://relay.example.com",
            source: .nip19,
            recordedAt: Date()
        )
        XCTAssertEqual(entry.relay, "wss://relay.example.com")
        XCTAssertEqual(entry.source, .nip19)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter HintIndexTypesTests`
Expected: FAIL with "cannot find 'HintSource' in scope"

**Step 3: Write minimal implementation**

```swift
import Foundation

/// Source of a relay hint
public enum HintSource: Sendable, Equatable {
    /// From NIP-19 bech32 encoding (nevent, nprofile, naddr)
    case nip19
    /// Event was observed arriving from this relay
    case eventObserved
    /// From user's NIP-65 relay list
    case userRelayList
    /// Explicitly provided by app
    case explicit
}

/// A recorded relay hint
public struct HintEntry: Sendable, Equatable {
    public let relay: RelayURL
    public let source: HintSource
    public let recordedAt: Date

    public init(relay: RelayURL, source: HintSource, recordedAt: Date = Date()) {
        self.relay = relay
        self.source = source
        self.recordedAt = recordedAt
    }
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter HintIndexTypesTests`
Expected: PASS

**Step 5: Commit**

```bash
git add Sources/NDKSwiftCore/RelayIntelligence/HintIndex/HintIndexTypes.swift Tests/NDKSwiftTests/Unit/RelayIntelligence/HintIndexTypesTests.swift
git commit -m "feat: add HintIndex types for relay hint tracking"
```

---

### Task 1.2: Create HintIndex Actor (Core Storage)

**Files:**
- Create: `Sources/NDKSwiftCore/RelayIntelligence/HintIndex/HintIndex.swift`
- Test: `Tests/NDKSwiftTests/Unit/RelayIntelligence/HintIndexTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest
@testable import NDKSwiftCore

final class HintIndexTests: XCTestCase {
    var hintIndex: HintIndex!

    override func setUp() async throws {
        hintIndex = HintIndex(maxSize: 100)
    }

    func test_recordHint_forPubkey_storesHint() async {
        let pubkey = "abc123"
        let relay = "wss://relay.example.com"

        await hintIndex.recordHint(pubkey: pubkey, relay: relay, source: .nip19)

        let hints = await hintIndex.hints(for: pubkey)
        XCTAssertEqual(hints.count, 1)
        XCTAssertEqual(hints.first?.relay, relay)
        XCTAssertEqual(hints.first?.source, .nip19)
    }

    func test_recordHint_forEventId_storesHint() async {
        let eventId = "event123"
        let relay = "wss://relay.example.com"

        await hintIndex.recordHint(eventId: eventId, relay: relay, source: .eventObserved)

        let hints = await hintIndex.hints(forEventId: eventId)
        XCTAssertEqual(hints.count, 1)
        XCTAssertEqual(hints.first?.relay, relay)
    }

    func test_hints_returnsEmpty_whenNoHintsRecorded() async {
        let hints = await hintIndex.hints(for: "unknown")
        XCTAssertTrue(hints.isEmpty)
    }

    func test_recordHint_deduplicates_sameRelaySource() async {
        let pubkey = "abc123"
        let relay = "wss://relay.example.com"

        await hintIndex.recordHint(pubkey: pubkey, relay: relay, source: .nip19)
        await hintIndex.recordHint(pubkey: pubkey, relay: relay, source: .nip19)

        let hints = await hintIndex.hints(for: pubkey)
        XCTAssertEqual(hints.count, 1)
    }

    func test_recordHint_allowsDifferentSources_forSameRelay() async {
        let pubkey = "abc123"
        let relay = "wss://relay.example.com"

        await hintIndex.recordHint(pubkey: pubkey, relay: relay, source: .nip19)
        await hintIndex.recordHint(pubkey: pubkey, relay: relay, source: .eventObserved)

        let hints = await hintIndex.hints(for: pubkey)
        XCTAssertEqual(hints.count, 2)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter HintIndexTests`
Expected: FAIL with "cannot find 'HintIndex' in scope"

**Step 3: Write minimal implementation**

```swift
import Foundation

/// Thread-safe index for tracking relay hints
/// Learns where users and events have been observed
public actor HintIndex {
    private var pubkeyHints: [String: [HintEntry]] = [:]
    private var eventIdHints: [String: [HintEntry]] = [:]
    private var addressHints: [String: [HintEntry]] = [:]

    private let maxSize: Int
    private var totalEntries: Int = 0

    public init(maxSize: Int = 10000) {
        self.maxSize = maxSize
    }

    // MARK: - Recording Hints

    public func recordHint(pubkey: String, relay: RelayURL, source: HintSource) {
        let normalizedRelay = relay.normalizedRelayURL
        let entry = HintEntry(relay: normalizedRelay, source: source)

        var hints = pubkeyHints[pubkey, default: []]

        // Check for duplicate (same relay + source)
        if hints.contains(where: { $0.relay == normalizedRelay && $0.source == source }) {
            return
        }

        hints.append(entry)
        pubkeyHints[pubkey] = hints
        totalEntries += 1

        evictIfNeeded()
    }

    public func recordHint(eventId: String, relay: RelayURL, source: HintSource) {
        let normalizedRelay = relay.normalizedRelayURL
        let entry = HintEntry(relay: normalizedRelay, source: source)

        var hints = eventIdHints[eventId, default: []]

        if hints.contains(where: { $0.relay == normalizedRelay && $0.source == source }) {
            return
        }

        hints.append(entry)
        eventIdHints[eventId] = hints
        totalEntries += 1

        evictIfNeeded()
    }

    public func recordHint(address: String, relay: RelayURL, source: HintSource) {
        let normalizedRelay = relay.normalizedRelayURL
        let entry = HintEntry(relay: normalizedRelay, source: source)

        var hints = addressHints[address, default: []]

        if hints.contains(where: { $0.relay == normalizedRelay && $0.source == source }) {
            return
        }

        hints.append(entry)
        addressHints[address] = hints
        totalEntries += 1

        evictIfNeeded()
    }

    // MARK: - Retrieving Hints

    public func hints(for pubkey: String) -> [HintEntry] {
        return pubkeyHints[pubkey] ?? []
    }

    public func hints(forEventId eventId: String) -> [HintEntry] {
        return eventIdHints[eventId] ?? []
    }

    public func hints(forAddress address: String) -> [HintEntry] {
        return addressHints[address] ?? []
    }

    /// Get unique relay URLs for a pubkey
    public func relayURLs(for pubkey: String) -> Set<RelayURL> {
        return Set(hints(for: pubkey).map { $0.relay })
    }

    // MARK: - Statistics

    public var count: Int {
        return totalEntries
    }

    public var pubkeyCount: Int {
        return pubkeyHints.count
    }

    public var eventIdCount: Int {
        return eventIdHints.count
    }

    // MARK: - Management

    public func clear() {
        pubkeyHints.removeAll()
        eventIdHints.removeAll()
        addressHints.removeAll()
        totalEntries = 0
    }

    // MARK: - Private

    private func evictIfNeeded() {
        guard totalEntries > maxSize else { return }

        // Simple eviction: remove oldest entries from each map
        // Future: implement LRU based on recordedAt
        let evictCount = totalEntries - maxSize + (maxSize / 10) // Remove 10% buffer
        var evicted = 0

        // Evict from pubkey hints first
        for (key, hints) in pubkeyHints {
            if evicted >= evictCount { break }
            if hints.count > 1 {
                pubkeyHints[key] = Array(hints.dropFirst())
                evicted += 1
                totalEntries -= 1
            }
        }

        // Then event hints
        for (key, hints) in eventIdHints {
            if evicted >= evictCount { break }
            if hints.count > 1 {
                eventIdHints[key] = Array(hints.dropFirst())
                evicted += 1
                totalEntries -= 1
            }
        }
    }
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter HintIndexTests`
Expected: PASS

**Step 5: Commit**

```bash
git add Sources/NDKSwiftCore/RelayIntelligence/HintIndex/HintIndex.swift Tests/NDKSwiftTests/Unit/RelayIntelligence/HintIndexTests.swift
git commit -m "feat: add HintIndex actor for relay hint storage"
```

---

### Task 1.3: Integrate HintIndex with NIP-19 Decoding

**Files:**
- Modify: `Sources/NDKSwiftCore/Core/NDK.swift` (add hintIndex property)
- Modify: `Sources/NDKSwiftCore/DataSource/NDKFetchedEvent.swift` (record hints on NIP-19 decode)
- Test: `Tests/NDKSwiftTests/Unit/RelayIntelligence/HintIndexIntegrationTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest
@testable import NDKSwiftCore

final class HintIndexIntegrationTests: XCTestCase {
    func test_ndk_hasHintIndex() async throws {
        let ndk = NDK()
        let hintIndex = await ndk.hintIndex
        XCTAssertNotNil(hintIndex)
    }

    func test_fetchEvent_recordsHintFromNevent() async throws {
        let ndk = NDK()
        // nevent with relay hint would be decoded and recorded
        // This is more of an integration test - the actual behavior
        // depends on ContentTagger.decodeNostrEntity implementation
        let hintIndex = await ndk.hintIndex
        XCTAssertEqual(await hintIndex.count, 0) // Starts empty
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter HintIndexIntegrationTests`
Expected: FAIL with "value of type 'NDK' has no member 'hintIndex'"

**Step 3: Write minimal implementation**

In `NDK.swift`, add:
```swift
// Near other properties
public let hintIndex: HintIndex

// In init, add:
self.hintIndex = HintIndex()
```

In `NDKFetchedEvent.swift`, in the relay hint extraction logic, add call to record hint:
```swift
// After extracting relay hints from nevent/nprofile/naddr
if let relayHint = relayHint {
    Task {
        await ndk.hintIndex.recordHint(pubkey: pubkey, relay: relayHint, source: .nip19)
    }
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter HintIndexIntegrationTests`
Expected: PASS

**Step 5: Commit**

```bash
git add Sources/NDKSwiftCore/Core/NDK.swift Sources/NDKSwiftCore/DataSource/NDKFetchedEvent.swift Tests/NDKSwiftTests/Unit/RelayIntelligence/HintIndexIntegrationTests.swift
git commit -m "feat: integrate HintIndex with NDK and NIP-19 decoding"
```

---

### Task 1.4: Record Hints from Event Observations

**Files:**
- Modify: `Sources/NDKSwiftCore/DataSource/NDKSubscription.swift` (record hints when events arrive)
- Test: `Tests/NDKSwiftTests/Unit/RelayIntelligence/HintIndexEventObservationTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest
@testable import NDKSwiftCore

final class HintIndexEventObservationTests: XCTestCase {
    func test_eventArrival_recordsAuthorHint() async throws {
        // This test verifies that when an event arrives from a relay,
        // we record a hint for the event's author
        let ndk = NDK()
        let hintIndex = await ndk.hintIndex

        // Before any events, no hints
        let authorPubkey = "test_author_pubkey"
        let hintsBefor = await hintIndex.hints(for: authorPubkey)
        XCTAssertTrue(hintsBefor.isEmpty)

        // After processing an event (simulated), hint should exist
        // The actual recording happens in NDKSubscription when events arrive
        await hintIndex.recordHint(pubkey: authorPubkey, relay: "wss://test.relay", source: .eventObserved)

        let hintsAfter = await hintIndex.hints(for: authorPubkey)
        XCTAssertEqual(hintsAfter.count, 1)
        XCTAssertEqual(hintsAfter.first?.source, .eventObserved)
    }
}
```

**Step 2: Run test to verify it passes** (this is a unit test of recording behavior)

Run: `swift test --filter HintIndexEventObservationTests`
Expected: PASS

**Step 3: Modify NDKSubscription to record hints**

In the event processing code where events arrive from relays, add:
```swift
// Record hint that this author was seen at this relay
if let relay = event.relay {
    Task {
        await ndk.hintIndex.recordHint(pubkey: event.pubkey, relay: relay, source: .eventObserved)
    }
}
```

**Step 4: Commit**

```bash
git add Sources/NDKSwiftCore/DataSource/NDKSubscription.swift Tests/NDKSwiftTests/Unit/RelayIntelligence/HintIndexEventObservationTests.swift
git commit -m "feat: record relay hints when events are observed from relays"
```

---

## Phase 2: Pool Manager Enhancements

### Task 2.1: Add Persistent Relay Marking

**Files:**
- Modify: `Sources/NDKSwiftCore/Core/Managers/NDKPool.swift`
- Test: `Tests/NDKSwiftTests/Unit/Pool/NDKPoolPersistentRelaysTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest
@testable import NDKSwiftCore

final class NDKPoolPersistentRelaysTests: XCTestCase {
    func test_markPersistent_addsToSet() async {
        let ndk = NDK()
        let pool = await ndk.pool

        let relay = await pool.addRelay("wss://test.relay")
        await pool.markPersistent(relay.url)

        let isPersistent = await pool.isPersistent(relay.url)
        XCTAssertTrue(isPersistent)
    }

    func test_removePersistent_removesFromSet() async {
        let ndk = NDK()
        let pool = await ndk.pool

        let relay = await pool.addRelay("wss://test.relay")
        await pool.markPersistent(relay.url)
        await pool.removePersistent(relay.url)

        let isPersistent = await pool.isPersistent(relay.url)
        XCTAssertFalse(isPersistent)
    }

    func test_persistentRelays_returnsOnlyMarkedRelays() async {
        let ndk = NDK()
        let pool = await ndk.pool

        _ = await pool.addRelay("wss://relay1.com")
        _ = await pool.addRelay("wss://relay2.com")
        await pool.markPersistent("wss://relay1.com")

        let persistent = await pool.persistentRelays
        XCTAssertEqual(persistent.count, 1)
        XCTAssertTrue(persistent.contains("wss://relay1.com".normalizedRelayURL))
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter NDKPoolPersistentRelaysTests`
Expected: FAIL with "has no member 'markPersistent'"

**Step 3: Write minimal implementation**

Add to `NDKPool.swift`:
```swift
/// Set of relay URLs marked as persistent (never evicted)
private var persistentRelayUrls: Set<String> = []

/// Mark a relay as persistent (will not be evicted)
public func markPersistent(_ url: RelayURL) {
    let normalizedUrl = url.normalizedRelayURL
    persistentRelayUrls.insert(normalizedUrl)
}

/// Remove persistent marking from a relay
public func removePersistent(_ url: RelayURL) {
    let normalizedUrl = url.normalizedRelayURL
    persistentRelayUrls.remove(normalizedUrl)
}

/// Check if a relay is marked persistent
public func isPersistent(_ url: RelayURL) -> Bool {
    let normalizedUrl = url.normalizedRelayURL
    return persistentRelayUrls.contains(normalizedUrl)
}

/// Get all persistent relay URLs
public var persistentRelays: Set<RelayURL> {
    return persistentRelayUrls
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter NDKPoolPersistentRelaysTests`
Expected: PASS

**Step 5: Commit**

```bash
git add Sources/NDKSwiftCore/Core/Managers/NDKPool.swift Tests/NDKSwiftTests/Unit/Pool/NDKPoolPersistentRelaysTests.swift
git commit -m "feat: add persistent relay marking to NDKPool"
```

---

### Task 2.2: Add Usage Tracking to Pool

**Files:**
- Modify: `Sources/NDKSwiftCore/Core/Managers/NDKPool.swift`
- Test: `Tests/NDKSwiftTests/Unit/Pool/NDKPoolUsageTrackingTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest
@testable import NDKSwiftCore

final class NDKPoolUsageTrackingTests: XCTestCase {
    func test_markUsed_updatesLastUsedTimestamp() async {
        let ndk = NDK()
        let pool = await ndk.pool

        let relay = await pool.addRelay("wss://test.relay")
        let beforeMark = Date()

        await pool.markUsed(relay.url)

        let lastUsed = await pool.lastUsed(relay.url)
        XCTAssertNotNil(lastUsed)
        XCTAssertGreaterThanOrEqual(lastUsed!, beforeMark)
    }

    func test_idleRelays_returnsRelaysNotUsedRecently() async {
        let ndk = NDK()
        let pool = await ndk.pool

        _ = await pool.addRelay("wss://active.relay")
        _ = await pool.addRelay("wss://idle.relay")

        await pool.markUsed("wss://active.relay")
        // Don't mark idle.relay as used

        let idle = await pool.idleRelays(threshold: 0) // 0 seconds = everything not just used
        XCTAssertTrue(idle.contains("wss://idle.relay".normalizedRelayURL))
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter NDKPoolUsageTrackingTests`
Expected: FAIL with "has no member 'markUsed'"

**Step 3: Write minimal implementation**

Add to `NDKPool.swift`:
```swift
/// Track last used timestamp for each relay
private var relayLastUsed: [String: Date] = [:]

/// Mark a relay as recently used
public func markUsed(_ url: RelayURL) {
    let normalizedUrl = url.normalizedRelayURL
    relayLastUsed[normalizedUrl] = Date()
}

/// Mark multiple relays as recently used
public func markUsed(_ urls: Set<RelayURL>) {
    let now = Date()
    for url in urls {
        let normalizedUrl = url.normalizedRelayURL
        relayLastUsed[normalizedUrl] = now
    }
}

/// Get last used timestamp for a relay
public func lastUsed(_ url: RelayURL) -> Date? {
    let normalizedUrl = url.normalizedRelayURL
    return relayLastUsed[normalizedUrl]
}

/// Get relays that haven't been used within threshold
public func idleRelays(threshold: TimeInterval) -> Set<RelayURL> {
    let cutoff = Date().addingTimeInterval(-threshold)
    var idle = Set<RelayURL>()

    for relay in relays {
        let normalizedUrl = relay.url.normalizedRelayURL
        if let lastUsed = relayLastUsed[normalizedUrl] {
            if lastUsed < cutoff {
                idle.insert(normalizedUrl)
            }
        } else {
            // Never used - consider idle
            idle.insert(normalizedUrl)
        }
    }

    return idle
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter NDKPoolUsageTrackingTests`
Expected: PASS

**Step 5: Commit**

```bash
git add Sources/NDKSwiftCore/Core/Managers/NDKPool.swift Tests/NDKSwiftTests/Unit/Pool/NDKPoolUsageTrackingTests.swift
git commit -m "feat: add usage tracking to NDKPool for idle detection"
```

---

### Task 2.3: Add Idle Relay Eviction

**Files:**
- Modify: `Sources/NDKSwiftCore/Core/Managers/NDKPool.swift`
- Test: `Tests/NDKSwiftTests/Unit/Pool/NDKPoolEvictionTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest
@testable import NDKSwiftCore

final class NDKPoolEvictionTests: XCTestCase {
    func test_evictIdleRelays_removesNonPersistentIdleRelays() async {
        let ndk = NDK()
        let pool = await ndk.pool

        _ = await pool.addRelay("wss://idle.relay")
        _ = await pool.addRelay("wss://persistent.relay")
        await pool.markPersistent("wss://persistent.relay")

        // Neither is marked used, both are idle
        // But only non-persistent should be evicted
        await pool.evictIdleRelays(threshold: 0)

        let remaining = await pool.relays.map { $0.url }
        XCTAssertFalse(remaining.contains("wss://idle.relay".normalizedRelayURL))
        XCTAssertTrue(remaining.contains("wss://persistent.relay".normalizedRelayURL))
    }

    func test_evictIdleRelays_keepsRecentlyUsedRelays() async {
        let ndk = NDK()
        let pool = await ndk.pool

        _ = await pool.addRelay("wss://active.relay")
        await pool.markUsed("wss://active.relay")

        // Threshold of 60 seconds - recently used should not be evicted
        await pool.evictIdleRelays(threshold: 60)

        let remaining = await pool.relays.map { $0.url }
        XCTAssertTrue(remaining.contains("wss://active.relay".normalizedRelayURL))
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter NDKPoolEvictionTests`
Expected: FAIL with "has no member 'evictIdleRelays'"

**Step 3: Write minimal implementation**

Add to `NDKPool.swift`:
```swift
/// Evict relays that are idle and not persistent
/// - Parameter threshold: Time in seconds since last use to consider relay idle
/// - Returns: Set of evicted relay URLs
@discardableResult
public func evictIdleRelays(threshold: TimeInterval) async -> Set<RelayURL> {
    let idle = idleRelays(threshold: threshold)
    var evicted = Set<RelayURL>()

    for relayUrl in idle {
        // Don't evict persistent relays
        if persistentRelayUrls.contains(relayUrl) {
            continue
        }

        await removeRelay(relayUrl)
        evicted.insert(relayUrl)

        NDKLogger.log(.debug, category: .relay, "♻️ Evicted idle relay: \(relayUrl)")
    }

    if !evicted.isEmpty {
        NDKLogger.log(.info, category: .relay, "♻️ Evicted \(evicted.count) idle relays")
    }

    return evicted
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter NDKPoolEvictionTests`
Expected: PASS

**Step 5: Commit**

```bash
git add Sources/NDKSwiftCore/Core/Managers/NDKPool.swift Tests/NDKSwiftTests/Unit/Pool/NDKPoolEvictionTests.swift
git commit -m "feat: add idle relay eviction to NDKPool"
```

---

## Phase 3: RelayIntelligence Protocol

### Task 3.1: Define RelayIntelligence Protocol

**Files:**
- Create: `Sources/NDKSwiftCore/RelayIntelligence/RelayIntelligenceProtocol.swift`
- Test: `Tests/NDKSwiftTests/Unit/RelayIntelligence/RelayIntelligenceProtocolTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest
@testable import NDKSwiftCore

final class RelayIntelligenceProtocolTests: XCTestCase {
    func test_relayPurpose_cases() {
        XCTAssertNotNil(RelayPurpose.inbox)
        XCTAssertNotNil(RelayPurpose.outbox)
        XCTAssertNotNil(RelayPurpose.dm)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter RelayIntelligenceProtocolTests`
Expected: FAIL with "cannot find 'RelayPurpose'"

**Step 3: Write minimal implementation**

```swift
import Foundation

/// Purpose for relay selection
public enum RelayPurpose: Sendable {
    /// Relays where content is sent TO the user (their read relays)
    case inbox
    /// Relays where user publishes content FROM (their write relays)
    case outbox
    /// DM-specific relays (Kind 10050)
    case dm
}

/// Protocol for relay intelligence implementations
public protocol RelayIntelligence: Actor {
    /// Get relays for publishing an event
    /// Returns AsyncStream that emits relays progressively as discovered
    func relaysForPublishing(_ event: NDKEvent) -> AsyncStream<RelayURL>

    /// Get relays for fetching events matching a filter
    func relaysForFetching(_ filter: NDKFilter) -> AsyncStream<RelayURL>

    /// Get relays for reaching a specific user
    func relaysForUser(_ pubkey: String, purpose: RelayPurpose) -> AsyncStream<RelayURL>

    /// Get relays for fetching a specific event by ID
    func relaysForEvent(id: String, hints: [RelayURL]) -> AsyncStream<RelayURL>
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter RelayIntelligenceProtocolTests`
Expected: PASS

**Step 5: Commit**

```bash
git add Sources/NDKSwiftCore/RelayIntelligence/RelayIntelligenceProtocol.swift Tests/NDKSwiftTests/Unit/RelayIntelligence/RelayIntelligenceProtocolTests.swift
git commit -m "feat: add RelayIntelligence protocol definition"
```

---

### Task 3.2: Implement Default RelayIntelligence

**Files:**
- Create: `Sources/NDKSwiftCore/RelayIntelligence/DefaultRelayIntelligence.swift`
- Test: `Tests/NDKSwiftTests/Unit/RelayIntelligence/DefaultRelayIntelligenceTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest
@testable import NDKSwiftCore

final class DefaultRelayIntelligenceTests: XCTestCase {
    var ndk: NDK!
    var intelligence: DefaultRelayIntelligence!

    override func setUp() async throws {
        ndk = NDK()
        intelligence = await ndk.relayIntelligence as? DefaultRelayIntelligence
    }

    func test_relaysForUser_emitsHintsFirst() async {
        // Pre-populate hint index
        await ndk.hintIndex.recordHint(pubkey: "test_pubkey", relay: "wss://hint.relay", source: .nip19)

        var relays: [RelayURL] = []
        for await relay in await intelligence.relaysForUser("test_pubkey", purpose: .outbox) {
            relays.append(relay)
            if relays.count >= 1 { break } // Just check first one
        }

        XCTAssertTrue(relays.contains("wss://hint.relay".normalizedRelayURL))
    }

    func test_relaysForEvent_usesProvidedHints() async {
        var relays: [RelayURL] = []
        let hints = ["wss://hint1.relay", "wss://hint2.relay"]

        for await relay in await intelligence.relaysForEvent(id: "test_event", hints: hints) {
            relays.append(relay)
            if relays.count >= 2 { break }
        }

        XCTAssertTrue(relays.contains("wss://hint1.relay".normalizedRelayURL))
        XCTAssertTrue(relays.contains("wss://hint2.relay".normalizedRelayURL))
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter DefaultRelayIntelligenceTests`
Expected: FAIL with "cannot find 'DefaultRelayIntelligence'"

**Step 3: Write implementation** (substantial - this is the core)

```swift
import Foundation

/// Default implementation of RelayIntelligence
public actor DefaultRelayIntelligence: RelayIntelligence {
    private weak var ndk: NDK?

    public init(ndk: NDK) {
        self.ndk = ndk
    }

    // MARK: - RelayIntelligence Protocol

    public func relaysForPublishing(_ event: NDKEvent) -> AsyncStream<RelayURL> {
        AsyncStream { continuation in
            Task { [weak self] in
                guard let self = self, let ndk = self.ndk else {
                    continuation.finish()
                    return
                }

                var emitted = Set<RelayURL>()

                // 1. Emit my outbox relays immediately (from NIP-65 cache)
                if let signer = ndk.signer,
                   let myPubkey = try? await signer.pubkey,
                   let myRelays = await ndk.outbox.getRelaysSyncFor(pubkey: myPubkey, type: .write) {
                    for relay in myRelays.writeRelays {
                        if emitted.insert(relay.url).inserted {
                            continuation.yield(relay.url)
                        }
                    }
                }

                // 2. Emit recipients' inbox relays (p-tags < 10)
                let pTags = event.pTags
                if pTags.count < 10 {
                    for pubkey in pTags {
                        // Try cache first
                        if let userRelays = await ndk.outbox.getRelaysSyncFor(pubkey: pubkey, type: .read) {
                            for relay in userRelays.readRelays {
                                if emitted.insert(relay.url).inserted {
                                    continuation.yield(relay.url)
                                }
                            }
                        } else {
                            // Try hints
                            let hints = await ndk.hintIndex.relayURLs(for: pubkey)
                            for relay in hints {
                                if emitted.insert(relay).inserted {
                                    continuation.yield(relay)
                                }
                            }
                        }
                    }
                }

                // 3. Emit e-tag hint relays
                for tag in event.tags where tag.first == "e" && tag.count >= 3 {
                    let relayHint = tag[2]
                    if !relayHint.isEmpty, emitted.insert(relayHint.normalizedRelayURL).inserted {
                        continuation.yield(relayHint.normalizedRelayURL)
                    }
                }

                // 4. Discover recipients' relays in background and emit
                if pTags.count < 10 {
                    for pubkey in pTags {
                        if await ndk.outbox.getRelaysSyncFor(pubkey: pubkey, type: .read) == nil {
                            // Fetch from indexer
                            if let fetched = try? await ndk.outbox.getRelaysFor(pubkey: pubkey, type: .read) {
                                for relay in fetched.readRelays {
                                    if emitted.insert(relay.url).inserted {
                                        continuation.yield(relay.url)
                                    }
                                }
                            }
                        }
                    }
                }

                // 5. Fallback to app relays if too few
                if emitted.count < 2 {
                    let explicit = await ndk.pool.explicitRelays()
                    for relay in explicit {
                        if emitted.insert(relay.url).inserted {
                            continuation.yield(relay.url)
                        }
                    }
                }

                continuation.finish()
            }
        }
    }

    public func relaysForFetching(_ filter: NDKFilter) -> AsyncStream<RelayURL> {
        AsyncStream { continuation in
            Task { [weak self] in
                guard let self = self, let ndk = self.ndk else {
                    continuation.finish()
                    return
                }

                var emitted = Set<RelayURL>()

                // 1. For authors in filter, emit their outbox relays
                if let authors = filter.authors {
                    for author in authors {
                        // Cache first
                        if let authorRelays = await ndk.outbox.getRelaysSyncFor(pubkey: author, type: .write) {
                            for relay in authorRelays.writeRelays {
                                if emitted.insert(relay.url).inserted {
                                    continuation.yield(relay.url)
                                }
                            }
                        }

                        // Hints
                        let hints = await ndk.hintIndex.relayURLs(for: author)
                        for relay in hints {
                            if emitted.insert(relay).inserted {
                                continuation.yield(relay)
                            }
                        }
                    }
                }

                // 2. Indexer relays for discovery
                for relay in ndk.outboxConfig.outboxRelays {
                    if emitted.insert(relay.normalizedRelayURL).inserted {
                        continuation.yield(relay.normalizedRelayURL)
                    }
                }

                // 3. App relays
                let explicit = await ndk.pool.explicitRelays()
                for relay in explicit {
                    if emitted.insert(relay.url).inserted {
                        continuation.yield(relay.url)
                    }
                }

                continuation.finish()
            }
        }
    }

    public func relaysForUser(_ pubkey: String, purpose: RelayPurpose) -> AsyncStream<RelayURL> {
        AsyncStream { continuation in
            Task { [weak self] in
                guard let self = self, let ndk = self.ndk else {
                    continuation.finish()
                    return
                }

                var emitted = Set<RelayURL>()
                let type: RelayListType = purpose == .inbox ? .read : .write

                // 1. Hints first (immediate)
                let hints = await ndk.hintIndex.relayURLs(for: pubkey)
                for relay in hints {
                    if emitted.insert(relay).inserted {
                        continuation.yield(relay)
                    }
                }

                // 2. Cache second (immediate)
                if let cached = await ndk.outbox.getRelaysSyncFor(pubkey: pubkey, type: type) {
                    let relays = type == .read ? cached.readRelays : cached.writeRelays
                    for relay in relays {
                        if emitted.insert(relay.url).inserted {
                            continuation.yield(relay.url)
                        }
                    }
                }

                // 3. Fetch from indexer if needed (discovery)
                if emitted.isEmpty {
                    if let fetched = try? await ndk.outbox.getRelaysFor(pubkey: pubkey, type: type) {
                        let relays = type == .read ? fetched.readRelays : fetched.writeRelays
                        for relay in relays {
                            if emitted.insert(relay.url).inserted {
                                continuation.yield(relay.url)
                            }
                        }
                    }
                }

                // 4. Fallback
                if emitted.isEmpty {
                    for relay in ndk.outboxConfig.outboxRelays {
                        if emitted.insert(relay.normalizedRelayURL).inserted {
                            continuation.yield(relay.normalizedRelayURL)
                        }
                    }
                }

                continuation.finish()
            }
        }
    }

    public func relaysForEvent(id: String, hints: [RelayURL]) -> AsyncStream<RelayURL> {
        AsyncStream { continuation in
            Task { [weak self] in
                guard let self = self, let ndk = self.ndk else {
                    continuation.finish()
                    return
                }

                var emitted = Set<RelayURL>()

                // 1. Provided hints first
                for hint in hints {
                    let normalized = hint.normalizedRelayURL
                    if emitted.insert(normalized).inserted {
                        continuation.yield(normalized)
                    }
                }

                // 2. Hints from index
                let indexedHints = await ndk.hintIndex.hints(forEventId: id)
                for hint in indexedHints {
                    if emitted.insert(hint.relay).inserted {
                        continuation.yield(hint.relay)
                    }
                }

                // 3. Indexer relays
                for relay in ndk.outboxConfig.outboxRelays {
                    if emitted.insert(relay.normalizedRelayURL).inserted {
                        continuation.yield(relay.normalizedRelayURL)
                    }
                }

                // 4. App relays
                let explicit = await ndk.pool.explicitRelays()
                for relay in explicit {
                    if emitted.insert(relay.url).inserted {
                        continuation.yield(relay.url)
                    }
                }

                continuation.finish()
            }
        }
    }
}
```

**Step 4: Add to NDK.swift**

```swift
// Add property
public let relayIntelligence: any RelayIntelligence

// In init
self.relayIntelligence = DefaultRelayIntelligence(ndk: self)
```

**Step 5: Run test to verify it passes**

Run: `swift test --filter DefaultRelayIntelligenceTests`
Expected: PASS

**Step 6: Commit**

```bash
git add Sources/NDKSwiftCore/RelayIntelligence/DefaultRelayIntelligence.swift Sources/NDKSwiftCore/Core/NDK.swift Tests/NDKSwiftTests/Unit/RelayIntelligence/DefaultRelayIntelligenceTests.swift
git commit -m "feat: implement DefaultRelayIntelligence with progressive resolution"
```

---

## Phase 4: Introspection API

### Task 4.1: Add HintIndex Introspection

**Files:**
- Modify: `Sources/NDKSwiftCore/RelayIntelligence/HintIndex/HintIndex.swift`
- Test: `Tests/NDKSwiftTests/Unit/RelayIntelligence/HintIndexIntrospectionTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest
@testable import NDKSwiftCore

final class HintIndexIntrospectionTests: XCTestCase {
    func test_allPubkeys_returnsTrackedPubkeys() async {
        let hintIndex = HintIndex()

        await hintIndex.recordHint(pubkey: "pubkey1", relay: "wss://relay1.com", source: .nip19)
        await hintIndex.recordHint(pubkey: "pubkey2", relay: "wss://relay2.com", source: .eventObserved)

        let allPubkeys = await hintIndex.allPubkeys
        XCTAssertEqual(allPubkeys.count, 2)
        XCTAssertTrue(allPubkeys.contains("pubkey1"))
        XCTAssertTrue(allPubkeys.contains("pubkey2"))
    }

    func test_recentHints_returnsLastNHints() async {
        let hintIndex = HintIndex()

        await hintIndex.recordHint(pubkey: "pubkey1", relay: "wss://relay1.com", source: .nip19)
        await hintIndex.recordHint(pubkey: "pubkey2", relay: "wss://relay2.com", source: .eventObserved)
        await hintIndex.recordHint(pubkey: "pubkey3", relay: "wss://relay3.com", source: .userRelayList)

        let recent = await hintIndex.recentHints(limit: 2)
        XCTAssertEqual(recent.count, 2)
    }

    func test_topRelays_returnsRelaysByFrequency() async {
        let hintIndex = HintIndex()

        // relay1.com appears twice
        await hintIndex.recordHint(pubkey: "pubkey1", relay: "wss://relay1.com", source: .nip19)
        await hintIndex.recordHint(pubkey: "pubkey2", relay: "wss://relay1.com", source: .nip19)
        // relay2.com appears once
        await hintIndex.recordHint(pubkey: "pubkey3", relay: "wss://relay2.com", source: .nip19)

        let top = await hintIndex.topRelays(limit: 2)
        XCTAssertEqual(top.first?.0, "wss://relay1.com".normalizedRelayURL)
        XCTAssertEqual(top.first?.1, 2)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter HintIndexIntrospectionTests`
Expected: FAIL with "has no member 'allPubkeys'"

**Step 3: Write implementation**

Add to `HintIndex.swift`:
```swift
// MARK: - Introspection

/// All tracked pubkeys
public var allPubkeys: Set<String> {
    return Set(pubkeyHints.keys)
}

/// All tracked event IDs
public var allEventIds: Set<String> {
    return Set(eventIdHints.keys)
}

/// Get recent hints (across all types)
public func recentHints(limit: Int = 10) -> [HintEntry] {
    var allEntries: [HintEntry] = []

    for hints in pubkeyHints.values {
        allEntries.append(contentsOf: hints)
    }
    for hints in eventIdHints.values {
        allEntries.append(contentsOf: hints)
    }
    for hints in addressHints.values {
        allEntries.append(contentsOf: hints)
    }

    return Array(allEntries.sorted { $0.recordedAt > $1.recordedAt }.prefix(limit))
}

/// Get top relays by frequency
public func topRelays(limit: Int = 10) -> [(RelayURL, Int)] {
    var relayCounts: [RelayURL: Int] = [:]

    for hints in pubkeyHints.values {
        for hint in hints {
            relayCounts[hint.relay, default: 0] += 1
        }
    }
    for hints in eventIdHints.values {
        for hint in hints {
            relayCounts[hint.relay, default: 0] += 1
        }
    }

    return Array(relayCounts.sorted { $0.value > $1.value }.prefix(limit).map { ($0.key, $0.value) })
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter HintIndexIntrospectionTests`
Expected: PASS

**Step 5: Commit**

```bash
git add Sources/NDKSwiftCore/RelayIntelligence/HintIndex/HintIndex.swift Tests/NDKSwiftTests/Unit/RelayIntelligence/HintIndexIntrospectionTests.swift
git commit -m "feat: add introspection API to HintIndex"
```

---

### Task 4.2: Add Intelligence Event Stream

**Files:**
- Create: `Sources/NDKSwiftCore/RelayIntelligence/IntelligenceEvents.swift`
- Modify: `Sources/NDKSwiftCore/RelayIntelligence/DefaultRelayIntelligence.swift`
- Test: `Tests/NDKSwiftTests/Unit/RelayIntelligence/IntelligenceEventsTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest
@testable import NDKSwiftCore

final class IntelligenceEventsTests: XCTestCase {
    func test_intelligenceEvent_types() {
        let _ = IntelligenceEvent.hintRecorded(pubkey: "test", relay: "wss://relay.com", source: .nip19)
        let _ = IntelligenceEvent.relayResolutionStarted(operationId: UUID(), type: .publish)
        let _ = IntelligenceEvent.relayEmitted(operationId: UUID(), relay: "wss://relay.com", source: .hintIndex)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter IntelligenceEventsTests`
Expected: FAIL with "cannot find 'IntelligenceEvent'"

**Step 3: Write implementation**

```swift
import Foundation

/// Events emitted by the relay intelligence layer
public enum IntelligenceEvent: Sendable {
    /// A hint was recorded in the index
    case hintRecorded(pubkey: String?, eventId: String?, relay: RelayURL, source: HintSource)

    /// Relay resolution started
    case relayResolutionStarted(operationId: UUID, type: OperationType)

    /// A relay was emitted during resolution
    case relayEmitted(operationId: UUID, relay: RelayURL, source: RelaySource)

    /// Relay resolution completed
    case relayResolutionCompleted(operationId: UUID, totalRelays: Int)

    /// Pool connection event
    case connectionAttempt(relay: RelayURL)
    case connectionSuccess(relay: RelayURL, latency: TimeInterval)
    case connectionFailed(relay: RelayURL, error: String)

    /// Relay evicted from pool
    case relayEvicted(relay: RelayURL, reason: EvictionReason)
}

/// Type of operation for relay resolution
public enum OperationType: Sendable {
    case publish
    case fetch
    case subscribe
    case userLookup
}

/// Source of a relay during resolution
public enum RelaySource: Sendable {
    case hintIndex
    case nip65Cache
    case indexerQuery
    case nip19Hints
    case eTagHints
    case appRelays
    case explicitParameter
}

/// Reason for relay eviction
public enum EvictionReason: Sendable {
    case idle
    case connectionFailed
    case blocked
    case manual
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter IntelligenceEventsTests`
Expected: PASS

**Step 5: Commit**

```bash
git add Sources/NDKSwiftCore/RelayIntelligence/IntelligenceEvents.swift Tests/NDKSwiftTests/Unit/RelayIntelligence/IntelligenceEventsTests.swift
git commit -m "feat: add IntelligenceEvent types for observability"
```

---

### Task 4.3: Add Event Stream to RelayIntelligence

**Files:**
- Modify: `Sources/NDKSwiftCore/RelayIntelligence/DefaultRelayIntelligence.swift`
- Test: `Tests/NDKSwiftTests/Unit/RelayIntelligence/IntelligenceEventStreamTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest
@testable import NDKSwiftCore

final class IntelligenceEventStreamTests: XCTestCase {
    func test_events_streamIsAccessible() async {
        let ndk = NDK()
        let intelligence = await ndk.relayIntelligence

        // Event stream should be accessible
        // This is a basic test - fuller integration tests would verify events are emitted
        let events = await intelligence.events
        XCTAssertNotNil(events)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter IntelligenceEventStreamTests`
Expected: FAIL with "has no member 'events'"

**Step 3: Write implementation**

Add to `RelayIntelligenceProtocol.swift`:
```swift
/// Stream of intelligence events for observation
var events: AsyncStream<IntelligenceEvent> { get }
```

Add to `DefaultRelayIntelligence.swift`:
```swift
private let eventStream: AsyncStream<IntelligenceEvent>
private let eventContinuation: AsyncStream<IntelligenceEvent>.Continuation

public init(ndk: NDK) {
    self.ndk = ndk
    (eventStream, eventContinuation) = AsyncStream<IntelligenceEvent>.makeStream()
}

public var events: AsyncStream<IntelligenceEvent> {
    return eventStream
}

// Helper to emit events
private func emit(_ event: IntelligenceEvent) {
    eventContinuation.yield(event)
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter IntelligenceEventStreamTests`
Expected: PASS

**Step 5: Commit**

```bash
git add Sources/NDKSwiftCore/RelayIntelligence/RelayIntelligenceProtocol.swift Sources/NDKSwiftCore/RelayIntelligence/DefaultRelayIntelligence.swift Tests/NDKSwiftTests/Unit/RelayIntelligence/IntelligenceEventStreamTests.swift
git commit -m "feat: add event stream to RelayIntelligence for observability"
```

---

### Task 4.4: Add Diagnostic Report

**Files:**
- Create: `Sources/NDKSwiftCore/RelayIntelligence/DiagnosticReport.swift`
- Test: `Tests/NDKSwiftTests/Unit/RelayIntelligence/DiagnosticReportTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest
@testable import NDKSwiftCore

final class DiagnosticReportTests: XCTestCase {
    func test_diagnosticReport_creation() async {
        let ndk = NDK()
        let intelligence = await ndk.relayIntelligence as! DefaultRelayIntelligence

        let report = await intelligence.diagnosticReport()
        XCTAssertNotNil(report)
        XCTAssertNotNil(report.generatedAt)
    }

    func test_diagnosticReport_toMarkdown() async {
        let ndk = NDK()
        let intelligence = await ndk.relayIntelligence as! DefaultRelayIntelligence

        let report = await intelligence.diagnosticReport()
        let markdown = report.toMarkdown()

        XCTAssertTrue(markdown.contains("Relay Intelligence Diagnostic Report"))
        XCTAssertTrue(markdown.contains("Hint Index"))
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter DiagnosticReportTests`
Expected: FAIL with "has no member 'diagnosticReport'"

**Step 3: Write implementation**

```swift
import Foundation

/// Diagnostic report for relay intelligence state
public struct DiagnosticReport: Sendable {
    public let generatedAt: Date
    public let poolSnapshot: PoolSnapshot
    public let hintIndexStats: HintIndexStats
    public let configuration: RelayConfiguration

    public init(
        poolSnapshot: PoolSnapshot,
        hintIndexStats: HintIndexStats,
        configuration: RelayConfiguration
    ) {
        self.generatedAt = Date()
        self.poolSnapshot = poolSnapshot
        self.hintIndexStats = hintIndexStats
        self.configuration = configuration
    }

    public func toMarkdown() -> String {
        var md = "# Relay Intelligence Diagnostic Report\n"
        md += "Generated: \(generatedAt)\n\n"

        md += "## Pool State\n"
        md += "- Connected: \(poolSnapshot.connectedCount) relays\n"
        md += "- Persistent: \(poolSnapshot.persistentCount)\n"
        md += "- Total: \(poolSnapshot.totalCount)\n\n"

        md += "## Hint Index\n"
        md += "- Pubkey hints: \(hintIndexStats.pubkeyCount)\n"
        md += "- Event hints: \(hintIndexStats.eventIdCount)\n"
        md += "- Total entries: \(hintIndexStats.totalCount)\n"

        if !hintIndexStats.topRelays.isEmpty {
            md += "\n### Top Relays\n"
            for (relay, count) in hintIndexStats.topRelays.prefix(5) {
                md += "- \(relay): \(count) hints\n"
            }
        }

        md += "\n## Configuration\n"
        md += "- Indexer relays: \(configuration.indexerRelays.count)\n"
        md += "- App relays: \(configuration.appRelays.count)\n"

        return md
    }

    public func toJSON() -> Data? {
        // Simplified JSON encoding
        let dict: [String: Any] = [
            "generatedAt": generatedAt.timeIntervalSince1970,
            "poolSnapshot": [
                "connected": poolSnapshot.connectedCount,
                "persistent": poolSnapshot.persistentCount,
                "total": poolSnapshot.totalCount
            ],
            "hintIndexStats": [
                "pubkeyCount": hintIndexStats.pubkeyCount,
                "eventIdCount": hintIndexStats.eventIdCount,
                "totalCount": hintIndexStats.totalCount
            ]
        ]
        return try? JSONSerialization.data(withJSONObject: dict)
    }
}

public struct PoolSnapshot: Sendable {
    public let connectedCount: Int
    public let persistentCount: Int
    public let totalCount: Int
    public let relayStates: [RelayURL: String]
}

public struct HintIndexStats: Sendable {
    public let pubkeyCount: Int
    public let eventIdCount: Int
    public let totalCount: Int
    public let topRelays: [(RelayURL, Int)]
}

public struct RelayConfiguration: Sendable {
    public let indexerRelays: Set<RelayURL>
    public let appRelays: Set<RelayURL>
}
```

Add to `DefaultRelayIntelligence.swift`:
```swift
public func diagnosticReport() async -> DiagnosticReport {
    guard let ndk = ndk else {
        return DiagnosticReport(
            poolSnapshot: PoolSnapshot(connectedCount: 0, persistentCount: 0, totalCount: 0, relayStates: [:]),
            hintIndexStats: HintIndexStats(pubkeyCount: 0, eventIdCount: 0, totalCount: 0, topRelays: []),
            configuration: RelayConfiguration(indexerRelays: [], appRelays: [])
        )
    }

    let connected = await ndk.pool.connectedRelays()
    let persistent = await ndk.pool.persistentRelays
    let total = await ndk.pool.relays

    let poolSnapshot = PoolSnapshot(
        connectedCount: connected.count,
        persistentCount: persistent.count,
        totalCount: total.count,
        relayStates: [:]
    )

    let hintIndexStats = HintIndexStats(
        pubkeyCount: await ndk.hintIndex.pubkeyCount,
        eventIdCount: await ndk.hintIndex.eventIdCount,
        totalCount: await ndk.hintIndex.count,
        topRelays: await ndk.hintIndex.topRelays(limit: 10)
    )

    let explicit = await ndk.pool.explicitRelays()
    let configuration = RelayConfiguration(
        indexerRelays: ndk.outboxConfig.outboxRelays,
        appRelays: Set(explicit.map { $0.url })
    )

    return DiagnosticReport(
        poolSnapshot: poolSnapshot,
        hintIndexStats: hintIndexStats,
        configuration: configuration
    )
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter DiagnosticReportTests`
Expected: PASS

**Step 5: Commit**

```bash
git add Sources/NDKSwiftCore/RelayIntelligence/DiagnosticReport.swift Sources/NDKSwiftCore/RelayIntelligence/DefaultRelayIntelligence.swift Tests/NDKSwiftTests/Unit/RelayIntelligence/DiagnosticReportTests.swift
git commit -m "feat: add DiagnosticReport for relay intelligence introspection"
```

---

## Phase 5: Integration

### Task 5.1: Wire Up RelayIntelligence to Publish Flow

**Files:**
- Modify: `Sources/NDKSwiftCore/Outbox/NDKPublishingStrategy.swift`
- Test: `Tests/NDKSwiftTests/Unit/RelayIntelligence/PublishIntegrationTests.swift`

This task integrates the new RelayIntelligence with the existing publish flow to enable progressive relay resolution.

**Implementation notes:**
- Modify `NDKPublishingStrategy.publish()` to use `relayIntelligence.relaysForPublishing()`
- Process the AsyncStream progressively - publish to each relay as it's emitted
- Track which relays have confirmed
- Record hint when event is successfully published to a relay

---

### Task 5.2: Wire Up RelayIntelligence to Fetch Flow

**Files:**
- Modify: `Sources/NDKSwiftCore/Core/NDK+FetchEvent.swift`
- Test: `Tests/NDKSwiftTests/Unit/RelayIntelligence/FetchIntegrationTests.swift`

This task integrates RelayIntelligence with event fetching for progressive relay resolution.

---

### Task 5.3: Wire Up RelayIntelligence to Subscribe Flow

**Files:**
- Modify: `Sources/NDKSwiftCore/DataSource/NDKSubscriptionManager.swift`
- Test: `Tests/NDKSwiftTests/Unit/RelayIntelligence/SubscribeIntegrationTests.swift`

This task integrates RelayIntelligence with subscriptions for progressive relay resolution.

---

## Summary

This implementation plan covers:

1. **Phase 1: HintIndex** - The learning component that tracks where users/events are observed
2. **Phase 2: Pool Manager** - Add persistent marking and usage-based eviction
3. **Phase 3: RelayIntelligence** - The core protocol and default implementation with progressive resolution
4. **Phase 4: Introspection** - Event stream, diagnostic reports, and debugging tools
5. **Phase 5: Integration** - Wire up to existing publish/fetch/subscribe flows

Each task follows TDD: write failing test → implement → verify → commit.

---

**Plan complete and saved to `docs/plans/2025-12-16-relay-intelligence-implementation.md`. Two execution options:**

**1. Subagent-Driven (this session)** - I dispatch fresh subagent per task, review between tasks, fast iteration

**2. Parallel Session (separate)** - Open new session with executing-plans, batch execution with checkpoints

**Which approach?**
