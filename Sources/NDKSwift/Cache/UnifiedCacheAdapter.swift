import Foundation

/// Adapter that bridges LayeredCache to NDKCacheAdapter protocol
public final class UnifiedCacheAdapter: NDKCacheAdapter {
    public let locking: Bool = false // Actor-based, no explicit locking needed
    public private(set) var ready: Bool = false
    
    private let eventCache: LayeredCache
    private let profileCache: LayeredCache
    private let nip05Cache: LayeredCache
    private let relayStatusCache: LayeredCache
    
    // Cache key prefixes
    private enum CachePrefix {
        static let event = "event:"
        static let profile = "profile:"
        static let nip05 = "nip05:"
        static let relayStatus = "relay:"
        static let eventsByAuthor = "events:author:"
        static let eventsByKind = "events:kind:"
        static let eventsByTag = "events:tag:"
    }
    
    public init(
        eventCache: LayeredCache? = nil,
        profileCache: LayeredCache? = nil,
        nip05Cache: LayeredCache? = nil,
        relayStatusCache: LayeredCache? = nil
    ) async {
        // Use provided caches or create memory-only defaults
        if let cache = eventCache {
            self.eventCache = cache
        } else {
            self.eventCache = await CacheFactory.createMemoryCache(size: 10000)
        }
        
        if let cache = profileCache {
            self.profileCache = cache
        } else {
            self.profileCache = await CacheFactory.createMemoryCache(size: 1000, defaultTTL: 3600)
        }
        
        if let cache = nip05Cache {
            self.nip05Cache = cache
        } else {
            self.nip05Cache = await CacheFactory.createMemoryCache(size: 500, defaultTTL: 86400)
        }
        
        if let cache = relayStatusCache {
            self.relayStatusCache = cache
        } else {
            self.relayStatusCache = await CacheFactory.createMemoryCache(size: 100, defaultTTL: 300)
        }
        
        await startCache()
    }
    
    // MARK: - NDKCacheAdapter Protocol
    
    public func startCache() async {
        ready = true
    }
    
    public func stopCache() async {
        ready = false
    }
    
    public func saveEvent(_ event: NDKEvent) async throws {
        guard let id = event.id else { return }
        
        // Save the event
        let key = CachePrefix.event + id
        try await eventCache.set(key, value: event)
        
        // Update indexes
        await updateEventIndexes(event)
    }
    
    public func event(by id: String) async -> NDKEvent? {
        let key = CachePrefix.event + id
        return await eventCache.get(key, type: NDKEvent.self)
    }
    
    public func events(filter: NDKFilter) async -> [NDKEvent] {
        // For complex filtering, we still need to load all events
        // In a production system, you'd want more sophisticated indexing
        
        var results: [NDKEvent] = []
        
        // If filter has specific IDs, fetch those directly
        if let ids = filter.ids, !ids.isEmpty {
            for id in ids {
                if let event = await event(by: id) {
                    results.append(event)
                }
            }
            return results
        }
        
        // If filter has authors, use author index
        if let authors = filter.authors, !authors.isEmpty {
            for author in authors {
                let events = await eventsByAuthor(author)
                results.append(contentsOf: events)
            }
        }
        
        // Filter results based on other criteria
        return results.filter { event in
            filter.matches(event: event)
        }
    }
    
    public func setProfile(_ profile: NDKUserProfile, for pubkey: String) async throws {
        let key = CachePrefix.profile + pubkey
        try await profileCache.set(key, value: profile)
    }
    
    public func profile(for pubkey: String) async -> NDKUserProfile? {
        let key = CachePrefix.profile + pubkey
        return await profileCache.get(key, type: NDKUserProfile.self)
    }
    
    // MARK: - NDKCacheAdapter Required Methods
    
    public func query(subscription: NDKSubscription) async -> [NDKEvent] {
        // Query events based on subscription filters
        var results: [NDKEvent] = []
        for filter in subscription.filters {
            let events = await events(filter: filter)
            results.append(contentsOf: events)
        }
        return results
    }
    
    public func setEvent(_ event: NDKEvent, filters: [NDKFilter], relay: NDKRelay?) async {
        // Save event
        try? await saveEvent(event)
    }
    
    public func fetchProfile(pubkey: PublicKey) async -> NDKUserProfile? {
        return await profile(for: pubkey)
    }
    
