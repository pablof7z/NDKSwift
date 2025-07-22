import Foundation

/// Internal subscription manager for NDKDataRequirementManager only.
/// Use `ndk.observe()` for the public API.
actor InternalSubscriptionManager {
    private let ndk: NDK
    private var activeSubscriptions: [String: InternalSubscription] = [:]
    
    init(ndk: NDK) {
        self.ndk = ndk
    }
    
    /// Create an internal subscription
    func createSubscription(
        id: String,
        filters: [NDKFilter],
        relays: Set<RelayURL>? = nil
    ) async -> InternalSubscription {
        
        // Remove any existing subscription with same ID
        if let existing = activeSubscriptions[id] {
            NDKLogger.log(.warning, category: .subscription, "♻️ Replacing existing subscription with ID: \(id)")
            await existing.close()
        }
        
        let subscription = InternalSubscription(
            id: id,
            filters: filters,
            relays: relays,
            ndk: ndk
        )
        
        activeSubscriptions[id] = subscription
        
        // Start the subscription
        await subscription.start()
        
        return subscription
    }
    
    /// Close a subscription
    func closeSubscription(id: String) async {
        NDKLogger.log(.debug, category: .subscription, "🚪 Closing subscription: \(id)")
        if let subscription = activeSubscriptions.removeValue(forKey: id) {
            await subscription.close()
            NDKLogger.log(.info, category: .subscription, "✅ Closed subscription: \(id), remaining active: \(activeSubscriptions.count)")
        } else {
            NDKLogger.log(.warning, category: .subscription, "⚠️ Attempted to close non-existent subscription: \(id)")
        }
    }
    
    /// Process incoming event from relay
    func processEvent(_ event: NDKEvent, subscriptionId: String, from relay: RelayProtocol) async {
        guard let subscription = activeSubscriptions[subscriptionId] else {
            NDKLogger.log(.trace, category: .subscription, "🚫 Ignoring event for non-existent subscription: \(subscriptionId)")
            return
        }
        await subscription.handleEvent(event, from: relay)
    }
    
    /// Process EOSE from relay
    func processEOSE(subscriptionId: String, from relay: RelayProtocol) async {
        guard let subscription = activeSubscriptions[subscriptionId] else {
            NDKLogger.log(.trace, category: .subscription, "🚫 Ignoring EOSE for non-existent subscription: \(subscriptionId)")
            return
        }
        await subscription.handleEOSE(from: relay)
    }
}

/// Internal subscription handler for relay communication.
/// Part of the internal implementation of NDKDataRequirementManager.
actor InternalSubscription {
    let id: String
    let filters: [NDKFilter]
    let relays: Set<RelayURL>?
    private weak var ndk: NDK?
    
    private var eventHandlers: [(NDKEvent) async -> Void] = []
    private var eoseHandlers: [(String) async -> Void] = []  // Changed to include relay URL
    private var isActive = false
    
    // AsyncSequence support
    private var eventStream: AsyncStream<(event: NDKEvent, relay: String)>?
    private var eventContinuation: AsyncStream<(event: NDKEvent, relay: String)>.Continuation?
    
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
    
    init(id: String, filters: [NDKFilter], relays: Set<RelayURL>?, ndk: NDK) {
        self.id = id
        self.filters = filters
        self.relays = relays
        self.ndk = ndk
    }
    
    /// Start the subscription
    func start() async {
        guard !isActive, let ndk = ndk else {
            NDKLogger.log(.warning, category: .subscription, "⚠️ Cannot start subscription - isActive: \(isActive), hasNDK: \(ndk != nil)")
            return
        }
        isActive = true
        
        // Get relays to use
        let targetRelays: [NDKRelay]
        if let specificRelays = relays {
            targetRelays = await ndk.pool.getRelays(for: specificRelays)
        } else {
            targetRelays = await ndk.pool.connectedRelays()
        }
        
        // Send REQ message to each relay
        var successCount = 0
        for relay in targetRelays {
            do {
                let message = createREQMessage()
                try await relay.send(message)
                
                // Track subscription on the relay
                await relay.trackSubscription(id: id, filters: filters)
                
                successCount += 1
            } catch {
                NDKLogger.log(.error, category: .subscription, "❌ Failed to send REQ to \(relay.url): \(error)")
            }
        }
    }
    
    /// Close the subscription
    func close() async {
        guard isActive, let ndk = ndk else {
            NDKLogger.log(.trace, category: .subscription, "🔄 Subscription already closed or no NDK: \(id)")
            return
        }
        isActive = false
        NDKLogger.log(.info, category: .subscription, "🛑 Closing subscription: \(id)")
        
        // Get relays to close on
        let targetRelays: [NDKRelay]
        if let specificRelays = relays {
            targetRelays = await ndk.pool.getRelays(for: specificRelays)
        } else {
            targetRelays = await ndk.pool.connectedRelays()
        }
        
        // Send CLOSE message to each relay
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
    private func createREQMessage() -> String {
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
            let jsonData = try JSONSerialization.data(withJSONObject: message, options: [.withoutEscapingSlashes])
            return String(data: jsonData, encoding: .utf8) ?? ""
        } catch {
            NDKLogger.log(.error, category: .subscription, "Failed to create REQ message: \(error)")
            return ""
        }
    }
    
    /// Create CLOSE message
    private func createCLOSEMessage() -> String {
        let message: [Any] = ["CLOSE", id]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: message, options: [.withoutEscapingSlashes])
            return String(data: jsonData, encoding: .utf8) ?? ""
        } catch {
            NDKLogger.log(.error, category: .subscription, "Failed to create CLOSE message: \(error)")
            return ""
        }
    }
}

// MARK: - NDKPool Extension for internal use
extension NDKPool {
    /// Get relays for given URLs (internal use only)
    func getRelays(for urls: Set<RelayURL>) async -> [NDKRelay] {
        var relays: [NDKRelay] = []
        for url in urls {
            if let relay = await getRelay(for: url) {
                relays.append(relay)
            }
        }
        return relays
    }
}