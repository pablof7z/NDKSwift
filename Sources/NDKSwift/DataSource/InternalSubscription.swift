import Foundation

/// Internal subscription manager for NDKDataRequirementManager only.
/// Use `ndk.observe()` for the public API.
actor InternalSubscriptionManager {
    private let ndk: NDK
    private var activeSubscriptions: [String: InternalSubscription] = [:]
    private var relayMonitorTask: Task<Void, Never>?
    
    // NEW: Fingerprint-based routing
    private var fingerprintSubscriptions: [NDKFilterFingerprint: Set<InternalSubscription>] = [:]
    private var relayIdToFingerprint: [String: NDKFilterFingerprint] = [:]
    
    // NEW: Relay-to-subscription mapping for O(1) lookups
    private var relayToSubscriptions: [RelayURL: Set<InternalSubscription>] = [:]
    // Track subscriptions that go to all relays (no specific relay targets)
    private var universalSubscriptions: Set<InternalSubscription> = []

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
        autoStart: Bool = true
    ) async -> InternalSubscription {
        // Ensure relay monitoring is started when first subscription is created
        await ensureRelayMonitoring()

        // Remove any existing subscription with same ID
        if let existing = activeSubscriptions[id] {
            NDKLogger.log(.warning, category: .subscription, "♻️ Replacing existing subscription with ID: \(id)")
            await existing.close()
        }

        let fp = fingerprint ?? filters.toFingerprint(closeOnEose: closeOnEose)
        
        let subscription = InternalSubscription(
            id: id,
            filters: filters,
            relays: relays,
            ndk: ndk,
            closeOnEose: closeOnEose,
            fingerprint: fp
        )

        activeSubscriptions[id] = subscription
        
        // Add to fingerprint mapping
        var subs = fingerprintSubscriptions[fp] ?? Set<InternalSubscription>()
        subs.insert(subscription)
        fingerprintSubscriptions[fp] = subs
        
        // Add to relay-based mapping
        if let specificRelays = relays {
            // Subscription targets specific relays
            for relayUrl in specificRelays {
                var relaySubs = relayToSubscriptions[relayUrl] ?? Set<InternalSubscription>()
                relaySubs.insert(subscription)
                relayToSubscriptions[relayUrl] = relaySubs
            }
        } else {
            // Subscription goes to all relays
            universalSubscriptions.insert(subscription)
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
        NDKLogger.log(.debug, category: .subscription, "🔗 Registered relay ID '\(safeRelayId)' → fingerprint '\(fingerprint)'")
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
            if let specificRelays = subscription.relays {
                for relayUrl in specificRelays {
                    if var relaySubs = relayToSubscriptions[relayUrl] {
                        relaySubs.remove(subscription)
                        if relaySubs.isEmpty {
                            relayToSubscriptions.removeValue(forKey: relayUrl)
                        } else {
                            relayToSubscriptions[relayUrl] = relaySubs
                        }
                    }
                }
            } else {
                universalSubscriptions.remove(subscription)
            }
            
            await subscription.close()
            NDKLogger.log(.info, category: .subscription, "✅ Closed subscription: \(id), remaining active: \(activeSubscriptions.count)")
        } else {
            NDKLogger.log(.warning, category: .subscription, "⚠️ Attempted to close non-existent subscription: \(id)")
        }
    }

    /// Process incoming event from relay
    func processEvent(_ event: NDKEvent, subscriptionId: String, from relay: RelayProtocol) async {
        // Try direct lookup first
        if let subscription = activeSubscriptions[subscriptionId] {
            await subscription.handleEvent(event, from: relay)
            return
        }
        
        // NEW: Try fingerprint-based routing for relay-specific IDs
        if let fingerprint = relayIdToFingerprint[subscriptionId],
           let subscriptions = fingerprintSubscriptions[fingerprint] {
            NDKLogger.log(.trace, category: .subscription, "🔀 Routing via fingerprint: \(subscriptionId) → \(fingerprint) (\(subscriptions.count) subscriptions)")
            for subscription in subscriptions {
                await subscription.handleEvent(event, from: relay)
            }
            return
        }
        
        NDKLogger.log(.trace, category: .subscription, "🚫 Ignoring event for non-existent subscription: \(subscriptionId)")
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
           let subscriptions = fingerprintSubscriptions[fingerprint] {
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
        // Ensure pool is available before starting monitoring
        guard let pool = ndk.pool else {
            NDKLogger.log(.warning, category: .subscription, "⚠️ [InternalSubManager] Pool not available, skipping relay monitoring")
            return
        }

        relayMonitorTask = Task {
            NDKLogger.log(.info, category: .subscription, "🔍 [InternalSubManager] Starting relay connection monitoring")

            for await event in await pool.relayChanges {
                guard !Task.isCancelled else { break }

                switch event {
                case .relayConnected(let relay):
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
        
        // Combine relay-specific and universal subscriptions
        let subscriptionsToReplay = Array(relaySpecificSubs) + Array(universalSubscriptions)
        
        guard !subscriptionsToReplay.isEmpty else {
            NDKLogger.log(.debug, category: .subscription, "📭 No active subscriptions to replay for \(relay.url)")
            return
        }
        
        NDKLogger.log(.debug, category: .subscription, "🔍 Found \(subscriptionsToReplay.count) subscriptions for relay \(relay.url) (O(1) lookup)")
        NDKLogger.log(.debug, category: .subscription, "  - Relay-specific: \(relaySpecificSubs.count)")
        NDKLogger.log(.debug, category: .subscription, "  - Universal: \(universalSubscriptions.count)")
        
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
                // If started but no relays active (all were disconnected), try sending to this relay
                NDKLogger.log(.info, category: .subscription, "🔄 Subscription \(subscription.id) was started but has no active relays - sending REQ to \(relay.url)")
                do {
                    let message = await subscription.createREQMessage()
                    try await relay.send(message)
                    await relay.trackSubscription(id: subscription.id, filters: subscription.filters)
                    await subscription.markRelayAsActive(relay.url)
                    NDKLogger.log(.info, category: .subscription, "✅ Activated subscription \(subscription.id) on relay \(relay.url)")
                } catch {
                    NDKLogger.log(.error, category: .subscription, "❌ Failed to activate subscription \(subscription.id) on \(relay.url): \(error)")
                }
            } else {
                // If already active on other relays, just send REQ to this relay
                do {
                    let message = await subscription.createREQMessage()
                    NDKLogger.log(.debug, category: .subscription, "📨 Replaying subscription \(subscription.id) to \(relay.url)")
                    try await relay.send(message)

                    // Track subscription on the relay
                    await relay.trackSubscription(id: subscription.id, filters: subscription.filters)
                    
                    // Update the subscription's active relays
                    await subscription.markRelayAsActive(relay.url)

                    NDKLogger.log(.info, category: .subscription, "✅ Replayed subscription \(subscription.id) to \(relay.url)")
                } catch {
                    NDKLogger.log(.error, category: .subscription, "❌ Failed to replay subscription \(subscription.id) to \(relay.url): \(error)")
                }
            }
        }
    }

    deinit {
        relayMonitorTask?.cancel()
    }
}

/// Internal subscription handler for relay communication.
/// Part of the internal implementation of NDKDataRequirementManager.
actor InternalSubscription: Hashable {
    let id: String
    let filters: [NDKFilter]
    let relays: Set<RelayURL>?
    private weak var ndk: NDK?
    
    // NEW: Fingerprint for internal routing
    var fingerprint: NDKFilterFingerprint = ""
    let closeOnEose: Bool

    private var eventHandlers: [(NDKEvent) async -> Void] = []
    private var eoseHandlers: [(String) async -> Void] = []  // Changed to include relay URL
    var isActive = false
    
    // Track which relays we actually sent REQ to
    var activeRelays: Set<String> = []

    // AsyncSequence support
    private var eventStream: AsyncStream<(event: NDKEvent, relay: String)>?
    private var eventContinuation: AsyncStream<(event: NDKEvent, relay: String)>.Continuation?
    
    // Make it Hashable for Set storage
    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    nonisolated static func == (lhs: InternalSubscription, rhs: InternalSubscription) -> Bool {
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

    init(id: String, filters: [NDKFilter], relays: Set<RelayURL>?, ndk: NDK, closeOnEose: Bool = false, fingerprint: NDKFilterFingerprint? = nil) {
        self.id = id
        self.filters = filters
        self.relays = relays
        self.ndk = ndk
        self.closeOnEose = closeOnEose
        self.fingerprint = fingerprint ?? filters.toFingerprint(closeOnEose: closeOnEose)
    }

    /// Start the subscription
    func start() async {
        guard !isActive, let ndk = ndk else {
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

        // Get relays to use
        let targetRelays: [NDKRelay]
        if let specificRelays = relays {
            // Use prepareRelays with autoConnect to ensure relays are connected
            targetRelays = await ndk.pool.prepareRelays(Array(specificRelays), autoConnect: true)
        } else {
            targetRelays = await ndk.pool.connectedRelays()
        }
        
        NDKLogger.log(.info, category: .subscription, "🚀 Opening subscription: \(id) on relays: \(targetRelays.map { $0.url })")
        
        // Send REQ message to each relay
        var successCount = 0
        var pendingCount = 0
        for relay in targetRelays {
            // Check if relay is connected
            if await relay.connectionState != .connected {
                NDKLogger.log(.debug, category: .subscription, "⏳ Relay \(relay.url) not connected yet - will send REQ when it connects")
                pendingCount += 1
                continue
            }
            
            do {
                let message = createREQMessage()
                try await relay.send(message)

                // Track subscription on the relay
                await relay.trackSubscription(id: id, filters: filters)
                
                // Track that we successfully sent REQ to this relay
                activeRelays.insert(relay.url)

                successCount += 1
            } catch {
                NDKLogger.log(.error, category: .subscription, "❌ Failed to send REQ to \(relay.url): \(error)")
            }
        }
        
        if pendingCount > 0 {
            NDKLogger.log(.debug, category: .subscription, "📊 Subscription \(id): sent to \(successCount) relays, \(pendingCount) pending connection")
        }
    }

    /// Mark a relay as active (used when replay succeeds)
    func markRelayAsActive(_ relayUrl: String) {
        activeRelays.insert(relayUrl)
    }
    
    /// Close the subscription
    func close() async {
        guard isActive, let ndk = ndk else {
            NDKLogger.log(.trace, category: .subscription, "🔄 Subscription already closed or no NDK: \(id)")
            return
        }
        isActive = false
        
        // Log stack trace to debug why subscription is closing
        let stackSymbols = Thread.callStackSymbols
        let relevantStack = stackSymbols.filter { 
            $0.contains("NDK") && !$0.contains("NDKLogger")
        }.prefix(10)
        
        NDKLogger.log(.info, category: .subscription, "🛑 Closing subscription: \(id) on relays: \(Array(activeRelays))")
        if !relevantStack.isEmpty {
            NDKLogger.log(.debug, category: .subscription, "📚 Stack trace for close: \n\(relevantStack.joined(separator: "\n"))")
        }

        // Only send CLOSE to relays we actually sent REQ to
        if !activeRelays.isEmpty {
            let targetRelays: [NDKRelay]
            if let specificRelays = relays {
                // Filter to only include relays we sent REQ to
                let activeRelayUrls = specificRelays.filter { activeRelays.contains($0) }
                targetRelays = await ndk.pool.prepareRelays(Array(activeRelayUrls), autoConnect: false)
            } else {
                // Get all connected relays and filter to active ones
                let allRelays = await ndk.pool.connectedRelays()
                targetRelays = allRelays.filter { activeRelays.contains($0.url) }
            }

            // Send CLOSE message to each active relay
            var closeCount = 0
            for relay in targetRelays {
                do {
                    let message = createCLOSEMessage()
                    try await relay.send(message)

                    // Untrack subscription from the relay
                    await relay.untrackSubscription(id: id)

                    closeCount += 1
                } catch {
                    NDKLogger.log(.error, category: .subscription, "❌ Failed to send CLOSE to \(relay.url): \(error)")
                }
            }
            
            // Clear active relays
            activeRelays.removeAll()
        }

        // Close the event stream
        eventContinuation?.finish()
        eventContinuation = nil
        eventStream = nil

        eventHandlers.removeAll()
        eoseHandlers.removeAll()
    }

    /// Register a handler for EOSE (End of Stored Events) with relay information
    func onEOSE(_ handler: @escaping (String) async -> Void) {
        eoseHandlers.append(handler)
    }

    /// Handle incoming event
    func handleEvent(_ event: NDKEvent, from relay: RelayProtocol) async {
        NDKLogger.log(.trace, category: .subscription, "📨 Handling event - id: \(event.id), kind: \(event.kind), from: \(relay.url)")

        // Feed event to stream with relay information
        if eventContinuation != nil {
            eventContinuation?.yield((event: event, relay: relay.url))
            NDKLogger.log(.trace, category: .subscription, "✅ Event yielded to stream")
        } else {
            NDKLogger.log(.warning, category: .subscription, "⚠️ No event continuation available")
        }

        // Notify all handlers
        if !eventHandlers.isEmpty {
            NDKLogger.log(.trace, category: .subscription, "📢 Notifying \(eventHandlers.count) event handlers")
            for handler in eventHandlers {
                await handler(event)
            }
        }
    }

    /// Handle EOSE
    func handleEOSE(from relay: RelayProtocol) async {

        // Notify all handlers with relay URL
        if !eoseHandlers.isEmpty {
            NDKLogger.log(.trace, category: .subscription, "📢 Notifying \(eoseHandlers.count) EOSE handlers")
            for handler in eoseHandlers {
                await handler(relay.url)
            }
        } else {
            NDKLogger.log(.trace, category: .subscription, "📦 No EOSE handlers registered")
        }
    }

    /// Create REQ message
    internal func createREQMessage() -> String {
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
