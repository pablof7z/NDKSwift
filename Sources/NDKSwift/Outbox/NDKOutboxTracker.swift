import Foundation

/// Event emitted when relay information is discovered for a user
public struct RelayDiscoveryEvent: Sendable {
    public let pubkey: String
    public let readRelays: Set<RelayURL>
    public let writeRelays: Set<RelayURL>
    public let source: RelayListSource
    public let timestamp: Date
    
    public init(
        pubkey: String,
        readRelays: Set<RelayURL>,
        writeRelays: Set<RelayURL>,
        source: RelayListSource,
        timestamp: Date = Date()
    ) {
        self.pubkey = pubkey
        self.readRelays = readRelays
        self.writeRelays = writeRelays
        self.source = source
        self.timestamp = timestamp
    }
}

/// Tracks relay information for users to implement the outbox model
public actor NDKOutboxTracker {
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
    
    /// Stream of relay discoveries
    public let relayDiscoveries: AsyncStream<RelayDiscoveryEvent>
    private let relayDiscoveryContinuation: AsyncStream<RelayDiscoveryEvent>.Continuation

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
        
        // Initialize AsyncStream for relay discoveries
        var continuation: AsyncStream<RelayDiscoveryEvent>.Continuation!
        self.relayDiscoveries = AsyncStream { cont in
            continuation = cont
        }
        self.relayDiscoveryContinuation = continuation
    }

    /// Get relay information for a user.
    ///
    /// Retrieves relay preferences for a given user's public key, implementing the
    /// NIP-65 outbox model. This method checks multiple cache layers before fetching
    /// from the network if necessary.
    ///
    /// - Parameters:
    ///   - pubkey: The hex-encoded public key of the user
    ///   - maxAge: Maximum age of cached data to consider valid (default: 1 hour)
    ///   - type: Type of relays to retrieve (.read, .write, or .both)
    ///
    /// - Returns: An `NDKOutboxItem` containing the user's relay preferences, or nil if not found
    ///
    /// - Throws: `NDKError` if the network request fails
    ///
    /// - Note: This method implements caching with both positive and negative cache entries.
    ///   Negative cache entries prevent repeated lookups for users without relay lists.
    ///
    /// Example:
    /// ```swift
    /// let relays = try await tracker.getRelaysFor(
    ///     pubkey: userPubkey,
    ///     maxAge: TimeConstants.hour,
    ///     type: .read
    /// )
    /// ```
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
    public func getRelaysSyncFor(
        pubkey: String,
        type: RelayListType = .both
    ) async -> NDKOutboxItem? {
        guard let cached = await memoryCache.get(pubkey),
              let item = cached.item else { return nil }
        return filterByType(item, type: type)
    }

    /// Get all cached outbox items
    /// - Returns: Array of all valid cached items (excludes negative cache entries)
    func getAllCachedItems() async -> [NDKOutboxItem] {
        var items: [NDKOutboxItem] = []

        // Get all items from memory cache
        let allKeys = await memoryCache.getAllKeys()
        for key in allKeys {
            if let cached = await memoryCache.get(key),
               let item = cached.item,
               Date() <= cached.expiresAt {
                items.append(item)
            }
        }

        return items
    }

    /// Track a user's relay information.
    ///
    /// Stores relay preferences for a user in the cache and optionally emits a
    /// discovery event for other components to react to relay information updates.
    ///
    /// - Parameters:
    ///   - pubkey: The hex-encoded public key of the user
    ///   - readRelays: Set of relay URLs the user reads from
    ///   - writeRelays: Set of relay URLs the user writes to
    ///   - source: Source of the relay information (e.g., .nip65, .manual, .blastr)
    ///   - emitDiscoveryEvent: Whether to emit a `RelayDiscoveryEvent` (default: true)
    ///
    /// - Note: Blacklisted relays are automatically filtered out before storage.
    ///
    /// Example:
    /// ```swift
    /// await tracker.track(
    ///     pubkey: userPubkey,
    ///     readRelays: ["wss://relay1.com", "wss://relay2.com"],
    ///     writeRelays: ["wss://relay3.com"],
    ///     source: .nip65
    /// )
    /// ```
    func track(
        pubkey: String,
        readRelays: Set<String> = [],
        writeRelays: Set<String> = [],
        source: RelayListSource = .manual,
        emitDiscoveryEvent: Bool = true
    ) async {
        // Filter out blacklisted relays
        let filteredReadRelays = readRelays.subtracting(blacklistedRelays)
        let filteredWriteRelays = writeRelays.subtracting(blacklistedRelays)
        
        let readRelayInfos = filteredReadRelays
            .map { RelayInfo(url: $0) }

        let writeRelayInfos = filteredWriteRelays
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
        
        // Emit discovery event only if requested
        if emitDiscoveryEvent {
            let discoveryEvent = RelayDiscoveryEvent(
                pubkey: pubkey,
                readRelays: filteredReadRelays,
                writeRelays: filteredWriteRelays,
                source: source
            )
            relayDiscoveryContinuation.yield(discoveryEvent)
            
            NDKLogger.log(.debug, category: .outbox, "📡 Emitted relay discovery for \(pubkey.prefix(8)): \(filteredReadRelays.count) read, \(filteredWriteRelays.count) write relays")
        }
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

        NDKLogger.log(.info, category: .outbox, "🔍 Fetching relay list (10002) for \(pubkey.prefix(8))...")
        
        let filter = NDKFilter(
            authors: [pubkey],
            kinds: [EventKind.relayList]
        )

        // Determine which relays to use for fetching relay lists
        let relaysToUse: Set<String>
        
        // Check if outbox relays are connected
        let connectedRelays = await ndk.pool.connectedRelayURLs
        let connectedOutboxRelays = ndk.outboxConfig.outboxRelays.intersection(connectedRelays)
        
        if !connectedOutboxRelays.isEmpty {
            // Use connected outbox relays
            relaysToUse = connectedOutboxRelays
            NDKLogger.log(.debug, category: .outbox, "📡 Using \(connectedOutboxRelays.count) connected outbox relays for relay list fetch: \(connectedOutboxRelays.sorted())")
        } else if !connectedRelays.isEmpty {
            // Fall back to any connected relays
            relaysToUse = connectedRelays
            NDKLogger.log(.warning, category: .outbox, "⚠️ No outbox relays connected, falling back to \(connectedRelays.count) explicit relays: \(connectedRelays.sorted())")
        } else {
            // No relays connected at all
            NDKLogger.log(.error, category: .outbox, "❌ No relays connected for relay list fetch")
            return (nil, Set())
        }

        // Use determined relays
        let dataSource = ndk.observe(
            filter: filter,
            maxAge: 0,
            cachePolicy: .networkOnly,
            relays: relaysToUse
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
            NDKLogger.log(.info, category: .outbox, "📭 No relay list (10002) found for \(pubkey.prefix(8))... from \(eoseRelays.count) relays: \(eoseRelays.sorted())")
            return (nil, eoseRelays)
        }

        NDKLogger.log(.info, category: .outbox, "📬 Found relay list (10002) for \(pubkey.prefix(8))... created at: \(Date(timeIntervalSince1970: TimeInterval(event.createdAt)))")
        
        // Debug log the actual event tags
        NDKLogger.log(.debug, category: .outbox, "📋 Event tags: \(event.tags)")

        let relayList = NDKRelayList.fromEvent(event)
        
        NDKLogger.log(.debug, category: .outbox, "📝 Raw relay list data - Read: \(relayList.readRelays.map { $0.url }), Write: \(relayList.writeRelays.map { $0.url })")

        let readRelayUrls = Set(relayList.readRelays.map { $0.url })
            .subtracting(blacklistedRelays)
        let writeRelayUrls = Set(relayList.writeRelays.map { $0.url })
            .subtracting(blacklistedRelays)

        let readRelayInfos = readRelayUrls.map { RelayInfo(url: $0) }
        let writeRelayInfos = writeRelayUrls.map { RelayInfo(url: $0) }

        if !blacklistedRelays.isEmpty && (relayList.readRelays.count != readRelayUrls.count || relayList.writeRelays.count != writeRelayUrls.count) {
            NDKLogger.log(.debug, category: .outbox, "🚫 Filtered blacklisted relays - Final Read: \(readRelayUrls), Write: \(writeRelayUrls)")
        }

        let item = NDKOutboxItem(
            pubkey: pubkey,
            readRelays: Set(readRelayInfos),
            writeRelays: Set(writeRelayInfos),
            source: .nip65
        )
        
        NDKLogger.log(.info, category: .outbox, "✅ Processed relay list for \(pubkey.prefix(8))... - \(readRelayUrls.count) read relays, \(writeRelayUrls.count) write relays")

        return (item, eoseRelays)
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
