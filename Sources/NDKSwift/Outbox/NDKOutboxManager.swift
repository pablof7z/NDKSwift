import Foundation

/// Public-facing outbox manager that provides a simplified API for outbox operations
/// This facade hides the complexity of internal components like RelayRanker, RelaySelector, etc.
public actor NDKOutboxManager {
    private let ndk: NDK
    private let tracker: NDKOutboxTracker
    private let ranker: NDKRelayRanker
    private let selector: NDKRelaySelector
    private let publishingStrategy: NDKPublishingStrategy
    private let fetchingStrategy: NDKFetchingStrategy
    
    init(ndk: NDK) {
        self.ndk = ndk
        self.tracker = NDKOutboxTracker(ndk: ndk)
        self.ranker = NDKRelayRanker(ndk: ndk, tracker: tracker)
        self.selector = NDKRelaySelector(ndk: ndk, tracker: tracker, ranker: ranker)
        self.publishingStrategy = NDKPublishingStrategy(ndk: ndk, selector: selector, tracker: tracker)
        self.fetchingStrategy = NDKFetchingStrategy(ndk: ndk, selector: selector)
    }
    
    // MARK: - Public API
    
    /// Publish an event using the outbox model
    /// - Parameters:
    ///   - event: The event to publish
    ///   - strategy: Optional custom relay selection strategy
    /// - Returns: Set of relays where the event was successfully published
    public func publish(_ event: NDKEvent, strategy: RelaySelectionStrategy? = nil) async throws -> Set<String> {
        let result = try await publishingStrategy.publish(event, customStrategy: strategy)
        return result.successfulRelayUrls
    }
    
    /// Observe events using the outbox model
    /// - Parameters:
    ///   - filter: The filter to use for observing events
    ///   - maxAge: Maximum age of events in seconds (0 = no cache)
    ///   - cachePolicy: Cache policy to use
    ///   - strategy: Optional custom relay selection strategy
    /// - Returns: NDKDataSource for observing events
    public func observe(
        filter: NDKFilter,
        maxAge: TimeInterval = 0,
        cachePolicy: CachePolicy = .networkOnly,
        strategy: RelaySelectionStrategy? = nil
    ) async -> NDKDataSource<NDKEvent> {
        // Get optimal relays for this filter
        let relays: Set<String>
        if let strategy = strategy {
            relays = Set(await strategy.selectRelays(filter.authors?.first ?? ""))
        } else {
            let selection = await selector.selectRelaysForFetching(
                filter: filter,
                config: FetchingConfig(maxRelayCount: 10)
            )
            relays = selection.relays
        }
        
        // Convert URLs to relay URLs (already normalized)
        let relayUrls = Set(relays)
        
        // Create and return data source
        return NDKDataSource(
            ndk: ndk,
            filter: filter,
            maxAge: maxAge,
            cachePolicy: cachePolicy,
            relays: relayUrls
        )
    }
    
    /// Start tracking a user for outbox operations
    /// - Parameter pubkey: The public key of the user to track
    public func trackUser(_ pubkey: String) async {
        // Fetch user's relay information
        if let item = try? await tracker.getRelaysFor(pubkey: pubkey) {
            await tracker.track(
                pubkey: pubkey,
                readRelays: Set(item.readRelays.map { $0.url }),
                writeRelays: Set(item.writeRelays.map { $0.url }),
                source: item.source
            )
        }
    }
    
    /// Stop tracking a user
    /// - Parameter pubkey: The public key of the user to stop tracking
    public func untrackUser(_ pubkey: String) async {
        // Currently there's no specific untrack method, but fetching will update the cache
        // This is a no-op for now
    }
    
    /// Get the current score for a relay
    /// - Parameters:
    ///   - relay: The relay URL
    ///   - pubkey: The public key to get the score for
    /// - Returns: The relay's score (0.0-1.0)
    public func getRelayScore(relay: String, for pubkey: String) async -> Double {
        return await ranker.getScore(relay: relay, pubkey: pubkey)
    }
    
    /// Get recommended relays for a user
    /// - Parameters:
    ///   - pubkey: The public key to get recommendations for
    ///   - count: Maximum number of relays to return
    /// - Returns: Array of recommended relay URLs
    public func getRecommendedRelays(for pubkey: String, count: Int = 5) async -> [String] {
        return await selector.selectRelays(for: pubkey, count: count)
    }
    
    /// Get recommended relays for a subscription based on filters
    /// Use this to create outbox-aware subscriptions
    /// - Parameters:
    ///   - filters: The filters to analyze for relay selection
    /// - Returns: Set of relay URLs recommended for this subscription
    public func getRecommendedRelaysForSubscription(filters: [NDKFilter]) async -> Set<String> {
        print("🔍 [OutboxManager] getRecommendedRelaysForSubscription called with \(filters.count) filters")
        var allRelays = Set<String>()
        var missingPubkeys = Set<String>()
        
        for (index, filter) in filters.enumerated() {
            print("🔍 [OutboxManager] Processing filter \(index + 1)/\(filters.count)")
            if let authors = filter.authors {
                print("🔍 [OutboxManager] Filter has authors: \(authors.joined(separator: ", "))")
            } else {
                print("🔍 [OutboxManager] Filter has no authors. Filter details: \(filter)")
            }
            let result = await selector.selectRelaysForFetching(
                filter: filter,
                config: FetchingConfig(maxRelayCount: 10)
            )
            print("🔍 [OutboxManager] Filter \(index + 1) returned \(result.relays.count) relays")
            allRelays.formUnion(result.relays)
            missingPubkeys.formUnion(result.missingRelayInfoPubkeys)
        }
        
        print("🔍 [OutboxManager] After initial selection: \(allRelays.count) relays, \(missingPubkeys.count) missing pubkeys")
        
        // If we have missing pubkeys, fetch their relay lists first
        if !missingPubkeys.isEmpty {
            NDKLogger.log(.debug, category: .outbox, "📋 Missing relay info for \(missingPubkeys.count) pubkeys, fetching...")
            print("🔍 [OutboxManager] Missing pubkeys: \(missingPubkeys.joined(separator: ", "))")
            
            // Fetch relay lists for missing pubkeys
            for (index, pubkey) in missingPubkeys.enumerated() {
                print("🔍 [OutboxManager] Fetching relay list for pubkey \(index + 1)/\(missingPubkeys.count): \(pubkey)")
                _ = try? await tracker.getRelaysFor(pubkey: pubkey)
                print("🔍 [OutboxManager] Completed fetch for pubkey \(index + 1)/\(missingPubkeys.count)")
            }
            
            print("🔍 [OutboxManager] All relay lists fetched, re-running selection...")
            
            // Re-run the selection now that we have the relay lists
            allRelays.removeAll()
            for (index, filter) in filters.enumerated() {
                print("🔍 [OutboxManager] Re-processing filter \(index + 1)/\(filters.count)")
                let result = await selector.selectRelaysForFetching(
                    filter: filter,
                    config: FetchingConfig(maxRelayCount: 10)
                )
                print("🔍 [OutboxManager] Re-run filter \(index + 1) returned \(result.relays.count) relays")
                allRelays.formUnion(result.relays)
            }
        }
        
        print("🔍 [OutboxManager] Final result: returning \(allRelays.count) relays")
        print("🔍 [OutboxManager] Relays: \(allRelays.joined(separator: ", "))")
        return allRelays
    }
}

/// Custom relay selection strategy that can be provided by users
public struct RelaySelectionStrategy {
    /// Closure that selects relays for a given public key
    public let selectRelays: (String) async -> [String]
    
    public init(selectRelays: @escaping (String) async -> [String]) {
        self.selectRelays = selectRelays
    }
}