    public func saveProfile(pubkey: PublicKey, profile: NDKUserProfile) async {
        try? await setProfile(profile, for: pubkey)
    }
    
    public func loadNip05(_ nip05: String) async -> (pubkey: PublicKey, relays: [String])? {
        struct NIP05Data: Codable {
            let pubkey: String
            let relays: [String]
        }
        
        let key = CachePrefix.nip05 + nip05.lowercased()
        if let data = await nip05Cache.get(key, type: NIP05Data.self) {
            return (data.pubkey, data.relays)
        }
        return nil
    }
    
    public func saveNip05(_ nip05: String, pubkey: PublicKey, relays: [String]) async {
        struct NIP05Data: Codable {
            let pubkey: String
            let relays: [String]
        }
        
        let key = CachePrefix.nip05 + nip05.lowercased()
        let data = NIP05Data(pubkey: pubkey, relays: relays)
        try? await nip05Cache.set(key, value: data)
    }
    
    public func updateRelayStatus(_ url: RelayURL, status: NDKRelayConnectionState) async {
        let key = CachePrefix.relayStatus + url
        try? await relayStatusCache.set(key, value: status)
    }
    
    public func getRelayStatus(_ url: RelayURL) async -> NDKRelayConnectionState? {
        let key = CachePrefix.relayStatus + url
        return await relayStatusCache.get(key, type: NDKRelayConnectionState.self)
    }
    
    public func addUnpublishedEvent(_ event: NDKEvent, relayUrls: [RelayURL]) async {
        try? await saveUnpublishedEvent(event, to: Set(relayUrls))
    }
    
    public func getUnpublishedEvents(for relayUrl: RelayURL) async -> [NDKEvent] {
        return await unpublishedEvents(for: relayUrl)
    }
    
    public func removeUnpublishedEvent(_ eventId: EventID, from relayUrl: RelayURL) async {
        try? await markEventAsPublished(eventId, to: relayUrl)
    }
    
    public func removeAllEvents() async throws {
        await eventCache.clear()
    }
    
    // MARK: - Private Helper Methods
    
    private func updateEventIndexes(_ event: NDKEvent) async {
        // Update author index
        let pubkey = event.pubkey
        let key = CachePrefix.eventsByAuthor + pubkey
        var authorEvents = await eventCache.get(key, type: [String].self) ?? []
        if let eventId = event.id, !authorEvents.contains(eventId) {
            authorEvents.append(eventId)
            try? await eventCache.set(key, value: authorEvents)
        }
        
        // Update kind index
        let kindKey = CachePrefix.eventsByKind + String(event.kind)
        var kindEvents = await eventCache.get(kindKey, type: [String].self) ?? []
        if let eventId = event.id, !kindEvents.contains(eventId) {
            kindEvents.append(eventId)
            try? await eventCache.set(kindKey, value: kindEvents)
        }
        
        // Update tag indexes
        for tag in event.tags {
            guard tag.count >= 2 else { continue }
            let tagKey = CachePrefix.eventsByTag + "\(tag[0]):\(tag[1])"
            var tagEvents = await eventCache.get(tagKey, type: [String].self) ?? []
            if let eventId = event.id, !tagEvents.contains(eventId) {
                tagEvents.append(eventId)
                try? await eventCache.set(tagKey, value: tagEvents)
            }
        }
    }
    
    private func eventsByAuthor(_ pubkey: String) async -> [NDKEvent] {
        let key = CachePrefix.eventsByAuthor + pubkey
        guard let eventIds = await eventCache.get(key, type: [String].self) else {
            return []
        }
        
        var events: [NDKEvent] = []
        for id in eventIds {
            if let event = await event(by: id) {
                events.append(event)
            }
        }
        return events
    }
}

