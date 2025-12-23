import Foundation

/// Protocol for relay preference tracking functionality
/// This allows both NDKOutboxManager and future implementations to provide the same interface
public protocol RelayPreferenceProvider {
    func getRelaysSyncFor(pubkey: String, type: RelayListType) async -> NDKOutboxItem?
    func getRelaysFor(pubkey: String, maxAge: TimeInterval, type: RelayListType) async throws -> NDKOutboxItem?
    func getAllCachedItems() async -> [NDKOutboxItem]
    func track(pubkey: String, readRelays: Set<String>, writeRelays: Set<String>, source: RelayListSource, emitDiscoveryEvent: Bool) async
    func clear() async
    func cleanupExpired() async
}

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

/// Type of relay list to fetch
public enum RelayListType {
    case read
    case write
    case both
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
/// let dataSource = await ndk.outbox.subscribe(filter: filter)
/// for await event in dataSource {
///     print("Received event: \(event)")
/// }
/// ```
public actor NDKOutboxManager: RelayPreferenceProvider {
    // MARK: - Constants

    /// Default TTL for positive cache entries (24 hours)
    static let positiveEntryTTL: TimeInterval = TimeConstants.day

    /// Default TTL for negative cache entries (1 hour)
    static let negativeEntryTTL: TimeInterval = TimeConstants.hour

    /// Default in-memory cache capacity
    static let defaultCapacity = NetworkConstants.outboxTrackerCapacity

    // MARK: - Properties

    private let ndk: NDK
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

    // MARK: - Cache Implementation (merged from tracker)

    private let memoryCache: LRUCache<String, CachedRelayPreference>
    private let blacklistedRelays: Set<String>

    /// Track pending fetches to avoid duplicate requests
    private var pendingFetches: [String: Task<NDKOutboxItem?, Error>] = [:]

    /// Stream of relay discoveries as they happen
    public let relayDiscoveries: AsyncStream<RelayDiscoveryEvent>
    private let relayDiscoveryContinuation: AsyncStream<RelayDiscoveryEvent>.Continuation

    /// Cached relay preference with metadata
    private struct CachedRelayPreference {
        let item: NDKOutboxItem? // nil = negative cache
        let fetchedAt: Date
        let expiresAt: Date
        let checkedRelays: Set<String>? // For negative entries only
    }

    init(
        ndk: NDK,
        capacity: Int = NDKOutboxManager.defaultCapacity,
        blacklistedRelays: Set<String> = []
    ) {
        self.ndk = ndk
        lookupTracker = RelayListLookupTracker()
        memoryCache = LRUCache(capacity: capacity, defaultTTL: Self.positiveEntryTTL)
        self.blacklistedRelays = blacklistedRelays

        // Set up discovery stream
        var continuation: AsyncStream<RelayDiscoveryEvent>.Continuation!
        relayDiscoveries = AsyncStream { cont in
            continuation = cont
        }
        relayDiscoveryContinuation = continuation
    }

    // MARK: - Public API

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
    /// - Returns: `NDKSubscription` that emits matching events as they arrive.
    ///
    /// ## Example
    /// ```swift
    /// let filter = NDKFilter(authors: [alicePubkey], kinds: [1])
    /// let dataSource = await outbox.subscribe(filter: filter, maxAge: 3600)
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
    ) async -> NDKSubscription<NDKEvent> {
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
        return NDKSubscription(
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
        if let item = try? await getRelaysFor(pubkey: pubkey) {
            await track(
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
            // Note: Invalid relays (ws://, localhost) are already filtered at track() time
            if let item = await getRelaysSyncFor(pubkey: author, type: .both) {
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
                    // Has relay info but no relays - treat as unknown
                    NDKLogger.log(.debug, category: .outbox, "⚠️ Author \(author.prefix(8)) has relay info but no relays")
                    unknownAuthors.insert(author)
                }
            } else {
                // No relay info cached
                NDKLogger.log(.debug, category: .outbox, "❓ No relay info cached for \(author.prefix(8))")
                unknownAuthors.insert(author)

                // Check if we should look them up (don't mark as looked up here - that happens when discovery is triggered)
                if await lookupTracker.shouldLookup(author) {
                    authorsToDiscover.insert(author)
                }
            }
        }

        NDKLogger.log(.info, category: .outbox, "📊 Relay mapping: \(unknownAuthors.count) unknown authors, \(authorsToDiscover.count) to discover")

        // Log current state of relayToAuthors before adding unknown authors
        if !relayToAuthors.isEmpty {
            NDKLogger.log(.debug, category: .outbox, "📋 Current relayToAuthors mapping before adding unknown authors:")
            for (relay, authors) in relayToAuthors {
                NDKLogger.log(.debug, category: .outbox, "  - \(relay): \(authors.count) authors")
            }
        }

        // NOTE: Unknown authors are NOT added to relayToAuthors here!
        // They are kept separate in `unknownAuthors` and handled by applyOutboxStrategy
        // which routes them to fallback relays with `isFallback: true`.
        // This ensures fallback relay coverage doesn't count toward author-specific coverage.
        if !unknownAuthors.isEmpty {
            NDKLogger.log(.debug, category: .outbox, "📋 \(unknownAuthors.count) unknown authors will use fallback relays (not added to filtersByRelay)")
        }

        // Create relay-specific filters
        NDKLogger.log(.debug, category: .outbox, "📝 Creating filters from relayToAuthors mapping with \(relayToAuthors.count) entries")
        for (relay, relayAuthors) in relayToAuthors {
            NDKLogger.log(.debug, category: .outbox, "  - Relay \(relay): \(relayAuthors.count) authors")
            var relayFilter = filter
            relayFilter.authors = Array(relayAuthors)
            filtersByRelay[relay] = relayFilter
        }

        NDKLogger.log(.info, category: .outbox, "✅ Created \(filtersByRelay.count) relay-specific filters")
        for (relay, _) in filtersByRelay {
            NDKLogger.log(.debug, category: .outbox, "  - Filter for relay: \(relay)")
        }

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
            guard let relaysToUse = await getRelaysForDiscovery() else {
                NDKLogger.log(.warning, category: .outbox, "⏳ No relays connected for relay discovery - marking \(authors.count) authors as pending")
                await lookupTracker.markPending(authors)
                return
            }

            // Mark authors as looked up only AFTER we've confirmed we have relays to use
            // This ensures we retry discovery if it fails due to no relays being connected
            await lookupTracker.markLookedUp(authors)

            // Create data source for relay list discovery
            // Generate a short subscription ID by taking prefix of first author and adding count
            let shortAuthorsId = authors.first.map { String($0.prefix(8)) } ?? "unknown"
            let subscriptionId = "relay_disc_\(shortAuthorsId)_\(authors.count)"

            let dataSource = NDKSubscription(
                ndk: ndk,
                filter: relayListFilter,
                relays: relaysToUse,
                subscriptionId: subscriptionId
            )

            // Process relay lists as they arrive
            var eventCount = 0

            for await batch in dataSource.events {
                eventCount += batch.count
                for event in batch {
                    await processRelayListEvent(event)
                }
            }

            NDKLogger.log(.info, category: .outbox, "✅ Relay discovery completed for \(authors.count) authors - received \(eventCount) events total")
        }
    }

