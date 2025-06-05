import Foundation

/// Tracks relay information for users to implement the outbox model
public actor NDKOutboxTracker {
    /// Default TTL for cached relay information (2 minutes)
    public static let defaultTTL: TimeInterval = 120

    /// Default cache capacity
    public static let defaultCapacity = 1000

    private let ndk: NDK
    private let cache: LRUCache<String, NDKOutboxItem>
    private let blacklistedRelays: Set<String>

    /// Track pending fetches to avoid duplicate requests
    private var pendingFetches: [String: Task<NDKOutboxItem?, Error>] = [:]

    public init(
        ndk: NDK,
        capacity: Int = defaultCapacity,
        ttl: TimeInterval = defaultTTL,
        blacklistedRelays: Set<String> = []
    ) {
        self.ndk = ndk
        self.cache = LRUCache(capacity: capacity, defaultTTL: ttl)
        self.blacklistedRelays = blacklistedRelays
    }

    /// Get relay information for a user
    public func getRelaysFor(
        pubkey: String,
        type: RelayListType = .both
    ) async throws -> NDKOutboxItem? {
        // Check cache first
        if let cached = await cache.get(pubkey) {
            return filterByType(cached, type: type)
        }

        // Check if there's already a pending fetch
        if let pendingTask = pendingFetches[pubkey] {
            let result = try await pendingTask.value
            return result.flatMap { filterByType($0, type: type) }
        }

        // Create new fetch task
        let fetchTask = Task<NDKOutboxItem?, Error> {
            defer { pendingFetches.removeValue(forKey: pubkey) }

            let item = try await fetchRelayList(for: pubkey)
            if let item = item {
                await cache.set(pubkey, value: item)
            }
            return item
        }

        pendingFetches[pubkey] = fetchTask
        let result = try await fetchTask.value
        return result.flatMap { filterByType($0, type: type) }
    }

    /// Get relay information synchronously from cache only
    public func getRelaysSyncFor(
        pubkey: String,
        type: RelayListType = .both
    ) async -> NDKOutboxItem? {
        guard let cached = await cache.get(pubkey) else { return nil }
        return filterByType(cached, type: type)
    }

    /// Track a user's relay information
    public func track(
        pubkey: String,
        readRelays: Set<String> = [],
        writeRelays: Set<String> = [],
        source: RelayListSource = .manual
    ) async {
        let readRelayInfos = readRelays
            .subtracting(blacklistedRelays)
            .map { RelayInfo(url: $0) }

        let writeRelayInfos = writeRelays
            .subtracting(blacklistedRelays)
            .map { RelayInfo(url: $0) }

        let item = NDKOutboxItem(
            pubkey: pubkey,
            readRelays: Set(readRelayInfos),
            writeRelays: Set(writeRelayInfos),
            source: source
        )

        await cache.set(pubkey, value: item)
    }

    /// Update relay metadata (e.g., health scores)
    public func updateRelayMetadata(
        url: String,
        metadata: RelayMetadata
    ) async {
        // Get all items that contain this relay
        let allItems = await cache.allItems()

        for (pubkey, item) in allItems {
            var updated = false

            let updatedReadRelays = item.readRelays.map { relay -> RelayInfo in
                if relay.url == url {
                    updated = true
                    return RelayInfo(url: url, metadata: metadata)
                }
                return relay
            }

            let updatedWriteRelays = item.writeRelays.map { relay -> RelayInfo in
                if relay.url == url {
                    updated = true
                    return RelayInfo(url: url, metadata: metadata)
                }
                return relay
            }

            if updated {
                let updatedItem = NDKOutboxItem(
                    pubkey: item.pubkey,
                    readRelays: Set(updatedReadRelays),
                    writeRelays: Set(updatedWriteRelays),
                    fetchedAt: item.fetchedAt,
                    source: item.source
                )
                await cache.set(pubkey, value: updatedItem)
            }
        }
    }

    /// Clear the cache
    public func clear() async {
        await cache.clear()
        pendingFetches.removeAll()
    }

    /// Clean up expired entries
    public func cleanupExpired() async {
        await cache.cleanupExpired()
    }

    // MARK: - Private Methods

    private func fetchRelayList(for pubkey: String) async throws -> NDKOutboxItem? {
        // First try NIP-65 (kind 10002)
        if let nip65Item = try await fetchNIP65RelayList(for: pubkey) {
            return nip65Item
        }

        // Fallback to contact list (kind 3)
        return try await fetchContactListRelays(for: pubkey)
    }

    private func fetchNIP65RelayList(for pubkey: String) async throws -> NDKOutboxItem? {
        let filter = NDKFilter(
            authors: [pubkey],
            kinds: [NDKRelayList.kind]
        )

        let eventSet = try await ndk.fetchEvents(filters: [filter])
        let events = Array(eventSet).sorted { $0.createdAt > $1.createdAt }

        guard let latestEvent = events.first else {
            return nil
        }

        let relayList = NDKRelayList.fromEvent(latestEvent)

        let readRelayUrls = Set(relayList.readRelays.map { $0.url })
        let readRelays = readRelayUrls
            .subtracting(blacklistedRelays)
            .map { RelayInfo(url: $0) }

        let writeRelayUrls = Set(relayList.writeRelays.map { $0.url })
        let writeRelays = writeRelayUrls
            .subtracting(blacklistedRelays)
            .map { RelayInfo(url: $0) }

        // Find relays that support both read and write
        let bothRelayUrls = readRelayUrls.intersection(writeRelayUrls)
        let bothRelays = bothRelayUrls
            .subtracting(blacklistedRelays)
            .map { RelayInfo(url: $0) }

        return NDKOutboxItem(
            pubkey: pubkey,
            readRelays: Set(readRelays).union(Set(bothRelays)),
            writeRelays: Set(writeRelays).union(Set(bothRelays)),
            source: .nip65
        )
    }

    private func fetchContactListRelays(for pubkey: String) async throws -> NDKOutboxItem? {
        let filter = NDKFilter(
            authors: [pubkey],
            kinds: [EventKind.contacts]
        )

        let eventSet = try await ndk.fetchEvents(filters: [filter])
        let events = Array(eventSet).sorted { $0.createdAt > $1.createdAt }

        guard let latestEvent = events.first else {
            return nil
        }

        let contactList = NDKContactList.fromEvent(latestEvent)

        // Extract relay URLs from contact entries
        let relayUrls = Set(contactList.contacts.compactMap { $0.relayURL })
        let relays = relayUrls
            .subtracting(blacklistedRelays)
            .map { RelayInfo(url: $0) }

        // For contact lists, use same relays for both read and write
        return NDKOutboxItem(
            pubkey: pubkey,
            readRelays: Set(relays),
            writeRelays: Set(relays),
            source: .contactList
        )
    }

    private func filterByType(_ item: NDKOutboxItem, type: RelayListType) -> NDKOutboxItem {
        switch type {
        case .read:
            return NDKOutboxItem(
                pubkey: item.pubkey,
                readRelays: item.readRelays,
                writeRelays: [],
                fetchedAt: item.fetchedAt,
                source: item.source
            )
        case .write:
            return NDKOutboxItem(
                pubkey: item.pubkey,
                readRelays: [],
                writeRelays: item.writeRelays,
                fetchedAt: item.fetchedAt,
                source: item.source
            )
        case .both:
            return item
        }
    }
}

/// Type of relay list to fetch
public enum RelayListType {
    case read
    case write
    case both
}
