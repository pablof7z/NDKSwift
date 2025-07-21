import Foundation

/// Tracks relay information for users to implement the outbox model
actor NDKOutboxTracker {
    /// Default TTL for cached relay information (2 minutes)
    static let defaultTTL: TimeInterval = 120

    /// Default cache capacity
    static let defaultCapacity = 1000

    private let ndk: NDK
    private let cache: LRUCache<String, NDKOutboxItem>
    private let blacklistedRelays: Set<String>

    /// Track pending fetches to avoid duplicate requests
    private var pendingFetches: [String: Task<NDKOutboxItem?, Error>] = [:]

    init(
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
    func getRelaysFor(
        pubkey: String,
        type: RelayListType = .both
    ) async throws -> NDKOutboxItem? {
        print("🔍 [OutboxTracker] getRelaysFor called for pubkey: \(pubkey)")
        
        // Check cache first
        if let cached = await cache.get(pubkey) {
            print("🔍 [OutboxTracker] Found cached relay info for pubkey: \(pubkey)")
            return filterByType(cached, type: type)
        }

        print("🔍 [OutboxTracker] No cache found, checking pending fetches...")
        
        // Check if there's already a pending fetch
        if let pendingTask = pendingFetches[pubkey] {
            print("🔍 [OutboxTracker] Found pending fetch for pubkey: \(pubkey), waiting...")
            let result = try await pendingTask.value
            print("🔍 [OutboxTracker] Pending fetch completed for pubkey: \(pubkey)")
            return result.flatMap { filterByType($0, type: type) }
        }

        print("🔍 [OutboxTracker] Creating new fetch task for pubkey: \(pubkey)")
        
        // Create new fetch task
        let fetchTask = Task<NDKOutboxItem?, Error> {
            defer {
                print("🔍 [OutboxTracker] Removing pending fetch for pubkey: \(pubkey)")
                pendingFetches.removeValue(forKey: pubkey)
            }

            print("🔍 [OutboxTracker] Starting fetchRelayList for pubkey: \(pubkey)")
            let item = try await fetchRelayList(for: pubkey)
            
            if let item = item {
                print("🔍 [OutboxTracker] fetchRelayList succeeded, caching result for pubkey: \(pubkey)")
                await cache.set(pubkey, value: item)
            } else {
                print("🔍 [OutboxTracker] fetchRelayList returned nil for pubkey: \(pubkey)")
            }
            return item
        }

        pendingFetches[pubkey] = fetchTask
        print("🔍 [OutboxTracker] Waiting for fetch task to complete...")
        let result = try await fetchTask.value
        print("🔍 [OutboxTracker] Fetch task completed for pubkey: \(pubkey)")
        return result.flatMap { filterByType($0, type: type) }
    }

    /// Get relay information synchronously from cache only
    func getRelaysSyncFor(
        pubkey: String,
        type: RelayListType = .both
    ) async -> NDKOutboxItem? {
        guard let cached = await cache.get(pubkey) else { return nil }
        return filterByType(cached, type: type)
    }

    /// Track a user's relay information
    func track(
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
    func updateRelayMetadata(
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
    func clear() async {
        await cache.clear()
        pendingFetches.removeAll()
    }

    /// Clean up expired entries
    func cleanupExpired() async {
        await cache.cleanupExpired()
    }

    // MARK: - Private Methods

    private func fetchRelayList(for pubkey: String) async throws -> NDKOutboxItem? {
        print("🔍 [OutboxTracker] fetchRelayList: Trying NIP-65 (kind 10002) for pubkey: \(pubkey)")
        
        // First try NIP-65 (kind 10002)
        if let nip65Item = try await fetchNIP65RelayList(for: pubkey) {
            print("🔍 [OutboxTracker] fetchRelayList: Found NIP-65 relay list for pubkey: \(pubkey)")
            return nip65Item
        }

        print("🔍 [OutboxTracker] fetchRelayList: No NIP-65 list found, trying contact list (kind 3) for pubkey: \(pubkey)")
        
        // Fallback to contact list (kind 3)
        return try await fetchContactListRelays(for: pubkey)
    }

    private func fetchNIP65RelayList(for pubkey: String) async throws -> NDKOutboxItem? {
        print("🔍 [OutboxTracker] fetchNIP65RelayList: Starting for pubkey: \(pubkey)")
        
        var filter = NDKFilter()
        filter.authors = [pubkey]
        filter.kinds = [NDKRelayList.kind]

        print("🔍 [OutboxTracker] fetchNIP65RelayList: Creating subscription with filter - authors: \(filter.authors ?? []), kinds: \(filter.kinds ?? [])")
        
        // Use a direct subscription to avoid recursive outbox calls
        let subscriptionId = "outbox_fetch_\(UUID().uuidString)"
        print("🔍 [OutboxTracker] fetchNIP65RelayList: Creating subscription ID: \(subscriptionId)")
        
        // IMPORTANT: We must specify relays here to prevent outbox recursion
        // Use all currently connected relays
        let currentRelays = await ndk.pool.connectedRelays().map { $0.url }
        print("🔍 [OutboxTracker] fetchNIP65RelayList: Using \(currentRelays.count) connected relays to avoid outbox recursion")
        
        let subscription = await ndk.internalSubscriptionManager.createSubscription(
            id: subscriptionId,
            filters: [filter],
            relays: Set(currentRelays) // Use all connected relays to prevent recursion
        )
        
        print("🔍 [OutboxTracker] fetchNIP65RelayList: Subscription created")
        
        var latestEvent: NDKEvent?
        var didReceiveEvent = false
        
        // Set up EOSE handler
        print("🔍 [OutboxTracker] fetchNIP65RelayList: Setting up EOSE handler")
        await subscription.onEOSE {
            print("🔍 [OutboxTracker] fetchNIP65RelayList: EOSE received")
            didReceiveEvent = true
        }
        
        // Listen for events with a timeout
        print("🔍 [OutboxTracker] fetchNIP65RelayList: Starting event listener task")
        let eventTask = Task {
            for await (event, _) in await subscription.events {
                print("🔍 [OutboxTracker] fetchNIP65RelayList: Event received! ID: \(event.id)")
                latestEvent = event
                didReceiveEvent = true
                break // We only need the first event
            }
        }
        
        // Wait for event or timeout
        print("🔍 [OutboxTracker] fetchNIP65RelayList: Starting timeout task (2 seconds)")
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 second timeout
            print("🔍 [OutboxTracker] fetchNIP65RelayList: Timeout reached")
            didReceiveEvent = true
        }
        
        // Wait until we receive an event or timeout
        print("🔍 [OutboxTracker] fetchNIP65RelayList: Waiting for event or timeout...")
        while !didReceiveEvent {
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }
        
        print("🔍 [OutboxTracker] fetchNIP65RelayList: Done waiting, cancelling tasks")
        
        // Cancel tasks
        eventTask.cancel()
        timeoutTask.cancel()
        
        // Close the subscription
        print("🔍 [OutboxTracker] fetchNIP65RelayList: Closing subscription")
        await ndk.internalSubscriptionManager.closeSubscription(id: subscriptionId)
        
        guard let event = latestEvent else {
            return nil
        }

        let relayList = NDKRelayList.fromEvent(event)

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
        var filter = NDKFilter()
        filter.authors = [pubkey]
        filter.kinds = [EventKind.contacts]

        // Use a direct subscription to avoid recursive outbox calls
        let subscriptionId = "outbox_fetch_contacts_\(UUID().uuidString)"
        // IMPORTANT: We must specify relays here to prevent outbox recursion
        // Use all currently connected relays
        let currentRelays = await ndk.pool.connectedRelays().map { $0.url }
        print("🔍 [OutboxTracker] fetchNIP65RelayList: Using \(currentRelays.count) connected relays to avoid outbox recursion")
        
        let subscription = await ndk.internalSubscriptionManager.createSubscription(
            id: subscriptionId,
            filters: [filter],
            relays: Set(currentRelays) // Use all connected relays to prevent recursion
        )
        
        var latestEvent: NDKEvent?
        var didReceiveEvent = false
        
        // Set up EOSE handler
        await subscription.onEOSE {
            didReceiveEvent = true
        }
        
        // Listen for events with a timeout
        let eventTask = Task {
            for await (event, _) in await subscription.events {
                latestEvent = event
                didReceiveEvent = true
                break // We only need the first event
            }
        }
        
        // Wait for event or timeout
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 second timeout
            didReceiveEvent = true
        }
        
        // Wait until we receive an event or timeout
        while !didReceiveEvent {
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }
        
        // Cancel tasks
        eventTask.cancel()
        timeoutTask.cancel()
        
        // Close the subscription
        await ndk.internalSubscriptionManager.closeSubscription(id: subscriptionId)
        
        guard let event = latestEvent else {
            return nil
        }

        let contactList = NDKContactList.fromEvent(event)

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
enum RelayListType {
    case read
    case write
    case both
}
