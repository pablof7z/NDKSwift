import Foundation

/// Internal subscription manager for NDKSubscriptionManager only.
/// Use `ndk.subscribe()` for the public API.
actor InternalSubscriptionManager {
    private let ndk: NDK
    private var activeSubscriptions: [String: NDKSubscriptionCoordinator] = [:]
    private var relayMonitorTask: Task<Void, Never>?

    // NEW: Fingerprint-based routing
    private var fingerprintSubscriptions: [NDKFilterFingerprint: Set<NDKSubscriptionCoordinator>] = [:]
    private var relayIdToFingerprint: [String: NDKFilterFingerprint] = [:]

    // NEW: Relay-to-subscription mapping for O(1) lookups
    private var relayToSubscriptions: [RelayURL: Set<NDKSubscriptionCoordinator>] = [:]

    init(ndk: NDK) {
        self.ndk = ndk
        // Start monitoring in a task to avoid accessing pool before it's ready
        Task {
            await startRelayMonitoring()
        }
    }

    /// Start relay monitoring if not already started
    private func ensureRelayMonitoring() async {
        guard relayMonitorTask == nil else { return }
        await startRelayMonitoring()
    }

    /// Create an internal subscription
    func createSubscription(
        id: String,
        filters: [NDKFilter],
        relays: Set<RelayURL>? = nil,
        fingerprint: NDKFilterFingerprint? = nil,
        closeOnEose: Bool = false,
        autoStart: Bool = true,
        isGroupable: Bool = true,
        groupableDelay: TimeInterval? = nil,
        groupableDelayType: NDKSubscriptionDelayType? = nil
    ) async -> NDKSubscriptionCoordinator {
        // Ensure relay monitoring is started when first subscription is created
        await ensureRelayMonitoring()

        // Remove any existing subscription with same ID
        if let existing = activeSubscriptions[id] {
            NDKLogger.log(.warning, category: .subscription, "♻️ Replacing existing subscription with ID: \(id)")
            await existing.close()
        }

        let fp = fingerprint ?? filters.toFingerprint(closeOnEose: closeOnEose)

        let subscription = NDKSubscriptionCoordinator(
            id: id,
            filters: filters,
            relays: relays,
            ndk: ndk,
            closeOnEose: closeOnEose,
            fingerprint: fp,
            isGroupable: isGroupable,
            groupableDelay: groupableDelay,
            groupableDelayType: groupableDelayType
        )

        activeSubscriptions[id] = subscription

        // Add to fingerprint mapping
        var subs = fingerprintSubscriptions[fp] ?? Set<NDKSubscriptionCoordinator>()
        subs.insert(subscription)
        fingerprintSubscriptions[fp] = subs

        // Add to relay-based mapping
        if let specificRelays = relays {
            // Subscription targets specific relays
            for relayUrl in specificRelays {
                var relaySubs = relayToSubscriptions[relayUrl] ?? Set<NDKSubscriptionCoordinator>()
                relaySubs.insert(subscription)
                relayToSubscriptions[relayUrl] = relaySubs
            }
        } else {
            // When relays are not specified, the subscription will use outbox model
            // or fallback relays when started
            NDKLogger.log(.debug, category: .subscription, "📌 Subscription created without explicit relays2 - will use outbox model or fallback relays")
        }

        NDKLogger.log(.debug, category: .subscription, "📌 Created subscription '\(id)' with fingerprint '\(fp)'")

        // Start the subscription if autoStart is true
        if autoStart {
            await subscription.start()
        }

        return subscription
    }

    /// Register a relay-specific ID mapping to a fingerprint
    func registerRelayIdMapping(relayId: String, fingerprint: NDKFilterFingerprint) async {
        // Ensure the relay ID doesn't exceed limits
        let safeRelayId = NDKSubscriptionIDGenerator.generateRelayID(from: relayId)
        relayIdToFingerprint[safeRelayId] = fingerprint
        NDKLogger.log(.debug, category: .subscription, "🔗 [InternalSubManager] Registered relay ID mapping: '\(safeRelayId)' → fingerprint '\(fingerprint)'")
        NDKLogger.log(.trace, category: .subscription,
                      "   Total relay ID mappings: \(relayIdToFingerprint.count)")
    }

    /// Update relay associations for a subscription (used by outbox model)
    func updateRelayAssociation(subscription: NDKSubscriptionCoordinator, relay: RelayURL) async {
        var relaySubs = relayToSubscriptions[relay] ?? Set<NDKSubscriptionCoordinator>()
        relaySubs.insert(subscription)
        relayToSubscriptions[relay] = relaySubs

        NDKLogger.log(.debug, category: .subscription,
                      "🔗 [InternalSubManager] Updated relay association: '\(subscription.id)' → '\(relay)'")
    }

    /// Close a subscription
    func closeSubscription(id: String) async {
        if let subscription = activeSubscriptions.removeValue(forKey: id) {
            // Remove from fingerprint mapping
            let fingerprint = await subscription.fingerprint
            if let subs = fingerprintSubscriptions[fingerprint] {
                var updatedSubs = subs
                updatedSubs.remove(subscription)
                if updatedSubs.isEmpty {
                    fingerprintSubscriptions.removeValue(forKey: fingerprint)
                } else {
                    fingerprintSubscriptions[fingerprint] = updatedSubs
                }
            }

            // Remove from relay-based mapping
            // Check all relays since subscription might have been associated dynamically
            for (relayUrl, var relaySubs) in relayToSubscriptions {
                if relaySubs.contains(subscription) {
                    relaySubs.remove(subscription)
                    if relaySubs.isEmpty {
                        relayToSubscriptions.removeValue(forKey: relayUrl)
                    } else {
                        relayToSubscriptions[relayUrl] = relaySubs
                    }
                }
            }

            await subscription.close()
            NDKLogger.log(.info, category: .subscription, "✅ Closed subscription: \(id), remaining active: \(activeSubscriptions.count)")
        } else {
            NDKLogger.log(.warning, category: .subscription, "⚠️ Attempted to close non-existent subscription: \(id)")
        }
    }

    /// Process incoming event from relay
    func processEvent(_ event: NDKEvent, subscriptionId: String, from relay: RelayProtocol) async {
        NDKLogger.log(.trace, category: .subscription,
                      "📥 [InternalSubManager] Processing event for subscription ID '\(subscriptionId)' from relay \(relay.url)")

        // Track which subscriptions have already received this event to avoid duplicates
        var deliveredTo = Set<String>()

        // Try direct lookup first
        if let subscription = activeSubscriptions[subscriptionId] {
            NDKLogger.log(.trace, category: .subscription,
                          "✅ [InternalSubManager] Found direct subscription for ID '\(subscriptionId)'")
            await subscription.handleEvent(event, from: relay)
            deliveredTo.insert(subscription.id)
        }

        // Try fingerprint-based routing for relay-specific IDs
        if let fingerprint = relayIdToFingerprint[subscriptionId],
           let subscriptions = fingerprintSubscriptions[fingerprint]
        {
            NDKLogger.log(.trace, category: .subscription, "🔀 Routing via fingerprint: \(subscriptionId) → \(fingerprint) (\(subscriptions.count) subscriptions)")
            for subscription in subscriptions {
                if !deliveredTo.contains(subscription.id) {
                    await subscription.handleEvent(event, from: relay)
                    deliveredTo.insert(subscription.id)
                }
            }
        }

        if deliveredTo.isEmpty {
            NDKLogger.log(.trace, category: .subscription, "🚫 No matching subscriptions found for event")
        }
    }

    /// Process EOSE from relay
    func processEOSE(subscriptionId: String, from relay: RelayProtocol) async {
        // Try direct lookup first
        if let subscription = activeSubscriptions[subscriptionId] {
            await subscription.handleEOSE(from: relay)
            return
        }

        // NEW: Try fingerprint-based routing for relay-specific IDs
        if let fingerprint = relayIdToFingerprint[subscriptionId],
           let subscriptions = fingerprintSubscriptions[fingerprint]
        {
            NDKLogger.log(.trace, category: .subscription, "🔀 Routing EOSE via fingerprint: \(subscriptionId) → \(fingerprint)")
            for subscription in subscriptions {
                await subscription.handleEOSE(from: relay)
            }
            return
        }

        NDKLogger.log(.trace, category: .subscription, "🚫 Ignoring EOSE for non-existent subscription: \(subscriptionId)")
    }

    // MARK: - Relay Monitoring

    /// Start monitoring relay connection events
    private func startRelayMonitoring() async {
        // Pool is always available
        let pool = ndk.pool

        relayMonitorTask = Task {
            NDKLogger.log(.info, category: .subscription, "🔍 [InternalSubManager] Starting relay connection monitoring")

            for await event in await pool.relayChanges {
                guard !Task.isCancelled else { break }

                switch event {
                case let .relayConnected(relay):
                    NDKLogger.log(.info, category: .subscription, "🔌 [InternalSubManager] Relay connected: \(relay.url) - replaying subscriptions")
                    await replaySubscriptionsForRelay(relay)
                default:
                    break // We only care about connections
                }
            }
        }
    }

    /// Replay active subscriptions for a newly connected relay
    private func replaySubscriptionsForRelay(_ relay: NDKRelay) async {
        // O(1) lookup: Get subscriptions that specifically target this relay
        let relaySpecificSubs = relayToSubscriptions[relay.url] ?? []
        let subscriptionsToReplay = Array(relaySpecificSubs)

        guard !subscriptionsToReplay.isEmpty else {
            NDKLogger.log(.debug, category: .subscription, "📭 No active subscriptions to replay for \(relay.url)")
            return
        }

        NDKLogger.log(.debug, category: .subscription, "🔍 Found \(subscriptionsToReplay.count) subscriptions for relay \(relay.url) (O(1) lookup)")

        // All subscriptions in this list are already relevant - no filtering needed
        let relevantSubscriptions = subscriptionsToReplay

        guard !relevantSubscriptions.isEmpty else {
            NDKLogger.log(.debug, category: .subscription, "📭 No relevant subscriptions to replay for \(relay.url)")
            return
        }

        NDKLogger.log(.info, category: .subscription, "🔄 Replaying \(relevantSubscriptions.count) subscriptions to \(relay.url)")

        // Log details of subscriptions being replayed
        for (index, subscription) in relevantSubscriptions.enumerated() {
            let filterSummary = subscription.filters.map { filter in
                var parts: [String] = []
                if let kinds = filter.kinds {
                    parts.append("kinds:\(kinds)")
                }
                if let authors = filter.authors {
                    parts.append("authors:\(authors.map { String($0.prefix(8)) }.joined(separator: ","))")
                }
                if let limit = filter.limit {
                    parts.append("limit:\(limit)")
                }
                if let tags = filter.tags, !tags.isEmpty {
                    parts.append("tags:\(tags.keys.joined(separator: ","))")
                }
                return parts.joined(separator: ", ")
            }.joined(separator: " | ")

            NDKLogger.log(.debug, category: .subscription, "  \(index + 1). \(subscription.id): \(filterSummary)")
        }

        for subscription in relevantSubscriptions {
            // Check if we already sent REQ to this relay
            let alreadySent = await subscription.activeRelays.contains(relay.url)
            if alreadySent {
                NDKLogger.log(.debug, category: .subscription, "⏭️ Subscription \(subscription.id) already sent to \(relay.url)")
                continue
            }

            // Check if subscription has been started
            let hasActiveRelays = await !subscription.activeRelays.isEmpty
            let isSubscriptionActive = await subscription.isActive

            if !isSubscriptionActive {
                // If not started yet, start it now
                NDKLogger.log(.info, category: .subscription, "🚀 Starting inactive subscription \(subscription.id) for relay \(relay.url)")
                await subscription.start()
            } else if !hasActiveRelays {
                // If started but no relays active (all were disconnected), add to relay via subscription manager
                NDKLogger.log(.info, category: .subscription, "🔄 Subscription \(subscription.id) was started but has no active relays - adding to \(relay.url)")

                // Route through subscription manager for proper grouping
                await relay.addSubscription(subscription, filters: subscription.filters)
                await subscription.markRelayAsActive(relay.url)
                NDKLogger.log(.info, category: .subscription, "✅ Activated subscription \(subscription.id) on relay \(relay.url)")
            } else {
                // If already active on other relays, add to this relay via subscription manager
                NDKLogger.log(.debug, category: .subscription, "📨 [RelayReplay] Replaying subscription \(subscription.id) to \(relay.url)")

                // Route through subscription manager for proper grouping
                await relay.addSubscription(subscription, filters: subscription.filters)
                await subscription.markRelayAsActive(relay.url)

                NDKLogger.log(.info, category: .subscription, "✅ Replayed subscription \(subscription.id) to \(relay.url)")
            }
        }
    }

    deinit {
        relayMonitorTask?.cancel()
    }
}

