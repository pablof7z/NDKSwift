import Foundation

/// Tracks relay information for users to implement the outbox model
actor NDKOutboxTracker {
    /// Default TTL for positive cache entries (24 hours)
    static let positiveEntryTTL: TimeInterval = TimeConstants.day
    
    /// Default TTL for negative cache entries (1 hour)
    static let negativeEntryTTL: TimeInterval = TimeConstants.hour

    /// Default in-memory cache capacity
    static let defaultCapacity = NetworkConstants.outboxTrackerCapacity

    private let ndk: NDK
    private let memoryCache: LRUCache<String, CachedRelayPreference>
    private let blacklistedRelays: Set<String>

    /// Track pending fetches to avoid duplicate requests
    private var pendingFetches: [String: Task<NDKOutboxItem?, Error>] = [:]
    
    /// Cached relay preference with metadata
    private struct CachedRelayPreference {
        let item: NDKOutboxItem?  // nil = negative cache
        let fetchedAt: Date
        let expiresAt: Date
        let checkedRelays: Set<String>?  // For negative entries only
    }

    init(
        ndk: NDK,
        capacity: Int = defaultCapacity,
        blacklistedRelays: Set<String> = []
    ) {
        self.ndk = ndk
        self.memoryCache = LRUCache(capacity: capacity, defaultTTL: Self.positiveEntryTTL)
        self.blacklistedRelays = blacklistedRelays
    }

    /// Get relay information for a user
    func getRelaysFor(
        pubkey: String,
        maxAge: TimeInterval = TimeConstants.hour,
        type: RelayListType = .both
    ) async throws -> NDKOutboxItem? {
        // 1. Check memory cache first
        if let cached = await checkMemoryCache(pubkey: pubkey, maxAge: maxAge) {
            NDKLogger.log(.debug, category: .outbox, "🔍 Memory cache hit for pubkey: \(pubkey)")
            if let item = cached.item {
                return filterByType(item, type: type)
            } else {
                // Negative cache hit
                return nil
            }
        }
        
        // 2. Check database cache
        if let cached = await checkDatabaseCache(pubkey: pubkey, maxAge: maxAge) {
            NDKLogger.log(.debug, category: .outbox, "🔍 Database cache hit for pubkey: \(pubkey)")
            if let item = cached.item {
                return filterByType(item, type: type)
            } else {
                // Negative cache hit
                return nil
            }
        }

        // 3. Check if there's already a pending fetch
        if let pendingTask = pendingFetches[pubkey] {
            let result = try await pendingTask.value
            return result.flatMap { filterByType($0, type: type) }
        }
        
        // 4. Create new fetch task
        let fetchTask = Task<NDKOutboxItem?, Error> {
            defer {
                pendingFetches.removeValue(forKey: pubkey)
            }

            let (item, eoseRelays) = try await fetchRelayListFromNetwork(for: pubkey)
            
            // Cache the result
            await cacheResult(pubkey: pubkey, item: item, eoseRelays: eoseRelays)
            
            return item
        }

        pendingFetches[pubkey] = fetchTask
        let result = try await fetchTask.value
        return result.flatMap { filterByType($0, type: type) }
    }

    /// Get relay information synchronously from cache only
    func getRelaysSyncFor(
        pubkey: String,
        type: RelayListType = .both
    ) async -> NDKOutboxItem? {
        guard let cached = await memoryCache.get(pubkey),
              let item = cached.item else { return nil }
        return filterByType(item, type: type)
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

        await memoryCache.set(pubkey, value: CachedRelayPreference(
            item: item,
            fetchedAt: Date(),
            expiresAt: Date().addingTimeInterval(Self.positiveEntryTTL),
            checkedRelays: nil
        ))
    }

    /// Update relay metadata (e.g., health scores)
    func updateRelayMetadata(
        url: String,
        metadata: RelayMetadata
    ) async {
        // Get all items that contain this relay
        let allItems = await memoryCache.allItems()

        for (pubkey, cached) in allItems {
            guard let item = cached.item else { continue }
            
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
                await memoryCache.set(pubkey, value: CachedRelayPreference(
                    item: updatedItem,
                    fetchedAt: cached.fetchedAt,
                    expiresAt: cached.expiresAt,
                    checkedRelays: cached.checkedRelays
                ))
            }
        }
    }

    /// Clear the cache
    func clear() async {
        await memoryCache.clear()
        pendingFetches.removeAll()
    }

    /// Clean up expired entries
    func cleanupExpired() async {
        await memoryCache.cleanupExpired()
    }

    // MARK: - Private Methods
    
    private func checkMemoryCache(pubkey: String, maxAge: TimeInterval) async -> CachedRelayPreference? {
        guard let cached = await memoryCache.get(pubkey) else { return nil }
        
        // Check maxAge
        let age = Date().timeIntervalSince(cached.fetchedAt)
        if age > maxAge {
            return nil
        }
        
        // Check expiration
        if Date() > cached.expiresAt {
            return nil
        }
        
        // For negative cache, check if we'd query the same relays
        if cached.item == nil, let checkedRelays = cached.checkedRelays {
            let currentOutboxRelays = ndk.outboxConfig.outboxRelays
            if !currentOutboxRelays.isSubset(of: checkedRelays) {
                // Some new outbox relays to check
                return nil
            }
        }
        
        return cached
    }
    
    private func checkDatabaseCache(pubkey: String, maxAge: TimeInterval) async -> CachedRelayPreference? {
        guard let dbResult = await ndk.cache.getRelayPreferences(pubkey: pubkey) else {
            return nil
        }
        
        // Check maxAge
        let age = Date().timeIntervalSince(dbResult.fetchedAt)
        if age > maxAge {
            return nil
        }
        
        // Check expiration
        if Date() > dbResult.expiresAt {
            return nil
        }
        
        // For negative cache, check if we'd query the same relays
        let hasRelayList = dbResult.writeRelays != nil || dbResult.readRelays != nil
        if !hasRelayList, let checkedRelays = dbResult.checkedRelays {
            let currentOutboxRelays = ndk.outboxConfig.outboxRelays
            if !currentOutboxRelays.isSubset(of: checkedRelays) {
                // Some new outbox relays to check
                return nil
            }
        }
        
        // Convert to NDKOutboxItem
        let item: NDKOutboxItem?
        if let writeRelays = dbResult.writeRelays, let readRelays = dbResult.readRelays {
            let writeRelayInfos = writeRelays
                .filter { !blacklistedRelays.contains($0) }
                .map { RelayInfo(url: $0) }
            let readRelayInfos = readRelays
                .filter { !blacklistedRelays.contains($0) }
                .map { RelayInfo(url: $0) }
            
            item = NDKOutboxItem(
                pubkey: pubkey,
                readRelays: Set(readRelayInfos),
                writeRelays: Set(writeRelayInfos),
                fetchedAt: dbResult.fetchedAt,
                source: .nip65
            )
        } else {
            item = nil
        }
        
        let cached = CachedRelayPreference(
            item: item,
            fetchedAt: dbResult.fetchedAt,
            expiresAt: dbResult.expiresAt,
            checkedRelays: dbResult.checkedRelays
        )
        
        // Update memory cache
        await memoryCache.set(pubkey, value: cached)
        
        return cached
    }
    
    private func cacheResult(pubkey: String, item: NDKOutboxItem?, eoseRelays: Set<String>) async {
        let now = Date()
        let ttl = item != nil ? Self.positiveEntryTTL : Self.negativeEntryTTL
        let expiresAt = now.addingTimeInterval(ttl)
        
        let cached = CachedRelayPreference(
            item: item,
            fetchedAt: now,
            expiresAt: expiresAt,
            checkedRelays: item == nil ? eoseRelays : nil
        )
        
        // Update memory cache
        await memoryCache.set(pubkey, value: cached)
        
        // Save to database
        let writeRelays = item?.writeRelays.map { $0.url }
        let readRelays = item?.readRelays.map { $0.url }
        
        try? await ndk.cache.saveRelayPreferences(
            pubkey: pubkey,
            writeRelays: writeRelays,
            readRelays: readRelays,
            fetchedAt: now,
            expiresAt: expiresAt,
            checkedRelays: item == nil ? eoseRelays : nil
        )
    }

    private func fetchRelayListFromNetwork(for pubkey: String) async throws -> (item: NDKOutboxItem?, eoseRelays: Set<String>) {
        var eoseRelays = Set<String>()
        var relayListEvent: NDKEvent?
        
        let filter = NDKFilter(
            authors: [pubkey],
            kinds: [10002],
            limit: 1
        )
        
        // Use configured outbox relays
        let dataSource = ndk.observe(
            filter: filter,
            maxAge: 0,
            cachePolicy: .networkOnly,
            relays: ndk.outboxConfig.outboxRelays
        )
        
        // Process both events and relay updates with timeout
        await withTaskGroup(of: Void.self) { group in
            // Task 1: Collect events
            group.addTask {
                for await event in dataSource.events {
                    if relayListEvent == nil || event.createdAt > relayListEvent!.createdAt {
                        relayListEvent = event
                    }
                }
            }
            
            // Task 2: Track EOSE
            group.addTask {
                for await update in dataSource.relayUpdates {
                    if case .eose(let relay) = update {
                        eoseRelays.insert(relay)
                    }
                }
            }
            
            // Task 3: Timeout after 2 seconds
            group.addTask {
                try? await Task.sleep(nanoseconds: 2 * TimeConstants.nanosecondsPerSecond)
            }
            
            // Wait for the first task to complete (timeout or data)
            await group.next()
            
            // Cancel remaining tasks
            group.cancelAll()
        }
        
        // Parse relay list if found
        guard let event = relayListEvent else {
            return (nil, eoseRelays)
        }
        
        let relayList = NDKRelayList.fromEvent(event)
        
        let readRelayUrls = Set(relayList.readRelays.map { $0.url })
            .subtracting(blacklistedRelays)
        let writeRelayUrls = Set(relayList.writeRelays.map { $0.url })
            .subtracting(blacklistedRelays)
        
        let readRelayInfos = readRelayUrls.map { RelayInfo(url: $0) }
        let writeRelayInfos = writeRelayUrls.map { RelayInfo(url: $0) }
        
        let item = NDKOutboxItem(
            pubkey: pubkey,
            readRelays: Set(readRelayInfos),
            writeRelays: Set(writeRelayInfos),
            source: .nip65
        )
        
        return (item, eoseRelays)
    }
    
    private func fetchRelayList(for pubkey: String) async throws -> NDKOutboxItem? {
        // First try NIP-65 (kind 10002)
        if let nip65Item = try await fetchNIP65RelayList(for: pubkey) {
            return nip65Item
        }

        // Fallback to contact list (kind 3)
        return try await fetchContactListRelays(for: pubkey)
    }

    private func fetchNIP65RelayList(for pubkey: String) async throws -> NDKOutboxItem? {
        var filter = NDKFilter()
        filter.authors = [pubkey]
        filter.kinds = [NDKRelayList.kind]

        // Use a direct subscription to avoid recursive outbox calls
        let subscriptionId = "outbox_fetch_\(UUID().uuidString)"
        
        // IMPORTANT: We must specify relays here to prevent outbox recursion
        // Use all currently connected relays
        let currentRelays = await ndk.pool.connectedRelays().map { $0.url }
        
        let subscription = await ndk.internalSubscriptionManager.createSubscription(
            id: subscriptionId,
            filters: [filter],
            relays: Set(currentRelays) // Use all connected relays to prevent recursion
        )
        
        
        var latestEvent: NDKEvent?
        var didReceiveEvent = false
        
        // Set up EOSE handler
        await subscription.onEOSE { _ in
            didReceiveEvent = true
        }
        
        // Listen for events with a timeout
        let eventTask = Task {
            for await (event, _) in await subscription.events {
                NDKLogger.log(.debug, category: .outbox, "🔍 fetchNIP65RelayList: Event received! ID: \(event.id)")
                latestEvent = event
                didReceiveEvent = true
                break // We only need the first event
            }
        }
        
        // Wait for event or timeout
        NDKLogger.log(.trace, category: .outbox, "🔍 fetchNIP65RelayList: Starting timeout task (2 seconds)")
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: 2 * TimeConstants.nanosecondsPerSecond) // 2 second timeout
            NDKLogger.log(.debug, category: .outbox, "🔍 fetchNIP65RelayList: Timeout reached")
            didReceiveEvent = true
        }
        
        // Wait until we receive an event or timeout
        NDKLogger.log(.trace, category: .outbox, "🔍 fetchNIP65RelayList: Waiting for event or timeout...")
        while !didReceiveEvent {
            try? await Task.sleep(nanoseconds: 100 * TimeConstants.nanosecondsPerMillisecond) // 100ms
        }
        
        NDKLogger.log(.trace, category: .outbox, "🔍 fetchNIP65RelayList: Done waiting, cancelling tasks")
        
        // Cancel tasks
        eventTask.cancel()
        timeoutTask.cancel()
        
        // Close the subscription
        NDKLogger.log(.trace, category: .outbox, "🔍 fetchNIP65RelayList: Closing subscription")
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
        NDKLogger.log(.debug, category: .outbox, "🔍 fetchNIP65RelayList: Using \(currentRelays.count) connected relays to avoid outbox recursion")
        
        let subscription = await ndk.internalSubscriptionManager.createSubscription(
            id: subscriptionId,
            filters: [filter],
            relays: Set(currentRelays) // Use all connected relays to prevent recursion
        )
        
        var latestEvent: NDKEvent?
        var didReceiveEvent = false
        
        // Set up EOSE handler
        await subscription.onEOSE { _ in
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
            try await Task.sleep(nanoseconds: 2 * TimeConstants.nanosecondsPerSecond) // 2 second timeout
            didReceiveEvent = true
        }
        
        // Wait until we receive an event or timeout
        while !didReceiveEvent {
            try? await Task.sleep(nanoseconds: 100 * TimeConstants.nanosecondsPerMillisecond) // 100ms
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