/// Extension to create unified cache from existing configuration
extension UnifiedCacheAdapter {
    /// Create a unified cache adapter with standard configuration
    public static func createStandard(
        cacheDirectory: URL? = nil,
        memoryEventSize: Int = 10000,
        memoryProfileSize: Int = 1000
    ) async throws -> UnifiedCacheAdapter {
        let cacheDir: URL
        if let provided = cacheDirectory {
            cacheDir = provided
        } else {
            cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
                .appendingPathComponent("NDKSwift")
                .appendingPathComponent("unified")
        }
        
        // Create cache directories
        let eventDir = cacheDir.appendingPathComponent("events")
        let profileDir = cacheDir.appendingPathComponent("profiles")
        let nip05Dir = cacheDir.appendingPathComponent("nip05")
        let _ = cacheDir.appendingPathComponent("relays")
        
        // Create layered caches
        let eventCache = try await CacheFactory.createStandardCache(
            diskURL: eventDir,
            memorySize: memoryEventSize,
            diskSize: 100_000_000, // 100MB
            defaultTTL: nil // Events don't expire
        )
        
        let profileCache = try await CacheFactory.createStandardCache(
            diskURL: profileDir,
            memorySize: memoryProfileSize,
            diskSize: 50_000_000, // 50MB
            defaultTTL: 3600 // 1 hour
        )
        
        let nip05Cache = try await CacheFactory.createStandardCache(
            diskURL: nip05Dir,
            memorySize: 500,
            diskSize: 10_000_000, // 10MB
            defaultTTL: 86400 // 24 hours
        )
        
        let relayStatusCache = await CacheFactory.createMemoryCache(
            size: 100,
            defaultTTL: 300 // 5 minutes
        )
        
        return await UnifiedCacheAdapter(
            eventCache: eventCache,
            profileCache: profileCache,
            nip05Cache: nip05Cache,
            relayStatusCache: relayStatusCache
        )
    }
}

/// Extension for NDKOutboxCacheAdapter compatibility
extension UnifiedCacheAdapter: NDKOutboxCacheAdapter {
    public func unpublishedEvents() async -> [NDKEvent] {
        // Use a special prefix for unpublished events
        let key = "unpublished:all"
        return await eventCache.get(key, type: [NDKEvent].self) ?? []
    }
    
    public func unpublishedEvents(for relay: String) async -> [NDKEvent] {
        let key = "unpublished:relay:" + relay
        return await eventCache.get(key, type: [NDKEvent].self) ?? []
    }
    
    public func saveUnpublishedEvent(_ event: NDKEvent, to relays: Set<String>) async throws {
        // Save to general unpublished list
        let allKey = "unpublished:all"
        var allEvents = await eventCache.get(allKey, type: [NDKEvent].self) ?? []
        if !allEvents.contains(where: { $0.id == event.id }) {
            allEvents.append(event)
            try await eventCache.set(allKey, value: allEvents)
        }
        
        // Save to relay-specific lists
        for relay in relays {
            let relayKey = "unpublished:relay:" + relay
            var relayEvents = await eventCache.get(relayKey, type: [NDKEvent].self) ?? []
            if !relayEvents.contains(where: { $0.id == event.id }) {
                relayEvents.append(event)
                try await eventCache.set(relayKey, value: relayEvents)
            }
        }
        
        // Also save the event normally
        try await saveEvent(event)
    }
    
    public func markEventAsPublished(_ eventId: String, to relay: String) async throws {
        // Remove from relay-specific unpublished list
        let relayKey = "unpublished:relay:" + relay
        if var relayEvents = await eventCache.get(relayKey, type: [NDKEvent].self) {
            relayEvents.removeAll { $0.id == eventId }
            try await eventCache.set(relayKey, value: relayEvents)
        }
        
        // Check if published to all relays
        let statusKey = "publish:status:" + eventId
        var status = await eventCache.get(statusKey, type: [String: Bool].self) ?? [:]
        status[relay] = true
        try await eventCache.set(statusKey, value: status)
        
        // If published to all relays, remove from general unpublished list
        let pendingRelaysKey = "publish:pending:" + eventId
        if let pendingRelays = await eventCache.get(pendingRelaysKey, type: Set<String>.self) {
            var remaining = pendingRelays
            remaining.remove(relay)
            
            if remaining.isEmpty {
                // Remove from all unpublished list
                let allKey = "unpublished:all"
                if var allEvents = await eventCache.get(allKey, type: [NDKEvent].self) {
                    allEvents.removeAll { $0.id == eventId }
                    try await eventCache.set(allKey, value: allEvents)
                }
            } else {
                try await eventCache.set(pendingRelaysKey, value: remaining)
            }
        }
    }
    
    // MARK: - NDKOutboxCacheAdapter Extended Methods
    