/// Internal subscription handler for relay communication.
/// Part of the internal implementation of NDKSubscriptionManager.
actor NDKSubscriptionCoordinator: Hashable {
    let id: String
    let filters: [NDKFilter]
    let relays: Set<RelayURL>?
    private weak var ndk: NDK?

    // NEW: Fingerprint for internal routing
    var fingerprint: NDKFilterFingerprint = ""
    nonisolated let closeOnEose: Bool

    // Grouping configuration
    nonisolated let isGroupable: Bool
    nonisolated let groupableDelay: TimeInterval?
    nonisolated let groupableDelayType: NDKSubscriptionDelayType?

    private var eoseHandlers: [(String) async -> Void] = [] // Changed to include relay URL
    var isActive = false

    // Callbacks for NDKSubscriptionRequirement
    private var onEvent: ((NDKEvent, NDKRelay) async -> Void)?
    private var onEOSE: ((NDKRelay) async -> Void)?

    /// Set the event handler callback
    func setOnEvent(_ handler: @escaping (NDKEvent, NDKRelay) async -> Void) {
        onEvent = handler
    }

    /// Set the EOSE handler callback
    func setOnEOSE(_ handler: @escaping (NDKRelay) async -> Void) {
        onEOSE = handler
    }

    // Track which relays we actually sent REQ to
    var activeRelays: Set<String> = []

    // AsyncSequence support
    private var eventStream: AsyncStream<(event: NDKEvent, relay: String)>?
    private var eventContinuation: AsyncStream<(event: NDKEvent, relay: String)>.Continuation?

    // Make it Hashable for Set storage
    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    nonisolated static func == (lhs: NDKSubscriptionCoordinator, rhs: NDKSubscriptionCoordinator) -> Bool {
        lhs.id == rhs.id
    }

    /// Events as an AsyncSequence with relay information
    var events: AsyncStream<(event: NDKEvent, relay: String)> {
        if let existingStream = eventStream {
            return existingStream
        }

        let (stream, continuation) = AsyncStream<(event: NDKEvent, relay: String)>.makeStream()
        eventStream = stream
        eventContinuation = continuation

        return stream
    }

    init(
        id: String,
        filters: [NDKFilter],
        relays: Set<RelayURL>?,
        ndk: NDK,
        closeOnEose: Bool = false,
        fingerprint: NDKFilterFingerprint? = nil,
        isGroupable: Bool = true,
        groupableDelay: TimeInterval? = nil,
        groupableDelayType: NDKSubscriptionDelayType? = nil
    ) {
        self.id = id
        self.filters = filters
        self.relays = relays
        self.ndk = ndk
        self.closeOnEose = closeOnEose
        self.fingerprint = fingerprint ?? filters.toFingerprint(closeOnEose: closeOnEose)
        self.isGroupable = isGroupable
        // Default delay values matching ndk-core
        self.groupableDelay = groupableDelay ?? (isGroupable ? 0.1 : nil)
        self.groupableDelayType = groupableDelayType ?? (isGroupable ? .atMost : nil)
    }

    /// Start the subscription
    func start() async {
        guard !isActive, let _ = ndk else {
            let reason = isActive ? "already active" : ErrorMessageConstants.Messages.ndkReferenceLost
            let filterSummary = filters.map { filter in
                var parts: [String] = []
                if let kinds = filter.kinds { parts.append("kinds:\(kinds)") }
                if let authors = filter.authors { parts.append("authors:\(authors.count)") }
                if let limit = filter.limit { parts.append("limit:\(limit)") }
                return parts.joined(separator: ",")
            }.joined(separator: "; ")

            NDKLogger.log(.warning, category: .subscription, "⚠️ Cannot start subscription '\(id)' - reason: \(reason), filters: [\(filterSummary)], activeRelays: \(activeRelays)")
            return
        }
        isActive = true

        // NOTE: In the new architecture, the actual subscription sending is handled by
        // relay-level subscription managers. This method now just marks the subscription as active.
        // The NDKSubscriptionRequirement will handle adding subscriptions to specific relays based on
        // the relay selection strategy (outbox, explicit, or default).

        NDKLogger.log(.info, category: .subscription, "✅ NDKSubscriptionCoordinator '\(id)' is now active")
    }

    /// Mark a relay as active (used when replay succeeds)
    func markRelayAsActive(_ relayUrl: String) {
        activeRelays.insert(relayUrl)
    }

    /// Handle incoming event
    func handleEvent(_ event: NDKEvent, from relay: RelayProtocol) async {
        // Call callback if set (new architecture)
        if let onEvent = onEvent {
            // Only pass NDKRelay instances to maintain type safety
            // For other RelayProtocol implementations, we can't guarantee full NDKRelay functionality
            guard let ndkRelay = relay as? NDKRelay else {
                NDKLogger.log(.warning, category: .subscription, "Received event from non-NDKRelay relay: \(relay.url)")
                return
            }
            await onEvent(event, ndkRelay)
        }

        // Stream to AsyncSequence
        eventContinuation?.yield((event: event, relay: relay.url))
    }

    /// Handle EOSE
    func handleEOSE(from relay: RelayProtocol) async {
        // Call callback if set (new architecture)
        if let onEOSE = onEOSE {
            guard let ndkRelay = relay as? NDKRelay else {
                NDKLogger.log(.warning, category: .subscription, "Received EOSE from non-NDKRelay relay: \(relay.url)")
                return
            }
            await onEOSE(ndkRelay)
        }

        // Call legacy handlers
        for handler in eoseHandlers {
            await handler(relay.url)
        }

        // Close if configured
        if closeOnEose {
            await close()
        }
    }

    /// Handle CLOSED message from relay
    func handleClosed(from relay: RelayProtocol, message: String) async {
        NDKLogger.log(.warning, category: .subscription,
                      "⚠️ Subscription \(id) closed by relay \(relay.url): \(message)")

        // Remove this relay from active relays
        activeRelays.remove(relay.url)

        // If no more active relays, close the subscription
        if activeRelays.isEmpty {
            await close()
        }
    }

    /// Close the subscription
    func close() async {
        guard isActive else {
            NDKLogger.log(.trace, category: .subscription, "🔄 Subscription already closed: \(id)")
            return
        }
        isActive = false

        NDKLogger.log(.info, category: .subscription, "🛑 Closing NDKSubscriptionCoordinator: \(id)")

        // In the new architecture, subscriptions are managed at the relay level
        // The NDKSubscriptionRequirement will handle removing subscriptions from relays

        // Close event stream
        eventContinuation?.finish()
        eventContinuation = nil
        eventStream = nil

        // Clear EOSE handlers
        eoseHandlers.removeAll()

        // Clear active relays
        activeRelays.removeAll()
    }

    /// Register a handler for EOSE (End of Stored Events) with relay information
    func onEOSE(_ handler: @escaping (String) async -> Void) {
        eoseHandlers.append(handler)
    }

    /// Create REQ message
    func createREQMessage() -> String {
        var message: [Any] = ["REQ", id]

        for filter in filters {
            var filterDict: [String: Any] = [:]

            if let authors = filter.authors {
                filterDict["authors"] = authors
            }

            if let kinds = filter.kinds {
                filterDict["kinds"] = kinds
            }

            if let ids = filter.ids {
                filterDict["ids"] = ids
            }

            if let tags = filter.tags {
                for (key, values) in tags {
                    filterDict["#\(key)"] = Array(values)
                }
            }

            if let since = filter.since {
                filterDict["since"] = since
            }

            if let until = filter.until {
                filterDict["until"] = until
            }

            if let limit = filter.limit {
                filterDict["limit"] = limit
            }

            message.append(filterDict)
        }

        do {
            return try JSONCoding.serializeToString(message)
        } catch {
            NDKLogger.log(.error, category: .subscription, ErrorMessageConstants.failedTo("create REQ message") + ": \(error)")
            return ""
        }
    }

    /// Create CLOSE message
    private func createCLOSEMessage() -> String {
        let message: [Any] = ["CLOSE", id]

        do {
            return try JSONCoding.serializeToString(message)
        } catch {
            NDKLogger.log(.error, category: .subscription, ErrorMessageConstants.failedTo("create CLOSE message") + ": \(error)")
            return ""
        }
    }
}

// MARK: - Testing Support

extension NDKSubscriptionCoordinator {
    /// Testing interface for inspecting subscription state
    struct InspectionData {
        public let id: String
        public let isGroupable: Bool
        public let groupableDelay: TimeInterval?
        public let groupableDelayType: NDKSubscriptionDelayType?
        public let isActive: Bool
        public let activeRelays: Set<String>
        public let fingerprint: String
        public let closeOnEose: Bool
        public let filterCount: Int
    }

    /// Get inspection data for testing
    func inspect() async -> InspectionData {
        InspectionData(
            id: id,
            isGroupable: isGroupable,
            groupableDelay: groupableDelay,
            groupableDelayType: groupableDelayType,
            isActive: isActive,
            activeRelays: activeRelays,
            fingerprint: fingerprint,
            closeOnEose: closeOnEose,
            filterCount: filters.count
        )
    }
}
