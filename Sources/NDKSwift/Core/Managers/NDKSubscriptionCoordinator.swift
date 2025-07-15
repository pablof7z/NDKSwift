import Foundation

/// Manages subscriptions and event fetching
public actor NDKSubscriptionCoordinator {
    private weak var ndk: NDK?
    private let subscriptionManager: NDKSubscriptionManager
    private let subscriptionTracker: NDKSubscriptionTracker
    private let cache: NDKCache
    
    // Relay list cache to prevent repeated queries
    private var relayListCache: [String: (relays: Set<RelayURL>, timestamp: Date)] = [:]
    private let relayListCacheTTL: TimeInterval = 86400 // 24 hours (1 day)
    
    init(ndk: NDK, subscriptionManager: NDKSubscriptionManager, subscriptionTracker: NDKSubscriptionTracker, cache: NDKCache) {
        self.ndk = ndk
        self.subscriptionManager = subscriptionManager
        self.subscriptionTracker = subscriptionTracker
        self.cache = cache
    }
    
    // MARK: - Subscriptions
    
    /// Subscribe to events matching multiple filters
    public func subscribe(
        filters: [NDKFilter],
        relays: Set<RelayURL>? = nil,
        id: String? = nil,
        closeOnEose: Bool = false
    ) async -> NDKSubscription {
        print("[NDKSubscriptionCoordinator.subscribe] Starting subscription with \(filters.count) filters, closeOnEose: \(closeOnEose)")
        guard let ndk = ndk else {
            print("[NDKSubscriptionCoordinator.subscribe] NDK is nil, returning dummy subscription")
            // Return a dummy subscription if NDK is deallocated
            var options = NDKSubscriptionOptions()
            options.closeOnEose = closeOnEose
            return NDKSubscription(
                id: id ?? UUID().uuidString,
                filters: filters,
                options: options,
                ndk: NDK()
            )
        }
        
        let subscriptionId = id ?? UUID().uuidString
        print("[NDKSubscriptionCoordinator.subscribe] Created subscription ID: \(subscriptionId)")
        
        // Collect all authors from all filters for outbox model
        let allAuthors = filters.compactMap { $0.authors }.flatMap { $0 }
        
        let selectedRelays: Set<RelayURL>
        if let specificRelays = relays {
            print("[NDKSubscriptionCoordinator.subscribe] Using specific relays: \(specificRelays.joined(separator: ", "))")
            selectedRelays = specificRelays
        } else {
            print("[NDKSubscriptionCoordinator.subscribe] No specific relays, determining relay selection")
            // Use outbox model or all relays
            if ndk.outboxEnabled, !allAuthors.isEmpty {
                print("[NDKSubscriptionCoordinator.subscribe] Using outbox model for \(allAuthors.count) authors")
                let outboxRelays = await getOutboxRelays(for: allAuthors)
                selectedRelays = outboxRelays
            } else {
                print("[NDKSubscriptionCoordinator.subscribe] Using all available relays")
                let allRelays = await ndk.pool.relays
                selectedRelays = Set(allRelays.map { $0.url })
            }
        }
        print("[NDKSubscriptionCoordinator.subscribe] Selected \(selectedRelays.count) relays")
        
        var options = NDKSubscriptionOptions()
        options.closeOnEose = closeOnEose
        options.relays = nil // We'll handle relay selection differently
        
        let subscription = NDKSubscription(
            id: subscriptionId,
            filters: filters,
            options: options,
            ndk: ndk
        )
        
        // Add to subscription manager
        print("[NDKSubscriptionCoordinator.subscribe] Adding subscription to manager")
        await subscriptionManager.addSubscription(subscription)
        print("[NDKSubscriptionCoordinator.subscribe] Subscription added to manager")
        
        // Track the subscription
        // Track the subscription for each filter
        print("[NDKSubscriptionCoordinator.subscribe] Tracking subscription for \(filters.count) filters")
        for filter in filters {
            await subscriptionTracker.trackSubscription(subscription, filter: filter, relayUrls: Array(selectedRelays))
        }
        print("[NDKSubscriptionCoordinator.subscribe] Subscription tracking complete")
        
        print("[NDKSubscriptionCoordinator.subscribe] Returning subscription")
        return subscription
    }
    
    /// Fetch events matching multiple filters
    public func fetchEvents(
        _ filters: [NDKFilter],
        relays: Set<RelayURL>? = nil,
        timeoutSeconds: Int = 5
    ) async throws -> [NDKEvent] {
        print("[NDKSubscriptionCoordinator.fetchEvents] Starting with \(filters.count) filters")
        guard ndk != nil else {
            print("[NDKSubscriptionCoordinator.fetchEvents] NDK reference lost")
            throw NDKError.notConfigured("NDK reference lost")
        }
        
        // Check cache first if no specific relays are specified
        if relays == nil && filters.count == 1 {
            print("[NDKSubscriptionCoordinator.fetchEvents] Checking cache for single filter")
            do {
                print("[NDKSubscriptionCoordinator.fetchEvents] Calling cache.queryEvents...")
                let cachedEvents = try await cache.queryEvents(filters[0])
                print("[NDKSubscriptionCoordinator.fetchEvents] cache.queryEvents returned \(cachedEvents.count) events")
                if !cachedEvents.isEmpty {
                    print("[NDKSubscriptionCoordinator] Returning \(cachedEvents.count) events from cache")
                    return cachedEvents
                }
            } catch {
                print("[NDKSubscriptionCoordinator] Cache query failed: \(error)")
            }
        }
        
        // Create subscription with closeOnEose
        print("[NDKSubscriptionCoordinator.fetchEvents] Creating subscription with closeOnEose")
        let subscription = await subscribe(filters: filters, relays: relays, closeOnEose: true)
        print("[NDKSubscriptionCoordinator.fetchEvents] Subscription created: \(subscription.id)")
        
        var events: [NDKEvent] = []
        var hasSeenEose = false
        
        // Set up timeout
        print("[NDKSubscriptionCoordinator.fetchEvents] Setting up timeout for \(timeoutSeconds) seconds")
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: UInt64(timeoutSeconds) * 1_000_000_000)
            if !hasSeenEose {
                print("[NDKSubscriptionCoordinator.fetchEvents] Timeout reached, closing subscription")
                await subscription.close()
            }
        }
        
        // Collect events
        print("[NDKSubscriptionCoordinator.fetchEvents] Starting to collect events")
        do {
            for try await event in subscription {
                print("[NDKSubscriptionCoordinator.fetchEvents] Received event: \(event.id)")
                events.append(event)
            }
            hasSeenEose = true
            print("[NDKSubscriptionCoordinator.fetchEvents] Finished collecting events (EOSE)")
        } catch {
            print("[NDKSubscriptionCoordinator.fetchEvents] Error collecting events: \(error)")
            timeoutTask.cancel()
            throw error
        }
        
        timeoutTask.cancel()
        print("[NDKSubscriptionCoordinator.fetchEvents] Timeout task cancelled")
        
        // Deduplicate by event ID if multiple filters were used
        if filters.count > 1 {
            let uniqueEvents = Array(Dictionary(grouping: events, by: { $0.id }).values.compactMap { $0.first })
            return uniqueEvents
        }
        
        return events
    }
    
    /// Fetch a single event by ID
    public func fetchEvent(
        id: EventID,
        relays: Set<RelayURL>? = nil,
        timeoutSeconds: Int = 5
    ) async throws -> NDKEvent? {
        print("[NDKSubscriptionCoordinator.fetchEvent] Starting for ID: \(id)")
        let filter = NDKFilter(ids: [id])
        print("[NDKSubscriptionCoordinator.fetchEvent] Calling fetchEvents with filter")
        let events = try await fetchEvents([filter], relays: relays, timeoutSeconds: timeoutSeconds)
        print("[NDKSubscriptionCoordinator.fetchEvent] fetchEvents returned \(events.count) events")
        return events.first
    }
    
    /// Fetch a single event matching the filter
    public func fetchEvent(
        _ filter: NDKFilter,
        relays: Set<RelayURL>? = nil,
        timeoutSeconds: Int = 5
    ) async throws -> NDKEvent? {
        print("[NDKSubscriptionCoordinator.fetchEvent] Starting with filter")
        var limitedFilter = filter
        limitedFilter.limit = 1
        print("[NDKSubscriptionCoordinator.fetchEvent] Calling fetchEvents with limited filter")
        let events = try await fetchEvents([limitedFilter], relays: relays, timeoutSeconds: timeoutSeconds)
        print("[NDKSubscriptionCoordinator.fetchEvent] fetchEvents returned \(events.count) events")
        return events.first
    }
    
    /// Fetch user profile
    public func fetchProfile(
        for pubkey: PublicKey,
        relays: Set<RelayURL>? = nil,
        timeoutSeconds: Int = 5
    ) async throws -> NDKUserProfile? {
        let filter = NDKFilter(
            authors: [pubkey],
            kinds: [EventKind.metadata],
            limit: 1
        )
        
        guard let event = try await fetchEvent(filter, relays: relays, timeoutSeconds: timeoutSeconds) else {
            return nil
        }
        
        // Parse profile from event content
        guard let profileData = event.content.data(using: String.Encoding.utf8),
              let profile = try? JSONDecoder().decode(NDKUserProfile.self, from: profileData) else {
            return nil
        }
        
        return profile
    }
    
    // MARK: - Subscription Management
    
    /// Get current subscription statistics
    public func getSubscriptionStats() async -> NDKSubscriptionManager.SubscriptionStats {
        await subscriptionManager.getStats()
    }
    
    // MARK: - Internal Methods
    
    /// Process incoming event from relay
    func processEvent(_ event: NDKEvent, from relay: RelayProtocol) async {
        await subscriptionManager.processEvent(event, from: relay)
        
        // Save to cache
        do {
            try await cache.saveEvent(event)
        } catch {
            print("[NDKSubscriptionCoordinator] Failed to cache event: \(error)")
        }
    }
    
    /// Process EOSE message
    func processEOSE(subscriptionId: String, from relay: RelayProtocol) async {
        await subscriptionManager.processEOSE(subscriptionId: subscriptionId, from: relay)
    }
    
    /// Process COUNT message
    func processCount(subscriptionId: String, count: Int, from relay: RelayProtocol) async {
        await subscriptionManager.processCount(subscriptionId: subscriptionId, count: count, from: relay)
    }
    
    // MARK: - Private Helpers
    
    private func getOutboxRelays(for authors: [String]) async -> Set<RelayURL> {
        guard let ndk = ndk else { return [] }
        
        var outboxRelays = Set<RelayURL>()
        var authorsNeedingFetch: [String] = []
        
        // Check cache first for each author
        for author in authors {
            if let cached = relayListCache[author] {
                let age = Date().timeIntervalSince(cached.timestamp)
                if age < relayListCacheTTL {
                    print("[NDKSubscriptionCoordinator] Using cached relay list for \(author) (age: \(Int(age))s)")
                    outboxRelays.formUnion(cached.relays)
                } else {
                    print("[NDKSubscriptionCoordinator] Cached relay list for \(author) expired (age: \(Int(age))s)")
                    authorsNeedingFetch.append(author)
                }
            } else {
                authorsNeedingFetch.append(author)
            }
        }
        
        // Only fetch for authors not in cache
        if !authorsNeedingFetch.isEmpty {
            print("[NDKSubscriptionCoordinator] Fetching relay lists for \(authorsNeedingFetch.count) authors")
            
            // Fetch relay lists for authors
            let relayListFilter = NDKFilter(
                authors: authorsNeedingFetch,
                kinds: [10002] // Relay list
            )
            
            do {
                // IMPORTANT: Pass empty relay set to prevent recursive outbox model calls
                // This forces fetchEvents to use all available relays instead of triggering outbox model again
                let allRelays = await ndk.pool.relays
                let allRelayUrls = Set(allRelays.map { $0.url })
                let relayListEvents = try await fetchEvents([relayListFilter], relays: allRelayUrls, timeoutSeconds: 3)
                
                // Group events by author
                var relaysByAuthor: [String: Set<RelayURL>] = [:]
                
                for event in relayListEvents {
                    var authorRelays = Set<RelayURL>()
                    for tag in event.tags {
                        if tag.count >= 2 && tag[0] == "r" {
                            let relayUrl = tag[1]
                            if tag.count < 3 || tag[2] == "write" || tag[2].isEmpty {
                                authorRelays.insert(relayUrl)
                            }
                        }
                    }
                    if !authorRelays.isEmpty {
                        relaysByAuthor[event.pubkey] = authorRelays
                        outboxRelays.formUnion(authorRelays)
                    }
                }
                
                // Update cache for authors we found relay lists for
                let now = Date()
                for (author, relays) in relaysByAuthor {
                    relayListCache[author] = (relays: relays, timestamp: now)
                    print("[NDKSubscriptionCoordinator] Cached relay list for \(author) with \(relays.count) relays")
                }
                
                // For authors with no relay list, cache empty set to prevent repeated queries
                for author in authorsNeedingFetch {
                    if relaysByAuthor[author] == nil {
                        relayListCache[author] = (relays: [], timestamp: now)
                        print("[NDKSubscriptionCoordinator] Cached empty relay list for \(author)")
                    }
                }
            } catch {
                print("[NDKSubscriptionCoordinator] Failed to fetch outbox relays: \(error)")
            }
        }
        
        // If no outbox relays found, use all relays
        if outboxRelays.isEmpty {
            let allRelays = await ndk.pool.relays
            outboxRelays = Set(allRelays.map { $0.url })
        }
        
        return outboxRelays
    }
    
    // MARK: - Cache Management
    
    /// Clear the relay list cache
    public func clearRelayListCache() {
        relayListCache.removeAll()
        print("[NDKSubscriptionCoordinator] Cleared relay list cache")
    }
    
    /// Clear relay list cache for specific author
    public func clearRelayListCache(for author: String) {
        relayListCache.removeValue(forKey: author)
        print("[NDKSubscriptionCoordinator] Cleared relay list cache for \(author)")
    }
}