    /// Process a relay list event and update tracking
    func processRelayListEvent(_ event: NDKEvent) async {
        guard event.kind == EventKind.relayList else { return }

        NDKLogger.log(.debug, category: .outbox, "📋 Processing relay list for \(event.pubkey.prefix(StringConstants.DisplayFormatting.hexPrefixLength))")

        let relayList = NDKRelayList.fromEvent(event)

        let readRelayUrls = Set(relayList.readRelays.validForOutbox.map { $0.url })
        let writeRelayUrls = Set(relayList.writeRelays.validForOutbox.map { $0.url })

        // Update tracker and emit discovery event immediately
        // Batching/debouncing is handled by consumers who need it (e.g., NDKSubscriptionManager)
        await track(
            pubkey: event.pubkey,
            readRelays: readRelayUrls,
            writeRelays: writeRelayUrls,
            source: .nip65,
            emitDiscoveryEvent: true
        )

        NDKLogger.log(.info, category: .outbox, "✅ Updated relay info for \(event.pubkey.prefix(StringConstants.DisplayFormatting.hexPrefixLength)): \(readRelayUrls.count) read, \(writeRelayUrls.count) write")
    }

    /// Retry pending discoveries when relays connect
    /// Called when a relay connects to check if there are authors we couldn't look up earlier
    public func retryPendingDiscoveries() async {
        // Get authors that need lookup (weren't marked because no relays were connected)
        let pendingAuthors = await lookupTracker.getPendingAuthors()

        guard !pendingAuthors.isEmpty else {
            NDKLogger.log(.trace, category: .outbox, "🔄 No pending authors to discover")
            return
        }

        // Check if we have connected relays now
        let connectedRelays = await ndk.pool.connectedRelayURLs
        guard !connectedRelays.isEmpty else {
            NDKLogger.log(.trace, category: .outbox, "🔄 Still no connected relays for discovery")
            return
        }

        NDKLogger.log(.info, category: .outbox, "🚀 Retrying discovery for \(pendingAuthors.count) authors now that relays are connected")
        discoverRelaysInBackground(for: pendingAuthors)
    }