    public func storeUnpublishedEvent(
        _ event: NDKEvent,
        targetRelays: Set<String>,
        publishConfig: OutboxPublishConfig?
    ) async {
        // Store to general unpublished list
        let allKey = "unpublished:all"
        var allRecords = await eventCache.get(allKey, type: [UnpublishedEventRecord].self) ?? []
        
        let storedConfig = publishConfig.map { StoredPublishConfig(from: $0) }
        let record = UnpublishedEventRecord(
            event: event,
            targetRelays: targetRelays,
            publishConfig: storedConfig
        )
        
        if !allRecords.contains(where: { $0.event.id == event.id }) {
            allRecords.append(record)
            try? await eventCache.set(allKey, value: allRecords)
        }
        
        // Store to relay-specific lists
        for relay in targetRelays {
            let relayKey = "unpublished:relay:" + relay
            var relayEvents = await eventCache.get(relayKey, type: [NDKEvent].self) ?? []
            if !relayEvents.contains(where: { $0.id == event.id }) {
                relayEvents.append(event)
                try? await eventCache.set(relayKey, value: relayEvents)
            }
        }
        
        // Also save the event normally
        try? await saveEvent(event)
    }
    
    public func getAllUnpublishedEvents() async -> [UnpublishedEventRecord] {
        let key = "unpublished:all"
        return await eventCache.get(key, type: [UnpublishedEventRecord].self) ?? []
    }
    
    public func updateUnpublishedEventStatus(
        eventId: String,
        relayURL: String,
        status: RelayPublishStatus
    ) async {
        let allKey = "unpublished:all"
        if var records = await eventCache.get(allKey, type: [UnpublishedEventRecord].self),
           let index = records.firstIndex(where: { $0.event.id == eventId }) {
            var record = records[index]
            var statuses = record.relayStatuses
            statuses[relayURL] = status
            
            records[index] = UnpublishedEventRecord(
                event: record.event,
                targetRelays: record.targetRelays,
                relayStatuses: statuses,
                createdAt: record.createdAt,
                lastAttemptAt: Date(),
                publishConfig: record.publishConfig,
                overallStatus: record.overallStatus
            )
            
            try? await eventCache.set(allKey, value: records)
        }
    }
    
    public func markEventAsPublished(eventId: String) async {
        let allKey = "unpublished:all"
        if var records = await eventCache.get(allKey, type: [UnpublishedEventRecord].self) {
            records.removeAll { $0.event.id == eventId }
            try? await eventCache.set(allKey, value: records)
        }
    }
    
    public func getEventsForRetry(olderThan: TimeInterval) async -> [UnpublishedEventRecord] {
        let records = await getAllUnpublishedEvents()
        return records.filter { $0.shouldRetry(after: olderThan) }
    }
    
    public func cleanupPublishedEvents(olderThan: TimeInterval) async {
        // Implementation depends on specific cleanup requirements
    }
    
    public func storeOutboxItem(_ item: NDKOutboxItem) async {
        try? await saveOutboxItem(item)
    }
    
    public func getOutboxItem(for pubkey: String) async -> NDKOutboxItem? {
        let items = await outboxItems()
        return items.first { item in
            // Need to check actual structure of NDKOutboxItem
            // This is a placeholder implementation
            true
        }
    }
    
    public func updateRelayHealth(url: String, health: RelayHealthMetrics) async {
        let key = "health:" + url
        try? await relayStatusCache.set(key, value: health, ttl: 300) // 5 minutes
    }
    
    public func getRelayHealth(url: String) async -> RelayHealthMetrics? {
        let key = "health:" + url
        return await relayStatusCache.get(key, type: RelayHealthMetrics.self)
    }
    
    public func outboxItems() async -> [NDKOutboxItem] {
        let key = "outbox:items"
        return await eventCache.get(key, type: [NDKOutboxItem].self) ?? []
    }
    
    public func saveOutboxItem(_ item: NDKOutboxItem) async throws {
        let key = "outbox:items"
        var items = await eventCache.get(key, type: [NDKOutboxItem].self) ?? []
        
        // NDKOutboxItem doesn't have an id property, so we'll store all items
        items.append(item)
        
        try await eventCache.set(key, value: items)
    }
    
    public func removeOutboxItem(_ itemId: String) async throws {
        // Since NDKOutboxItem doesn't have an id, we can't remove by id
        // This would need to be refactored based on the actual item structure
    }
}