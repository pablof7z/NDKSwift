import Foundation

/// Represents a relay discovery event
public struct RelayDiscovery: Sendable {
    public let authors: Set<String>
    public let relays: Set<RelayURL>
}

/// Public-facing outbox manager that provides a simplified API for outbox operations.
///
/// `NDKOutboxManager` implements the NIP-65 outbox model for intelligent relay selection,
/// ensuring efficient event publishing and retrieval based on users' relay preferences.
/// This facade hides the complexity of internal components like RelayRanker, RelaySelector, etc.
///
/// ## Overview
/// The outbox model optimizes Nostr network usage by:
/// - Publishing events only to relays where they're likely to be read
/// - Fetching events from relays where authors actually publish
/// - Reducing network overhead and improving performance
///
/// ## Example Usage
/// ```swift
/// // Publish an event using outbox model
/// let publishedRelays = try await ndk.outbox.publish(event)
///
/// // Observe events with intelligent relay selection
/// let dataSource = await ndk.outbox.observe(filter: filter)
/// for await event in dataSource {
///     print("Received event: \(event)")
/// }
/// ```
public actor NDKOutboxManager {
    private let ndk: NDK
    private var tracker: NDKOutboxTracker {
        ndk.outboxTracker
    }
    private var ranker: NDKRelayRanker {
        ndk.relayRanker
    }
    private var selector: NDKRelaySelector {
        ndk.relaySelector
    }
    private var publishingStrategy: NDKPublishingStrategy {
        ndk.publishingStrategy
    }
    private let lookupTracker: RelayListLookupTracker
    
    // Stream for relay discoveries
    private var discoveryStream: AsyncStream<RelayDiscovery>?
    private var discoveryContinuation: AsyncStream<RelayDiscovery>.Continuation?

    init(ndk: NDK) {
        self.ndk = ndk
        self.lookupTracker = RelayListLookupTracker()
        
        // Set up discovery stream
        let (stream, continuation) = AsyncStream<RelayDiscovery>.makeStream()
        self.discoveryStream = stream
        self.discoveryContinuation = continuation
    }

    // MARK: - Public API
    
    /// Stream of relay discoveries as they happen
    public var relayDiscoveries: AsyncStream<RelayDiscovery> {
        discoveryStream ?? AsyncStream { _ in }
    }

    /// Publishes an event using the outbox model for intelligent relay selection.
    ///
    /// This method automatically selects the optimal relays for publishing based on:
    /// - The event author's relay preferences (NIP-65)
    /// - Recipients' relay preferences (for targeted events)
    /// - Relay performance and availability
    ///
    /// - Parameters:
    ///   - event: The event to publish. Must be signed before publishing.
    ///   - strategy: Optional custom relay selection strategy. If nil, uses default outbox strategy.
    /// - Returns: Set of relay URLs where the event was successfully published.
    /// - Throws: `NDKError` if the event is unsigned or publishing fails completely.
    ///
    /// ## Example
    /// ```swift
    /// let event = NDKEvent(content: "Hello Nostr!", kind: 1)
    /// try event.sign(with: signer)
    /// let relays = try await outbox.publish(event)
    /// print("Published to \(relays.count) relays")
    /// ```
    public func publish(_ event: NDKEvent, strategy: RelaySelectionStrategy? = nil) async throws -> Set<String> {
        let result = try await publishingStrategy.publish(event, customStrategy: strategy)
        return result.successfulRelayUrls
    }

    /// Creates a data source for observing events using the outbox model.
    ///
    /// This method intelligently selects relays based on the filter's authors,
    /// ensuring events are fetched from relays where authors actually publish.
    ///
    /// - Parameters:
    ///   - filter: The filter specifying which events to observe.
    ///   - maxAge: Maximum age of cached events in seconds. Use 0 to disable cache.
    ///   - cachePolicy: Policy for cache usage. Defaults to `.networkOnly`.
    ///   - strategy: Optional custom relay selection strategy. If nil, uses outbox model.
    /// - Returns: `NDKDataSource` that emits matching events as they arrive.
    ///
    /// ## Example
    /// ```swift
    /// let filter = NDKFilter(authors: [alicePubkey], kinds: [1])
    /// let dataSource = await outbox.observe(filter: filter, maxAge: 3600)
    /// 
    /// for await event in dataSource {
    ///     print("New event from Alice: \(event.content)")
    /// }
    /// ```
    ///
    /// - Note: The returned data source automatically handles relay connections
    ///   and reconnections based on the selected relay set.
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
                filter: filter
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

    /// Starts tracking a user's relay preferences for outbox operations.
    ///
    /// This method fetches and caches the user's relay list (NIP-65) to optimize
    /// future publishing and fetching operations involving this user.
    ///
    /// - Parameters:
    ///   - pubkey: The public key of the user to track (hex format).
    ///   - emitDiscoveryEvent: Whether to emit relay discovery events for UI updates. Defaults to `true`.
    ///
    /// ## Example
    /// ```swift
    /// // Start tracking a user's relays
    /// await outbox.trackUser(bobPubkey)
    /// 
    /// // Now publishing to Bob will use his preferred relays
    /// let event = NDKEvent(content: "Hello Bob!", kind: 1)
    /// event.tags = [["p", bobPubkey]]
    /// try await outbox.publish(event)
    /// ```
    ///
    /// - Note: Tracking is asynchronous and may not complete immediately.
    ///   The system will use any available relay information while fetching updates.
    public func trackUser(_ pubkey: String, emitDiscoveryEvent: Bool = true) async {
        // Fetch user's relay information
        if let item = try? await tracker.getRelaysFor(pubkey: pubkey) {
            await tracker.track(
                pubkey: pubkey,
                readRelays: Set(item.readRelays.map { $0.url }),
                writeRelays: Set(item.writeRelays.map { $0.url }),
                source: item.source,
                emitDiscoveryEvent: emitDiscoveryEvent
            )
        }
    }


    /// Gets the current performance score for a relay.
    ///
    /// Relay scores are calculated based on:
    /// - Connection reliability
    /// - Response times
    /// - Message delivery success rate
    /// - Availability history
    ///
    /// - Parameters:
    ///   - relay: The relay URL to check.
    ///   - pubkey: The public key context for the score (scores may vary by user).
    /// - Returns: Score between 0.0 (worst) and 1.0 (best).
    ///
    /// ## Example
    /// ```swift
    /// let score = await outbox.getRelayScore(
    ///     relay: "wss://relay.example.com",
    ///     for: myPubkey
    /// )
    /// if score < 0.5 {
    ///     print("Poor performing relay")
    /// }
    /// ```
    public func getRelayScore(relay: String, for pubkey: String) async -> Double {
        return await ranker.getScore(relay: relay, pubkey: pubkey)
    }

    /// Gets recommended relays for a user based on various factors.
    ///
    /// Recommendations consider:
    /// - User's existing relay preferences
    /// - Relay performance scores
    /// - Network topology and peer usage
    /// - Geographic distribution (when available)
    ///
    /// - Parameters:
    ///   - pubkey: The public key to get recommendations for.
    ///   - count: Maximum number of relay URLs to return. Defaults to 5.
    /// - Returns: Array of recommended relay URLs, ordered by preference.
    ///
    /// ## Example
    /// ```swift
    /// let recommendations = await outbox.getRecommendedRelays(
    ///     for: newUserPubkey,
    ///     count: 3
    /// )
    /// // Suggest these relays to the new user
    /// ```
    public func getRecommendedRelays(for pubkey: String, count: Int = 5) async -> [String] {
        return await selector.selectRelays(for: pubkey, count: count)
    }

    /// Retrieves all tracked relay list items from the cache.
    ///
    /// This method returns cached relay preferences for all tracked users,
    /// useful for debugging or displaying relay usage statistics.
    ///
    /// - Returns: Array of `NDKOutboxItem` containing relay preferences for each tracked user.
    ///
    /// ## Example
    /// ```swift
    /// let items = await outbox.getAllTrackedItems()
    /// for item in items {
    ///     print("User \(item.pubkey) uses \(item.readRelays.count) read relays")
    /// }
    /// ```
    ///
    /// - Note: This only returns cached items. Users not yet tracked won't appear.
    public func getAllTrackedItems() async -> [NDKOutboxItem] {
        return await tracker.getAllCachedItems()
    }

    /// Analyzes a filter and creates an optimized outbox strategy for querying.
    ///
    /// This method breaks down a multi-author filter into relay-specific filters,
    /// ensuring each relay only receives queries for authors who actually use it.
    /// This significantly reduces network overhead and improves query performance.
    ///
    /// - Parameter filter: The filter to analyze and optimize.
    /// - Returns: `OutboxFilterStrategy` containing:
    ///   - `filtersByRelay`: Optimized filters mapped to specific relays
    ///   - `unknownAuthors`: Authors with no known relay information
    ///   - `authorsToDiscover`: Authors whose relay lists should be fetched
    ///
    /// ## Example
    /// ```swift
    /// let filter = NDKFilter(authors: [alice, bob, charlie], kinds: [1])
    /// let strategy = await outbox.getOutboxStrategy(for: filter)
    /// 
    /// // Use the optimized filters
    /// for (relay, optimizedFilter) in strategy.filtersByRelay {
    ///     print("Query \(relay) for \(optimizedFilter.authors?.count ?? 0) authors")
    /// }
    /// ```
    ///
    /// - Note: Authors without known relays will be queried on bootstrap/fallback relays.
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
                let readRelays = item.readRelays
                if !readRelays.isEmpty {
                    NDKLogger.log(.trace, category: .outbox, "✅ Found \(readRelays.count) read relays for \(author.prefix(8))")
                    for relay in readRelays {
                        relayToAuthors[relay.url, default: []].insert(author)
                    }
                } else if !item.writeRelays.isEmpty {
                    // Fall back to write relays if no read relays
                    NDKLogger.log(.trace, category: .outbox, "📝 Using \(item.writeRelays.count) write relays for \(author.prefix(8)) (no read relays)")
                    for relayInfo in item.writeRelays {
                        relayToAuthors[relayInfo.url, default: []].insert(author)
                    }
                } else {
                    // Has relay info but no relays - still unknown
                    NDKLogger.log(.debug, category: .outbox, "⚠️ Author \(author.prefix(8)) has relay info but no relays")
                    unknownAuthors.insert(author)
                }
            } else {
                // No relay info cached
                NDKLogger.log(.debug, category: .outbox, "❓ No relay info cached for \(author.prefix(8))")
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
            // Do NOT set a limit - this prevents filter aggregation
            let relayListFilter = NDKFilter(
                authors: Array(authors),
                kinds: [EventKind.relayList]
            )

            // Determine which relays to use for discovery
            let relaysToUse: Set<RelayURL>
            let connectedRelays = await ndk.pool.connectedRelayURLs
            
            if !ndk.outboxConfig.outboxRelays.isEmpty {
                // Check if any outbox relays are connected
                let connectedOutboxRelays = ndk.outboxConfig.outboxRelays.intersection(connectedRelays)
                
                if !connectedOutboxRelays.isEmpty {
                    // Use connected outbox relays
                    relaysToUse = connectedOutboxRelays
                    NDKLogger.log(.debug, category: .outbox, "📡 Using \(connectedOutboxRelays.count) connected outbox relays for relay discovery")
                } else if !connectedRelays.isEmpty {
                    // Fall back to any connected relays
                    relaysToUse = connectedRelays
                    NDKLogger.log(.warning, category: .outbox, "⚠️ No outbox relays connected, falling back to \(connectedRelays.count) explicit relays for discovery")
                } else {
                    // No relays connected at all
                    NDKLogger.log(.error, category: .outbox, "❌ No relays connected for relay discovery")
                    return
                }
            } else {
                // No outbox relays configured, use all connected relays
                relaysToUse = connectedRelays
                NDKLogger.log(.debug, category: .outbox, "📡 No outbox relays configured, using \(connectedRelays.count) connected relays for discovery")
            }
            
            // Create data source for relay list discovery
            // Generate a short subscription ID by taking prefix of first author and adding count
            let shortAuthorsId = authors.first.map { String($0.prefix(8)) } ?? "unknown"
            let subscriptionId = "relay_disc_\(shortAuthorsId)_\(authors.count)"
            
            let dataSource = NDKDataSource(
                ndk: ndk,
                filter: relayListFilter,
                relays: relaysToUse,
                subscriptionId: subscriptionId
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
        
        // Log specific relays discovered
        if NDKLogger.logLevel >= .debug {
            NDKLogger.log(.debug, category: .outbox, "📋 Read relays: \(readRelays.map { $0.url })")
            NDKLogger.log(.debug, category: .outbox, "📋 Write relays: \(writeRelays.map { $0.url })")
        }
        
        // Emit relay discovery event
        let allRelays = readRelays.union(writeRelays)
        if !allRelays.isEmpty {
            let discovery = RelayDiscovery(
                authors: Set([event.pubkey]),
                relays: Set(allRelays.map { $0.url })
            )
            NDKLogger.log(.info, category: .outbox, "📡 Emitting relay discovery event for \(event.pubkey.prefix(StringConstants.DisplayFormatting.hexPrefixLength)) with \(allRelays.count) relays")
            discoveryContinuation?.yield(discovery)
        }
    }
    
    /// Stop tracking a user for outbox operations
    /// - Parameter pubkey: The public key of the user to stop tracking
    public func untrackUser(_ pubkey: String) async {
        // Remove from tracker cache
        await tracker.clear() // For now, just clear - in future could implement selective removal
    }
    
    /// Get relay update statistics
    /// - Returns: Current statistics about relay updates and subscriptions
    public func getRelayUpdateStats() async -> RelayUpdateStats {
        // For now, return placeholder stats - this would be implemented with actual tracking
        return RelayUpdateStats(
            activeSubscriptions: 0,
            totalUnknownAuthors: 0,
            totalUpdateSubscriptions: 0
        )
    }
    
    /// Stream of relay updates
    public var relayUpdates: AsyncStream<RelayUpdateEvent> {
        // Convert RelayDiscoveryEvent to RelayUpdateEvent
        AsyncStream { continuation in
            Task {
                for await discovery in tracker.relayDiscoveries {
                    let update = RelayUpdateEvent(
                        pubkey: discovery.pubkey,
                        relays: (readRelays: discovery.readRelays, writeRelays: discovery.writeRelays),
                        affectedSubscriptionIds: Set<String>(), // Would need actual subscription tracking
                        timestamp: discovery.timestamp
                    )
                    continuation.yield(update)
                }
                continuation.finish()
            }
        }
    }
}
