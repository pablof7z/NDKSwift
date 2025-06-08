import Foundation

/// The primary cache interface for NDKSwift
public actor NDKCache {
    private let eventCache: LayeredCache
    private let profileCache: LayeredCache
    private let metadataCache: LayeredCache
    
    // Cache key prefixes
    private enum Prefix {
        static let event = "event:"
        static let profile = "profile:"
        static let nip05 = "nip05:"
        static let relay = "relay:"
        static let eventsByAuthor = "events:author:"
        static let eventsByKind = "events:kind:"
        static let eventsByTag = "events:tag:"
    }
    
    public init(
        cacheDirectory: URL? = nil,
        memoryEventLimit: Int = 10000,
        memoryProfileLimit: Int = 1000
    ) async throws {
        let cacheDir: URL
        if let provided = cacheDirectory {
            cacheDir = provided
        } else {
            cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
                .appendingPathComponent("NDKSwift")
                .appendingPathComponent("cache")
        }
        
        // Create cache directories
        let eventDir = cacheDir.appendingPathComponent("events")
        let profileDir = cacheDir.appendingPathComponent("profiles")
        let metadataDir = cacheDir.appendingPathComponent("metadata")
        
        // Initialize layered caches
        self.eventCache = try await CacheFactory.createStandardCache(
            diskURL: eventDir,
            memorySize: memoryEventLimit,
            diskSize: 100_000_000, // 100MB
            defaultTTL: nil // Events don't expire
        )
        
        self.profileCache = try await CacheFactory.createStandardCache(
            diskURL: profileDir,
            memorySize: memoryProfileLimit,
            diskSize: 50_000_000, // 50MB
            defaultTTL: 3600 // 1 hour
        )
        
        self.metadataCache = try await CacheFactory.createStandardCache(
            diskURL: metadataDir,
            memorySize: 500,
            diskSize: 10_000_000, // 10MB
            defaultTTL: 86400 // 24 hours
        )
    }
    
    // MARK: - Event Operations
    
    /// Save an event to cache
    public func saveEvent(_ event: NDKEvent) async throws {
        guard let id = event.id else { return }
        
        let key = Prefix.event + id
        try await eventCache.set(key, value: event)
        
        // Update indexes
        await updateEventIndexes(event)
    }
    
    /// Retrieve an event by ID
    public func getEvent(_ id: EventID) async -> NDKEvent? {
        let key = Prefix.event + id
        return await eventCache.get(key, type: NDKEvent.self)
    }
    
    /// Query events matching a filter
    public func queryEvents(_ filter: NDKFilter) async -> [NDKEvent] {
        // If filter has specific IDs, fetch those directly
        if let ids = filter.ids, !ids.isEmpty {
            var events: [NDKEvent] = []
            for id in ids {
                if let event = await getEvent(id) {
                    events.append(event)
                }
            }
            return events.filter { filter.matches(event: $0) }
        }
        
        // Use indexes for author-based queries
        if let authors = filter.authors, !authors.isEmpty {
            var events: [NDKEvent] = []
            for author in authors {
                let authorEvents = await getEventsByAuthor(author)
                events.append(contentsOf: authorEvents)
            }
            return events.filter { filter.matches(event: $0) }
        }
        
        // For other queries, we'd need more sophisticated indexing
        // This is a limitation of simple key-value caching
        return []
    }
    
    /// Remove all events from cache
    public func clearEvents() async {
        await eventCache.clear()
    }
    
    // MARK: - Profile Operations
    
    /// Save a user profile
    public func saveProfile(_ profile: NDKUserProfile, for pubkey: PublicKey) async throws {
        let key = Prefix.profile + pubkey
        try await profileCache.set(key, value: profile)
    }
    
    /// Retrieve a user profile
    public func getProfile(for pubkey: PublicKey) async -> NDKUserProfile? {
        let key = Prefix.profile + pubkey
        return await profileCache.get(key, type: NDKUserProfile.self)
    }
    
    // MARK: - NIP-05 Operations
    
    /// Save NIP-05 verification data
    public func saveNip05(_ pubkey: PublicKey, relays: [String], for nip05: String) async throws {
        struct NIP05Data: Codable {
            let pubkey: String
            let relays: [String]
            let verifiedAt: Date
        }
        
        let key = Prefix.nip05 + nip05.lowercased()
        let data = NIP05Data(pubkey: pubkey, relays: relays, verifiedAt: Date())
        try await metadataCache.set(key, value: data)
    }
    
    /// Retrieve NIP-05 verification data
    public func getNip05(for nip05: String) async -> (pubkey: PublicKey, relays: [String])? {
        struct NIP05Data: Codable {
            let pubkey: String
            let relays: [String]
            let verifiedAt: Date
        }
        
        let key = Prefix.nip05 + nip05.lowercased()
        guard let data = await metadataCache.get(key, type: NIP05Data.self) else {
            return nil
        }
        return (pubkey: data.pubkey, relays: data.relays)
    }
    
    // MARK: - Relay Status Operations
    
    /// Update relay connection status
    public func updateRelayStatus(_ url: RelayURL, status: NDKRelayConnectionState) async throws {
        let key = Prefix.relay + url
        try await metadataCache.set(key, value: status, ttl: 300) // 5 minutes
    }
    
    /// Get relay connection status
    public func getRelayStatus(_ url: RelayURL) async -> NDKRelayConnectionState? {
        let key = Prefix.relay + url
        return await metadataCache.get(key, type: NDKRelayConnectionState.self)
    }
    
    // MARK: - Statistics
    
    /// Get cache statistics for all layers
    public func statistics() async -> CacheStatistics {
        let eventStats = await eventCache.statistics()
        let profileStats = await profileCache.statistics()
        let metadataStats = await metadataCache.statistics()
        
        // Combine statistics
        return eventStats.map { stats in
            CacheStatistics(
                hits: stats.hits + (profileStats.first?.hits ?? 0) + (metadataStats.first?.hits ?? 0),
                misses: stats.misses + (profileStats.first?.misses ?? 0) + (metadataStats.first?.misses ?? 0),
                evictions: stats.evictions + (profileStats.first?.evictions ?? 0) + (metadataStats.first?.evictions ?? 0),
                currentSize: stats.currentSize + (profileStats.first?.currentSize ?? 0) + (metadataStats.first?.currentSize ?? 0),
                maxSize: nil
            )
        }.first ?? CacheStatistics(hits: 0, misses: 0, evictions: 0, currentSize: 0, maxSize: nil)
    }
    
    // MARK: - Private Methods
    
    private func updateEventIndexes(_ event: NDKEvent) async {
        // Update author index
        let authorKey = Prefix.eventsByAuthor + event.pubkey
        var authorEvents = await eventCache.get(authorKey, type: [EventID].self) ?? []
        if let eventId = event.id, !authorEvents.contains(eventId) {
            authorEvents.append(eventId)
            try? await eventCache.set(authorKey, value: authorEvents)
        }
        
        // Update kind index
        let kindKey = Prefix.eventsByKind + String(event.kind)
        var kindEvents = await eventCache.get(kindKey, type: [EventID].self) ?? []
        if let eventId = event.id, !kindEvents.contains(eventId) {
            kindEvents.append(eventId)
            try? await eventCache.set(kindKey, value: kindEvents)
        }
        
        // Update tag indexes for common tag types
        for tag in event.tags {
            guard tag.count >= 2 else { continue }
            let tagKey = Prefix.eventsByTag + "\(tag[0]):\(tag[1])"
            var tagEvents = await eventCache.get(tagKey, type: [EventID].self) ?? []
            if let eventId = event.id, !tagEvents.contains(eventId) {
                tagEvents.append(eventId)
                try? await eventCache.set(tagKey, value: tagEvents)
            }
        }
    }
    
    private func getEventsByAuthor(_ pubkey: PublicKey) async -> [NDKEvent] {
        let key = Prefix.eventsByAuthor + pubkey
        guard let eventIds = await eventCache.get(key, type: [EventID].self) else {
            return []
        }
        
        var events: [NDKEvent] = []
        for id in eventIds {
            if let event = await getEvent(id) {
                events.append(event)
            }
        }
        return events
    }
}

// MARK: - Cache-Only Operations

extension NDKCache {
    /// Perform a cache-only query (no relay fallback)
    public func queryCacheOnly(_ filter: NDKFilter) async -> [NDKEvent] {
        return await queryEvents(filter)
    }
    
    /// Check if an event exists in cache
    public func hasEvent(_ id: EventID) async -> Bool {
        let key = Prefix.event + id
        return await eventCache.contains(key)
    }
    
    /// Batch save events
    public func saveEvents(_ events: [NDKEvent]) async throws {
        for event in events {
            try await saveEvent(event)
        }
    }
}