import Foundation

/// Manages event publishing and lifecycle
public actor NDKEventManager {
    private weak var ndk: NDK?
    private let cache: NDKCache
    
    init(ndk: NDK, cache: NDKCache) {
        self.ndk = ndk
        self.cache = cache
    }
    
    // MARK: - Event Publishing
    
    /// Publish an event to relays
    public func publish(_ event: NDKEvent, logRawJSON: Bool = false) async throws -> Set<NDKRelay> {
        guard let ndk = ndk else {
            throw NDKError.notConfigured("NDK reference lost")
        }
        
        // Determine relays for publication
        let relaySelector = ndk.relaySelector
        let selection = await relaySelector.selectRelaysForPublishing(event: event)
        let targetRelayUrls = Set(selection.relays)
        
        NDKLogger.log(.debug, category: .event, "Event kind: \(event.kind), Selected \(targetRelayUrls.count) relays for publishing: \(targetRelayUrls)")
        
        // Use common publish implementation
        return try await publishToRelays(event: event, relayUrls: targetRelayUrls, logRawJSON: logRawJSON, useOptimistic: true)
    }
    
    /// Publish an event to specific relays
    public func publish(event: NDKEvent, to relayUrls: Set<String>, logRawJSON: Bool = false) async throws -> Set<NDKRelay> {
        // Use common publish implementation without optimistic publishing for explicit relay selection
        return try await publishToRelays(event: event, relayUrls: relayUrls, logRawJSON: logRawJSON, useOptimistic: false)
    }
    
    /// Common implementation for publishing events
    private func publishToRelays(event: NDKEvent, relayUrls: Set<String>, logRawJSON: Bool, useOptimistic: Bool) async throws -> Set<NDKRelay> {
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
            NDKLogger.log(.warning, category: .cache, "Failed to cache event: \(error)")
        }
        
        // Always handle optimistic publishing (except for relay lists)
        if useOptimistic && event.kind != 10002 {
            do {
                try await cache.addUnpublishedEvent(event, relays: relayUrls)
            } catch {
                NDKLogger.log(.warning, category: .cache, "Failed to add unpublished event to cache: \(error)")
            }
            
            // Always dispatch optimistically via cache (which notifies observers)
            // Cache processEvent already happened above, so observers are notified
        }
        
        if logRawJSON {
            if let jsonString = try? JSONCoding.encodeToString(event) {
                NDKLogger.log(.debug, category: .event, "Publishing event JSON: \(jsonString)")
            }
        }
        
        // Prepare relays for publishing (add to pool and start connecting)
        let targetRelays = await ndk.pool.prepareRelays(Array(relayUrls), autoConnect: true)
        
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
                        NDKLogger.log(.error, category: .event, "Failed to publish to \(relay.url): \(error)")
                        return (relay, false)
                    }
                }
            }
            
            for await (relay, success) in group {
                if success {
                    publishedRelays.insert(relay)
                    
                    // Update event tracker with successful publish
                    await ndk.eventTracker.updatePublishStatus(eventId: event.id, relay: relay.url, status: .succeeded)
                    await ndk.eventTracker.markSeen(eventId: event.id, relay: relay.url)
                    
                    // Always confirm event in cache
                    do {
                        try await cache.confirmEvent(eventId: event.id, onRelay: relay.url)
                    } catch {
                        NDKLogger.log(.warning, category: .event, "[NDKEventManager] Failed to confirm event: \(error)")
                    }
                } else {
                    failedRelays.insert(relay)
                    
                    // Update event tracker with failed publish
                    await ndk.eventTracker.updatePublishStatus(eventId: event.id, relay: relay.url, status: .failed(.connectionFailed))
                }
            }
        }
        
        // Failed relays are already tracked in the unpublished cache from earlier
        
        return publishedRelays
    }
    
    /// Build and publish an event in one step
    public func publish(_ builder: (NDKEventBuilder) -> NDKEventBuilder) async throws -> (event: NDKEvent, relays: Set<NDKRelay>) {
        guard let ndk = ndk else {
            throw NDKError.notConfigured("NDK reference lost")
        }
        
        let signer = try ndk.requireSigner()
        
        let eventBuilder = NDKEventBuilder(ndk: ndk)
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
                NDKLogger.log(.error, category: .event, "Failed to retry publishing event \(event.id): \(error)")
            }
        }
        
        return results
    }
    
    /// Publish queued events for a specific relay (called by NDKPool when relay connects)
    internal func publishQueuedEvents(for relay: NDKRelay) async {
        let unpublishedEvents = await cache.getUnpublishedEvents(maxAge: 3600, limit: nil)
        
        for (event, targetRelayUrls) in unpublishedEvents {
            if targetRelayUrls.contains(relay.url) {
                do {
                    let result = try await relay.publish(event)
                    if result.success {
                        try await cache.confirmEvent(eventId: event.id, onRelay: relay.url)
                    }
                } catch {
                    NDKLogger.log(.error, category: .event, "Failed to publish queued event to \(relay.url): \(error)")
                }
            }
        }
    }
}