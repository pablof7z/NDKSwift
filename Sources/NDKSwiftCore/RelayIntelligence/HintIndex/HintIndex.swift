import Foundation

/// Thread-safe index for tracking relay hints.
/// Learns where users and events have been observed, enabling smarter relay selection.
public actor HintIndex {
    // MARK: - Storage

    private var pubkeyHints: [String: [HintEntry]] = [:]
    private var eventIdHints: [String: [HintEntry]] = [:]
    private var addressHints: [String: [HintEntry]] = [:]

    private let maxSize: Int
    private var totalEntries: Int = 0

    /// Min-heap ordered by `recordedAt` (oldest first). Used for O(log N) eviction.
    /// Each push corresponds to exactly one append into a per-key array; on eviction
    /// we pop the oldest record and remove the matching `(relay, source)` pair from
    /// the per-key array (each per-key array is small — typically 1-5 entries).
    private var evictionHeap: MinHeap<HeapRecord> = MinHeap()

    // MARK: - Initialization

    public init(maxSize: Int = 10000) {
        self.maxSize = maxSize
    }

    // MARK: - Recording Hints

    /// Record a relay hint for a pubkey
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

        evictionHeap.push(HeapRecord(
            recordedAt: entry.recordedAt,
            table: .pubkey,
            key: pubkey,
            relay: normalizedRelay,
            source: source
        ))

        evictIfNeeded()
    }

    /// Record a relay hint for an event ID
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

        evictionHeap.push(HeapRecord(
            recordedAt: entry.recordedAt,
            table: .eventId,
            key: eventId,
            relay: normalizedRelay,
            source: source
        ))

        evictIfNeeded()
    }

    /// Record a relay hint for an addressable event (kind:pubkey:d-tag)
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

        evictionHeap.push(HeapRecord(
            recordedAt: entry.recordedAt,
            table: .address,
            key: address,
            relay: normalizedRelay,
            source: source
        ))

        evictIfNeeded()
    }

    /// Record hints when an event is observed from a relay
    /// Records both pubkey and eventId hints with .eventObserved source
    public func recordEventObservation(pubkey: String, eventId: String, relay: RelayURL) {
        recordHint(pubkey: pubkey, relay: relay, source: .eventObserved)
        recordHint(eventId: eventId, relay: relay, source: .eventObserved)
    }

    // MARK: - Retrieving Hints

    /// Get all hints for a pubkey
    public func hints(for pubkey: String) -> [HintEntry] {
        return pubkeyHints[pubkey] ?? []
    }

    /// Get all hints for an event ID
    public func hints(forEventId eventId: String) -> [HintEntry] {
        return eventIdHints[eventId] ?? []
    }

    /// Get all hints for an address
    public func hints(forAddress address: String) -> [HintEntry] {
        return addressHints[address] ?? []
    }

    /// Get unique relay URLs for a pubkey
    public func relayURLs(for pubkey: String) -> Set<RelayURL> {
        return Set(hints(for: pubkey).map { $0.relay })
    }

    /// Get unique relay URLs for an event ID
    public func relayURLs(forEventId eventId: String) -> Set<RelayURL> {
        return Set(hints(forEventId: eventId).map { $0.relay })
    }

    /// Get unique relay URLs for an address
    public func relayURLs(forAddress address: String) -> Set<RelayURL> {
        return Set(hints(forAddress: address).map { $0.relay })
    }

    // MARK: - Statistics

    /// Total number of hint entries
    public var count: Int {
        return totalEntries
    }

    /// Number of unique pubkeys with hints
    public var pubkeyCount: Int {
        return pubkeyHints.count
    }

    /// Number of unique event IDs with hints
    public var eventIdCount: Int {
        return eventIdHints.count
    }

    /// Number of unique addresses with hints
    public var addressCount: Int {
        return addressHints.count
    }

    // MARK: - Introspection

    /// Get all pubkey hints (for debugging/diagnostics)
    public var allPubkeyHints: [String: [HintEntry]] {
        return pubkeyHints
    }

    /// Get all event ID hints (for debugging/diagnostics)
    public var allEventIdHints: [String: [HintEntry]] {
        return eventIdHints
    }

    /// Get all address hints (for debugging/diagnostics)
    public var allAddressHints: [String: [HintEntry]] {
        return addressHints
    }

    /// Get relays ranked by how often they appear in hints
    public func mostKnownRelays(limit: Int) -> [RelayMention] {
        var relayCounts: [RelayURL: Int] = [:]

        // Count pubkey hints
        for hints in pubkeyHints.values {
            for hint in hints {
                relayCounts[hint.relay, default: 0] += 1
            }
        }

        // Count event ID hints
        for hints in eventIdHints.values {
            for hint in hints {
                relayCounts[hint.relay, default: 0] += 1
            }
        }

        // Count address hints
        for hints in addressHints.values {
            for hint in hints {
                relayCounts[hint.relay, default: 0] += 1
            }
        }

        // Sort by count descending and take top N
        let sorted = relayCounts.sorted { $0.value > $1.value }
        return Array(sorted.prefix(limit)).map { RelayMention(relay: $0.key, mentionCount: $0.value) }
    }

    /// Comprehensive statistics about the hint index
    public var statistics: HintIndexStatistics {
        var uniqueRelays = Set<RelayURL>()

        for hints in pubkeyHints.values {
            for hint in hints {
                uniqueRelays.insert(hint.relay)
            }
        }
        for hints in eventIdHints.values {
            for hint in hints {
                uniqueRelays.insert(hint.relay)
            }
        }
        for hints in addressHints.values {
            for hint in hints {
                uniqueRelays.insert(hint.relay)
            }
        }

        return HintIndexStatistics(
            pubkeyCount: pubkeyHints.count,
            eventIdCount: eventIdHints.count,
            addressCount: addressHints.count,
            totalEntries: totalEntries,
            uniqueRelayCount: uniqueRelays.count
        )
    }

    /// Breakdown of hints by source
    public var sourceBreakdown: [HintSource: Int] {
        var breakdown: [HintSource: Int] = [:]

        for hints in pubkeyHints.values {
            for hint in hints {
                breakdown[hint.source, default: 0] += 1
            }
        }
        for hints in eventIdHints.values {
            for hint in hints {
                breakdown[hint.source, default: 0] += 1
            }
        }
        for hints in addressHints.values {
            for hint in hints {
                breakdown[hint.source, default: 0] += 1
            }
        }

        return breakdown
    }

    // MARK: - Management

    /// Clear all hints
    public func clear() {
        pubkeyHints.removeAll()
        eventIdHints.removeAll()
        addressHints.removeAll()
        evictionHeap.removeAll()
        totalEntries = 0
    }

    // MARK: - Private — Heap-based eviction

    /// Which storage table a heap record points at.
    private enum HeapTable {
        case pubkey
        case eventId
        case address
    }

    /// One record in the eviction heap. Identifies a hint entry by
    /// `(table, key, relay, source)`. Because `recordHint` dedups on `(relay, source)`
    /// within each `(table, key)` slot, this tuple uniquely identifies an entry.
    /// Records are ordered by `recordedAt` (ascending → oldest first).
    private struct HeapRecord: Comparable {
        let recordedAt: Date
        let table: HeapTable
        let key: String
        let relay: RelayURL
        let source: HintSource

        static func < (lhs: HeapRecord, rhs: HeapRecord) -> Bool {
            return lhs.recordedAt < rhs.recordedAt
        }

        static func == (lhs: HeapRecord, rhs: HeapRecord) -> Bool {
            return lhs.recordedAt == rhs.recordedAt
        }
    }

    /// Evict oldest entries until `totalEntries <= maxSize`.
    ///
    /// Complexity: amortized O(log N) per insertion. Each `recordHint` performs
    /// one heap push (O(log N)) and (when over cap) at most one heap pop (O(log N))
    /// plus a removal from the per-key array (O(K) where K is the small per-key fanout).
    /// If a popped heap record no longer has a matching entry in its per-key array
    /// (defensive: should not happen with the current append-only dedup contract),
    /// the pop is treated as a no-op and we continue popping.
    private func evictIfNeeded() {
        while totalEntries > maxSize, let oldest = evictionHeap.pop() {
            // Locate the per-key array, then remove the matching (relay, source).
            switch oldest.table {
            case .pubkey:
                if removeMatchingEntry(in: &pubkeyHints, key: oldest.key, relay: oldest.relay, source: oldest.source) {
                    totalEntries -= 1
                }
            case .eventId:
                if removeMatchingEntry(in: &eventIdHints, key: oldest.key, relay: oldest.relay, source: oldest.source) {
                    totalEntries -= 1
                }
            case .address:
                if removeMatchingEntry(in: &addressHints, key: oldest.key, relay: oldest.relay, source: oldest.source) {
                    totalEntries -= 1
                }
            }
        }
    }

    /// Remove the first entry in `storage[key]` matching `(relay, source)`.
    /// Returns `true` if an entry was removed; `false` if no such entry existed.
    /// Drops the key entirely if its array becomes empty.
    @discardableResult
    private func removeMatchingEntry(
        in storage: inout [String: [HintEntry]],
        key: String,
        relay: RelayURL,
        source: HintSource
    ) -> Bool {
        guard var hints = storage[key] else { return false }
        guard let idx = hints.firstIndex(where: { $0.relay == relay && $0.source == source }) else {
            return false
        }
        hints.remove(at: idx)
        if hints.isEmpty {
            storage.removeValue(forKey: key)
        } else {
            storage[key] = hints
        }
        return true
    }
}

