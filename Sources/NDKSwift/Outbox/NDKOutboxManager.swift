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
    private let lookupTracker: RelayListLookupTracker
    private let updateNotifier: RelayUpdateNotifier

    init(ndk: NDK) {
        self.ndk = ndk
        self.tracker = NDKOutboxTracker(ndk: ndk)
        self.ranker = NDKRelayRanker(ndk: ndk, tracker: tracker)
        self.selector = NDKRelaySelector(ndk: ndk, tracker: tracker, ranker: ranker)
        self.publishingStrategy = NDKPublishingStrategy(ndk: ndk, selector: selector, tracker: tracker)
        self.fetchingStrategy = NDKFetchingStrategy(ndk: ndk, selector: selector)
        self.lookupTracker = RelayListLookupTracker()
        self.updateNotifier = RelayUpdateNotifier(ndk: ndk)
    }

    // MARK: - Public API

    /// Stream of relay update events for monitoring
    public var relayUpdates: AsyncStream<RelayUpdateEvent> {
        get async {
            await updateNotifier.relayUpdates
        }
    }

    /// Register a subscription for relay updates
    public func registerSubscriptionForUpdates(
        id: String,
        filter: NDKFilter,
        unknownAuthors: Set<String>
    ) async {
        await updateNotifier.registerSubscription(
            id: id,
            filter: filter,
            unknownAuthors: unknownAuthors
        )
    }

    /// Unregister a subscription from relay updates
    public func unregisterSubscriptionFromUpdates(id: String) async {
        await updateNotifier.unregisterSubscription(id: id)
    }

    /// Get relay update statistics
    public func getRelayUpdateStats() async -> RelayUpdateStats {
        await updateNotifier.getStats()
    }

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

    /// Get all tracked outbox items from cache
    /// - Returns: Array of all cached outbox items
    public func getAllTrackedItems() async -> [NDKOutboxItem] {
        return await tracker.getAllCachedItems()
    }

    /// Get outbox strategy for a filter, breaking it down by relay with proper author mapping
    /// - Parameter filter: The filter to analyze
    /// - Returns: Strategy with filters broken down by relay
    public func getOutboxStrategy(for filter: NDKFilter) async -> OutboxFilterStrategy {
        guard let authors = filter.authors, !authors.isEmpty else {
            NDKLogger.log(.debug, category: .outbox, "📡 No authors in filter, no outbox strategy needed")
            return OutboxFilterStrategy(
                filtersByRelay: [:],
                unknownAuthors: [],
                authorsToDiscover: []
            )
        }

        NDKLogger.log(.info, category: .outbox, "📡 Building outbox strategy for \(authors.count) authors")

        var filtersByRelay: [RelayURL: NDKFilter] = [:]
        var unknownAuthors = Set<String>()
        var authorsToDiscover = Set<String>()

        // Group authors by their relays
        var relayToAuthors: [RelayURL: Set<String>] = [:]

        for author in authors {
            // Get cached relay info synchronously (non-blocking)
            if let item = await tracker.getRelaysSyncFor(pubkey: author, type: .read) {
                // Author has known read relays - prefer these for fetching
                let readRelays = item.readRelays.map { $0.url }

                if !readRelays.isEmpty {
                    NDKLogger.log(.trace, category: .outbox, "✅ Found \(readRelays.count) read relays for \(author.prefix(8))")
                    for relay in readRelays {
                        relayToAuthors[relay, default: []].insert(author)
                    }
                } else if !item.writeRelays.isEmpty {
                    // Fall back to write relays if no read relays
                    NDKLogger.log(.trace, category: .outbox, "📝 Using \(item.writeRelays.count) write relays for \(author.prefix(8)) (no read relays)")
                    for relayInfo in item.writeRelays {
                        relayToAuthors[relayInfo.url, default: []].insert(author)
                    }
                } else {
                    // Has relay info but no relays - still unknown
                    unknownAuthors.insert(author)
                }
            } else {
                // No relay info cached
                unknownAuthors.insert(author)

                // Check if we should look them up
                if await lookupTracker.shouldLookup(author) {
                    authorsToDiscover.insert(author)
                    await lookupTracker.markLookedUp(author)
                }
            }
        }

        NDKLogger.log(.info, category: .outbox, "📊 Relay mapping: \(unknownAuthors.count) unknown authors, \(authorsToDiscover.count) to discover")

        // Add unknown authors to app's default relays
        if !unknownAuthors.isEmpty {
            let defaultRelays = await ndk.pool.connectedRelayURLs
            NDKLogger.log(.debug, category: .outbox, "🔄 Adding \(unknownAuthors.count) unknown authors to \(defaultRelays.count) default relays")
            for relay in defaultRelays {
                relayToAuthors[relay, default: []].formUnion(unknownAuthors)
            }
        }

        // Create relay-specific filters
        for (relay, relayAuthors) in relayToAuthors {
            var relayFilter = filter
            relayFilter.authors = Array(relayAuthors)
            filtersByRelay[relay] = relayFilter
        }

        NDKLogger.log(.info, category: .outbox, "✅ Created \(filtersByRelay.count) relay-specific filters")

        return OutboxFilterStrategy(
            filtersByRelay: filtersByRelay,
            unknownAuthors: unknownAuthors,
            authorsToDiscover: authorsToDiscover
        )
    }

    /// Discover relay lists in background (non-blocking)
    /// - Parameter authors: Authors to discover relay lists for
    public func discoverRelaysInBackground(for authors: Set<String>) {
        guard !authors.isEmpty else { return }

        NDKLogger.log(.info, category: .outbox, "🔍 Starting background relay discovery for \(authors.count) authors")

        Task {
            // Create filter for relay lists
            let relayListFilter = NDKFilter(
                authors: Array(authors),
                kinds: [EventKind.relayList],
                limit: authors.count
            )

            // Query ONLY designated outbox relays for relay lists
            let outboxRelays: Set<RelayURL>
            if !ndk.outboxConfig.outboxRelays.isEmpty {
                outboxRelays = ndk.outboxConfig.outboxRelays
            } else {
                outboxRelays = await ndk.pool.connectedRelayURLs
            }

            NDKLogger.log(.debug, category: .outbox, "📡 Querying \(outboxRelays.count) outbox relays for relay lists")

            // Create data source for relay list discovery
            let dataSource = NDKDataSource(
                ndk: ndk,
                filter: relayListFilter,
                relays: outboxRelays,
                subscriptionId: "relay_discovery_\(authors.prefix(3).joined())_\(authors.count)"
            )

            // Process relay lists as they arrive
            for await event in dataSource.events {
                await processRelayListEvent(event)
            }

            NDKLogger.log(.info, category: .outbox, "✅ Relay discovery completed for \(authors.count) authors")
        }
    }

    /// Process a relay list event and update tracking
    internal func processRelayListEvent(_ event: NDKEvent) async {
        guard event.kind == EventKind.relayList else { return }

        NDKLogger.log(.debug, category: .outbox, "📋 Processing relay list for \(event.pubkey.prefix(StringConstants.DisplayFormatting.hexPrefixLength))")

        // Parse relay list from event
        var readRelays = Set<RelayInfo>()
        var writeRelays = Set<RelayInfo>()

        for tag in event.tags {
            guard tag.count >= 2, tag[0] == "r" else { continue }
            let url = tag[1]
            let isWrite = tag.count < 3 || tag[2].isEmpty || tag[2] == "write"
            let isRead = tag.count < 3 || tag[2].isEmpty || tag[2] == "read"

            let relayInfo = RelayInfo(url: url)
            if isRead {
                readRelays.insert(relayInfo)
            }
            if isWrite {
                writeRelays.insert(relayInfo)
            }
        }

        // Update tracker
        await tracker.track(
            pubkey: event.pubkey,
            readRelays: Set(readRelays.map { $0.url }),
            writeRelays: Set(writeRelays.map { $0.url }),
            source: .nip65
        )

        NDKLogger.log(.info, category: .outbox, "✅ Updated relay info for \(event.pubkey.prefix(StringConstants.DisplayFormatting.hexPrefixLength)): \(readRelays.count) read, \(writeRelays.count) write")

        // Notify about relay discovery
        let discoveryInfo = RelayDiscoveryInfo(
            readRelays: Set(readRelays.map { $0.url }),
            writeRelays: Set(writeRelays.map { $0.url })
        )
        await updateNotifier.notifyRelayDiscovery(for: event.pubkey, relays: discoveryInfo)
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
