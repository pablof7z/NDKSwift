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
        totalEntries = 0
    }

    // MARK: - Private

    /// Entry type for tracking during eviction
    private enum EntryKeyType {
        case pubkey
        case eventId
        case address
    }

    /// Reference to a specific entry for eviction
    private struct EntryRef {
        let keyType: EntryKeyType
        let key: String
        let entryIndex: Int
        let recordedAt: Date
    }

    private func evictIfNeeded() {
        guard totalEntries > maxSize else { return }

        // True LRU eviction: collect all entries, sort by recordedAt, remove oldest
        // Remove 10% buffer to avoid frequent evictions
        let targetSize = maxSize - (maxSize / 10)
        let evictCount = totalEntries - targetSize

        // Collect all entries with their references
        var allEntries: [EntryRef] = []

        for (key, hints) in pubkeyHints {
            for (index, hint) in hints.enumerated() {
                allEntries.append(EntryRef(keyType: .pubkey, key: key, entryIndex: index, recordedAt: hint.recordedAt))
            }
        }

        for (key, hints) in eventIdHints {
            for (index, hint) in hints.enumerated() {
                allEntries.append(EntryRef(keyType: .eventId, key: key, entryIndex: index, recordedAt: hint.recordedAt))
            }
        }

        for (key, hints) in addressHints {
            for (index, hint) in hints.enumerated() {
                allEntries.append(EntryRef(keyType: .address, key: key, entryIndex: index, recordedAt: hint.recordedAt))
            }
        }

        // Sort by recordedAt (oldest first)
        allEntries.sort { $0.recordedAt < $1.recordedAt }

        // Track which entries to remove (by key and indices)
        var pubkeyIndicesToRemove: [String: Set<Int>] = [:]
        var eventIdIndicesToRemove: [String: Set<Int>] = [:]
        var addressIndicesToRemove: [String: Set<Int>] = [:]

        // Mark oldest entries for removal
        for i in 0 ..< min(evictCount, allEntries.count) {
            let entry = allEntries[i]
            switch entry.keyType {
            case .pubkey:
                pubkeyIndicesToRemove[entry.key, default: []].insert(entry.entryIndex)
            case .eventId:
                eventIdIndicesToRemove[entry.key, default: []].insert(entry.entryIndex)
            case .address:
                addressIndicesToRemove[entry.key, default: []].insert(entry.entryIndex)
            }
        }

        // Remove marked entries (iterate in reverse to preserve indices)
        for (key, indices) in pubkeyIndicesToRemove {
            guard var hints = pubkeyHints[key] else { continue }
            let sortedIndices = indices.sorted(by: >)
            for index in sortedIndices {
                hints.remove(at: index)
                totalEntries -= 1
            }
            if hints.isEmpty {
                pubkeyHints.removeValue(forKey: key)
            } else {
                pubkeyHints[key] = hints
            }
        }

        for (key, indices) in eventIdIndicesToRemove {
            guard var hints = eventIdHints[key] else { continue }
            let sortedIndices = indices.sorted(by: >)
            for index in sortedIndices {
                hints.remove(at: index)
                totalEntries -= 1
            }
            if hints.isEmpty {
                eventIdHints.removeValue(forKey: key)
            } else {
                eventIdHints[key] = hints
            }
        }

        for (key, indices) in addressIndicesToRemove {
            guard var hints = addressHints[key] else { continue }
            let sortedIndices = indices.sorted(by: >)
            for index in sortedIndices {
                hints.remove(at: index)
                totalEntries -= 1
            }
            if hints.isEmpty {
                addressHints.removeValue(forKey: key)
            } else {
                addressHints[key] = hints
            }
        }
    }
}
