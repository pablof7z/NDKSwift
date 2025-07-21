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
        if let subscription = activeSubscriptions.removeValue(forKey: id) {
            await subscription.close()
        }
    }
    
    /// Process incoming event from relay
    func processEvent(_ event: NDKEvent, subscriptionId: String, from relay: RelayProtocol) async {
        guard let subscription = activeSubscriptions[subscriptionId] else {
            return
        }
        await subscription.handleEvent(event, from: relay)
    }
    
    /// Process EOSE from relay
    func processEOSE(subscriptionId: String, from relay: RelayProtocol) async {
        guard let subscription = activeSubscriptions[subscriptionId] else { return }
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
    private var eoseHandlers: [() async -> Void] = []
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
        guard !isActive, let ndk = ndk else { return }
        isActive = true
        
        // Get relays to use
        let targetRelays: [NDKRelay]
        if let specificRelays = relays {
            targetRelays = await ndk.pool.getRelays(for: specificRelays)
        } else {
            targetRelays = await ndk.pool.connectedRelays()
        }
        
        // Send REQ message to each relay
        for relay in targetRelays {
            do {
                let message = createREQMessage()
                try await relay.send(message)
            } catch {
                NDKLogger.log(.warning, category: .subscription, "Failed to send REQ to \(relay.url): \(error)")
            }
        }
    }
    
    /// Close the subscription
    func close() async {
        guard isActive, let ndk = ndk else { return }
        isActive = false
        
        // Get relays to close on
        let targetRelays: [NDKRelay]
        if let specificRelays = relays {
            targetRelays = await ndk.pool.getRelays(for: specificRelays)
        } else {
            targetRelays = await ndk.pool.connectedRelays()
        }
        
        // Send CLOSE message to each relay
        for relay in targetRelays {
            do {
                let message = createCLOSEMessage()
                try await relay.send(message)
            } catch {
                print("[InternalSubscription] Failed to send CLOSE to \(relay.url): \(error)")
            }
        }
        
        // Close the event stream
        eventContinuation?.finish()
        eventContinuation = nil
        eventStream = nil
        
        eventHandlers.removeAll()
        eoseHandlers.removeAll()
    }
    
    /// Register a handler for EOSE (End of Stored Events)
    func onEOSE(_ handler: @escaping () async -> Void) {
        eoseHandlers.append(handler)
    }
    
    /// Handle incoming event
    func handleEvent(_ event: NDKEvent, from relay: RelayProtocol) async {
        // Feed event to stream with relay information
        eventContinuation?.yield((event: event, relay: relay.url))
        
        // Notify all handlers
        for handler in eventHandlers {
            await handler(event)
        }
    }
    
    /// Handle EOSE
    func handleEOSE(from relay: RelayProtocol) async {
        // Notify all handlers
        for handler in eoseHandlers {
            await handler()
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
            print("[InternalSubscription] Failed to create REQ message: \(error)")
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
            print("[InternalSubscription] Failed to create CLOSE message: \(error)")
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