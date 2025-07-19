import Foundation

/// Manages event publishing and lifecycle
public actor NDKEventManager {
    private weak var ndk: NDK?
    private let cache: NDKCache
    private let optimisticPublishingConfig: NDKOptimisticPublishingConfig
    
    init(ndk: NDK, cache: NDKCache, optimisticPublishingConfig: NDKOptimisticPublishingConfig) {
        self.ndk = ndk
        self.cache = cache
        self.optimisticPublishingConfig = optimisticPublishingConfig
    }
    
    // MARK: - Event Publishing
    
    /// Publish an event to relays
    public func publish(_ event: NDKEvent, logRawJSON: Bool = false) async throws -> Set<NDKRelay> {
        guard let ndk = ndk else {
            throw NDKError.notConfigured("NDK reference lost")
        }
        
        // Events should already be signed before publishing
        if event.sig.isEmpty {
            throw NDKError.invalidContent("Event must be signed before publishing")
        }
        
        
        // Save to cache first
        do {
            try await cache.saveEvent(event)
        } catch {
            print("[NDKEventManager] Warning: Failed to cache event: \(error)")
        }
        
        // Determine relays for publication
        let relaySelector = ndk.relaySelector
        let selection = await relaySelector.selectRelaysForPublishing(event: event)
        let targetRelayUrls = Array(selection.relays)
        
        print("[NDKEventManager] Event kind: \(event.kind), Selected \(targetRelayUrls.count) relays for publishing: \(targetRelayUrls)")
        
        // Handle optimistic publishing
        if optimisticPublishingConfig.enabled && event.kind != 10002 {
            do {
                try await cache.addUnpublishedEvent(event, relays: Set(targetRelayUrls))
            } catch {
                print("[NDKEventManager] Warning: Failed to add unpublished event to cache: \(error)")
            }
            
            // Dispatch optimistically via subscription coordinator
            await ndk.subscriptionCoordinator.processEvent(event, from: OptimisticEventSource())
        }
        
        if logRawJSON {
            if let jsonString = try? JSONCoding.encodeToString(event) {
                print("[NDKEventManager] Publishing event JSON: \(jsonString)")
            }
        }
        
        // Get relay objects from URLs and start connecting them in parallel
        var targetRelays: [NDKRelay] = []
        
        // First, add all relays to pool and collect them
        for url in targetRelayUrls {
            let relay = await ndk.pool.addRelay(url)
            targetRelays.append(relay)
        }
        
        // Start connecting to disconnected relays in parallel (non-blocking)
        Task {
            await withTaskGroup(of: Void.self) { group in
                for relay in targetRelays {
                    group.addTask {
                        let connectionState = await relay.connectionState
                        if connectionState != .connected && connectionState != .connecting {
                            print("[NDKEventManager] Starting connection to relay for publishing: \(relay.url)")
                            do {
                                try await relay.connect()
                                print("[NDKEventManager] Connected to relay: \(relay.url)")
                            } catch {
                                print("[NDKEventManager] Failed to connect to relay \(relay.url): \(error)")
                            }
                        }
                    }
                }
            }
        }
        
        // Publish to relays
        var publishedRelays = Set<NDKRelay>()
        var failedRelays = Set<NDKRelay>()
        await withTaskGroup(of: (NDKRelay, Bool).self) { group in
            for relay in targetRelays {
                group.addTask {
                    do {
                        let result = try await relay.publish(event)
                        return (relay, result.success)
                    } catch {
                        print("[NDKEventManager] Failed to publish to \(relay.url): \(error)")
                        return (relay, false)
                    }
                }
            }
            
            for await (relay, success) in group {
                if success {
                    publishedRelays.insert(relay)
                    
                    // Confirm event if optimistic publishing is enabled
                    if optimisticPublishingConfig.enabled {
                        do {
                            try await cache.confirmEvent(eventId: event.id, onRelay: relay.url)
                        } catch {
                            print("[NDKEventManager] Warning: Failed to confirm event: \(error)")
                        }
                    }
                } else {
                    failedRelays.insert(relay)
                }
            }
        }
        
        // For non-optimistic publishing, add failed events to unpublished cache for retry
        if !optimisticPublishingConfig.enabled && !failedRelays.isEmpty {
            let failedRelayUrls = Set(failedRelays.map { $0.url })
            do {
                try await cache.addUnpublishedEvent(event, relays: failedRelayUrls)
                print("[NDKEventManager] Added failed event \(event.id) to retry queue for relays: \(failedRelayUrls)")
            } catch {
                print("[NDKEventManager] Warning: Failed to add failed event to cache: \(error)")
            }
        }
        
        return publishedRelays
    }
    
    /// Publish an event to specific relays
    public func publish(event: NDKEvent, to relayUrls: Set<String>) async throws -> Set<NDKRelay> {
        guard let ndk = ndk else {
            throw NDKError.notConfigured("NDK reference lost")
        }
        
        // Events should already be signed before publishing
        if event.sig.isEmpty {
            throw NDKError.invalidContent("Event must be signed before publishing")
        }
        
        // Save to cache
        do {
            try await cache.saveEvent(event)
        } catch {
            print("[NDKEventManager] Warning: Failed to cache event: \(error)")
        }
        
        // Get relay instances and start connecting them in parallel
        var targetRelays = Set<NDKRelay>()
        
        // First, add all relays to pool and collect them
        for url in relayUrls {
            let relay = await ndk.pool.addRelay(url)
            targetRelays.insert(relay)
        }
        
        // Start connecting to disconnected relays in parallel (non-blocking)
        Task {
            await withTaskGroup(of: Void.self) { group in
                for relay in targetRelays {
                    group.addTask {
                        let connectionState = await relay.connectionState
                        if connectionState != .connected && connectionState != .connecting {
                            print("[NDKEventManager] Starting connection to relay for publishing: \(relay.url)")
                            do {
                                try await relay.connect()
                                print("[NDKEventManager] Connected to relay: \(relay.url)")
                            } catch {
                                print("[NDKEventManager] Failed to connect to relay \(relay.url): \(error)")
                            }
                        }
                    }
                }
            }
        }
        
        // Publish to specified relays
        var publishedRelays = Set<NDKRelay>()
        await withTaskGroup(of: (NDKRelay, Bool).self) { group in
            for relay in targetRelays {
                group.addTask {
                    do {
                        let result = try await relay.publish(event)
                        return (relay, result.success)
                    } catch {
                        print("[NDKEventManager] Failed to publish to \(relay.url): \(error)")
                        return (relay, false)
                    }
                }
            }
            
            for await (relay, success) in group {
                if success {
                    publishedRelays.insert(relay)
                }
            }
        }
        
        return publishedRelays
    }
    
    /// Build and publish an event in one step
    public func publish(_ builder: (NDKEventBuilder) -> NDKEventBuilder) async throws -> (event: NDKEvent, relays: Set<NDKRelay>) {
        guard let ndk = ndk else {
            throw NDKError.notConfigured("NDK reference lost")
        }
        
        guard let signer = ndk.signer else {
            throw NDKError.notConfigured("No signer available")
        }
        
        let eventBuilder = ndk.event()
        let configuredBuilder = builder(eventBuilder)
        
        // Build the event
        let event = try await configuredBuilder.build(signer: signer)
        
        // Publish it
        let relays = try await publish(event)
        
        return (event, relays)
    }
    
    /// Retry publishing unpublished events
    public func retryUnpublishedEvents(maxAge: TimeInterval = 3600, limit: Int? = nil) async throws -> [(event: NDKEvent, relays: Set<NDKRelay>)] {
        guard ndk != nil else {
            throw NDKError.notConfigured("NDK reference lost")
        }
        
        let unpublishedEvents = await cache.getUnpublishedEvents(maxAge: maxAge, limit: limit)
        
        var results: [(event: NDKEvent, relays: Set<NDKRelay>)] = []
        
        for (event, targetRelayUrls) in unpublishedEvents {
            do {
                let publishedRelays = try await publish(event: event, to: targetRelayUrls)
                results.append((event: event, relays: publishedRelays))
            } catch {
                print("[NDKEventManager] Failed to retry publishing event \(event.id): \(error)")
            }
        }
        
        return results
    }
    
    /// Publish queued events for a specific relay
    func publishQueuedEvents(for relay: NDKRelay) async {
        let unpublishedEvents = await cache.getUnpublishedEvents(maxAge: 3600, limit: nil)
        
        for (event, targetRelayUrls) in unpublishedEvents {
            if targetRelayUrls.contains(relay.url) {
                do {
                    let result = try await relay.publish(event)
                    if result.success {
                        try await cache.confirmEvent(eventId: event.id, onRelay: relay.url)
                    }
                } catch {
                    print("[NDKEventManager] Failed to publish queued event to \(relay.url): \(error)")
                }
            }
        }
    }
}