    // MARK: - Cache Methods

    /// Get relay information for a user
    public func getRelaysFor(
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

    /// Get relay information synchronously from cache only (memory + database, no network)
    public func getRelaysSyncFor(
        pubkey: String,
        type: RelayListType = .both
    ) async -> NDKOutboxItem? {
        // 1. Check memory cache first
        if let cached = await memoryCache.get(pubkey),
           let item = cached.item {
            return filterByType(item, type: type)
        }

        // 2. Check database cache (local, no network - still "sync")
        if let cached = await checkDatabaseCache(pubkey: pubkey, maxAge: TimeConstants.day * 7) {
            if let item = cached.item {
                return filterByType(item, type: type)
            }
        }

        return nil
    }

    /// Get all cached outbox items
    public func getAllCachedItems() async -> [NDKOutboxItem] {
        var items: [NDKOutboxItem] = []

        // Get all items from memory cache
        let allKeys = await memoryCache.getAllKeys()
        for key in allKeys {
            if let cached = await memoryCache.get(key),
               let item = cached.item,
               Date() <= cached.expiresAt
            {
                items.append(item)
            }
        }

        return items
    }

    /// Track a user's relay information
    public func track(
        pubkey: String,
        readRelays: Set<String> = [],
        writeRelays: Set<String> = [],
        source: RelayListSource = .manual,
        emitDiscoveryEvent: Bool = true
    ) async {
        // Filter out blacklisted and invalid relays (ws://, localhost) at the source
        let filteredReadRelays = readRelays.subtracting(blacklistedRelays).validForOutbox
        let filteredWriteRelays = writeRelays.subtracting(blacklistedRelays).validForOutbox

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

    /// Clear the cache
    public func clear() async {
        await memoryCache.clear()
        pendingFetches.removeAll()
    }

    /// Clean up expired entries
    public func cleanupExpired() async {
        await memoryCache.cleanupExpired()
    }

    // MARK: - Private Relay Selection

    /// Determines which relays to use for relay list discovery/fetching
    /// Prefers outbox relays if connected, falls back to any connected relays
    /// - Returns: Set of relay URLs to use, or nil if no relays are connected
    private func getRelaysForDiscovery() async -> Set<RelayURL>? {
        let connectedRelays = await ndk.pool.connectedRelayURLs

        if !ndk.outboxConfig.outboxRelays.isEmpty {
            let normalizedOutboxRelays = Set(ndk.outboxConfig.outboxRelays.map { $0.normalizedRelayURL })
            let connectedOutboxRelays = normalizedOutboxRelays.intersection(connectedRelays)

            if !connectedOutboxRelays.isEmpty {
                return connectedOutboxRelays
            }
        }

        return connectedRelays.isEmpty ? nil : connectedRelays
    }

    // MARK: - Private Cache Methods

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
        _ = maxAge // maxAge not applicable for cached events - we trust the cache

        // Query kind 10002 events directly from the cache
        let filter = NDKFilter(authors: [pubkey], kinds: [EventKind.relayList], limit: 1)
        guard let events = try? await ndk.cache.queryEvents(filter),
              let event = events.first else {
            return nil
        }

        // Use event creation time as fetchedAt (best available timestamp)
        let fetchedAt = Date(timeIntervalSince1970: TimeInterval(event.createdAt))

        // Note: We don't check maxAge here because event.createdAt is when the USER
        // created the event, not when we cached it. A kind 10002 could be years old
        // but still be the user's current valid relay list.

        let relayList = NDKRelayList.fromEvent(event)

        let writeRelayInfos = relayList.writeRelays.validForOutbox
            .filter { !blacklistedRelays.contains($0.url) }
            .map { RelayInfo(url: $0.url) }
        let readRelayInfos = relayList.readRelays.validForOutbox
            .filter { !blacklistedRelays.contains($0.url) }
            .map { RelayInfo(url: $0.url) }

        let item = NDKOutboxItem(
            pubkey: pubkey,
            readRelays: Set(readRelayInfos),
            writeRelays: Set(writeRelayInfos),
            fetchedAt: fetchedAt,
            source: .nip65
        )

        // Set expiration to 7 days from event creation
        let expiresAt = fetchedAt.addingTimeInterval(TimeConstants.day * 7)

        let cached = CachedRelayPreference(
            item: item,
            fetchedAt: fetchedAt,
            expiresAt: expiresAt,
            checkedRelays: nil
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

        // Update memory cache (kind 10002 events are already saved via normal event flow)
        await memoryCache.set(pubkey, value: cached)
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
        guard let relaysToUse = await getRelaysForDiscovery() else {
            NDKLogger.log(.error, category: .outbox, "❌ No relays connected for relay list fetch")
            return (nil, Set())
        }

        // Use determined relays
        let dataSource = ndk.subscribe(
            filter: filter,
            maxAge: 0,
            cachePolicy: .networkOnly,
            relays: relaysToUse,
            includeRelayUpdates: true
        )

        // Process both events and relay updates with timeout
        await withTaskGroup(of: Void.self) { group in
            // Task 1: Collect events
            group.addTask {
                for await batch in dataSource.events {
                    for event in batch {
                        if relayListEvent == nil || event.createdAt > relayListEvent!.createdAt {
                            relayListEvent = event
                        }
                    }
                }
            }

            // Task 2: Track EOSE
            group.addTask {
                guard let relayUpdates = dataSource.relayUpdates else { return }
                for await update in relayUpdates {
                    if case let .eose(relay) = update {
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

        let readRelayUrls = Set(relayList.readRelays.validForOutbox.map { $0.url }).subtracting(blacklistedRelays)
        let writeRelayUrls = Set(relayList.writeRelays.validForOutbox.map { $0.url }).subtracting(blacklistedRelays)

        let readRelayInfos = readRelayUrls.map { RelayInfo(url: $0) }
        let writeRelayInfos = writeRelayUrls.map { RelayInfo(url: $0) }

        let rawReadCount = relayList.readRelays.count
        let rawWriteCount = relayList.writeRelays.count
        if rawReadCount != readRelayUrls.count || rawWriteCount != writeRelayUrls.count {
            NDKLogger.log(.debug, category: .outbox, "🚫 Filtered invalid/blacklisted relays - Raw: \(rawReadCount)r/\(rawWriteCount)w → Valid: \(readRelayUrls.count)r/\(writeRelayUrls.count)w")
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

    // MARK: - Test Helpers

    /// Get pending authors that are waiting for relay connection to be discovered
    /// This is exposed for testing purposes
    public func getPendingAuthorsForTesting() async -> Set<String> {
        await lookupTracker.getPendingAuthors()
    }
}