// MARK: - MinHeap

/// A simple array-backed binary min-heap.
///
/// - `push` is O(log N).
/// - `pop` is O(log N).
/// - `removeAll` is O(N).
///
/// Internal; not exposed as public API.
struct MinHeap<Element: Comparable> {
    private var storage: [Element] = []

    var count: Int { storage.count }
    var isEmpty: Bool { storage.isEmpty }
    var peek: Element? { storage.first }

    mutating func push(_ element: Element) {
        storage.append(element)
        siftUp(from: storage.count - 1)
    }

    mutating func pop() -> Element? {
        guard let first = storage.first else { return nil }
        if storage.count == 1 {
            storage.removeLast()
            return first
        }
        storage[0] = storage.removeLast()
        siftDown(from: 0)
        return first
    }

    mutating func removeAll() {
        storage.removeAll(keepingCapacity: false)
    }

    private mutating func siftUp(from index: Int) {
        var child = index
        while child > 0 {
            let parent = (child - 1) / 2
            if storage[child] < storage[parent] {
                storage.swapAt(child, parent)
                child = parent
            } else {
                return
            }
        }
    }

    private mutating func siftDown(from index: Int) {
        var parent = index
        let n = storage.count
        while true {
            let left = 2 * parent + 1
            let right = 2 * parent + 2
            var smallest = parent
            if left < n, storage[left] < storage[smallest] {
                smallest = left
            }
            if right < n, storage[right] < storage[smallest] {
                smallest = right
            }
            if smallest == parent { return }
            storage.swapAt(parent, smallest)
            parent = smallest
        }
    }
}
