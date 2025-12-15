import Foundation

/// Manages event publishing and lifecycle
public actor NDKEventManager {
    private weak var ndk: NDK?
    private let cache: NDKCache

    /// Track events that failed due to auth requirements per relay
    private var pendingAuthEvents: [RelayURL: [NDKEvent]] = [:]

    init(ndk: NDK, cache: NDKCache) {
        self.ndk = ndk
        self.cache = cache
    }

    // MARK: - Event Publishing

    /// Publish an event to relays using the outbox model
    ///
    /// This method automatically selects the best relays for publishing based on the event type
    /// and outbox configuration. It uses optimistic publishing for better user experience.
    ///
    /// - Parameters:
    ///   - event: The event to publish (must be signed)
    ///   - logRawJSON: If true, logs the raw JSON of the event for debugging
    /// - Returns: Set of relays that successfully accepted the event
    /// - Throws: `NDKError.invalidContent` if the event is not signed,
    ///           `NDKError.notConfigured` if NDK reference is lost,
    ///           `NDKError.publishError` if publishing fails
    public func publish(_ event: NDKEvent, logRawJSON: Bool = false) async throws -> Set<NDKRelay> {
        guard let ndk = ndk else {
            throw NDKError.notConfigured(ErrorMessageConstants.Messages.ndkReferenceLost)
        }

        // Determine relays for publication
        let relaySelector = ndk.relaySelector
        let selection = await relaySelector.selectRelaysForPublishing(event: event)
        let targetRelayUrls = Set(selection.relays)

        NDKLogger.log(.debug, category: .event, "Event kind: \(event.kind), Selected \(targetRelayUrls.count) relays for publishing: \(targetRelayUrls)")

        // Use common publish implementation
        return try await publishToRelays(event: event, relayURLs: targetRelayUrls, logRawJSON: logRawJSON, useOptimistic: true)
    }

    /// Publish an event to specific relays
    ///
    /// This method bypasses the outbox model and publishes directly to the specified relays.
    /// Optimistic publishing is disabled when using explicit relay selection.
    ///
    /// - Parameters:
    ///   - event: The event to publish (must be signed)
    ///   - relayURLs: Set of relay URLs to publish to
    ///   - logRawJSON: If true, logs the raw JSON of the event for debugging
    /// - Returns: Set of relays that successfully accepted the event
    /// - Throws: `NDKError.invalidContent` if the event is not signed,
    ///           `NDKError.notConfigured` if NDK reference is lost,
    ///           `NDKError.publishError` if publishing fails
    public func publish(event: NDKEvent, to relayURLs: Set<String>, logRawJSON: Bool = false) async throws -> Set<NDKRelay> {
        // Use common publish implementation without optimistic publishing for explicit relay selection
        return try await publishToRelays(event: event, relayURLs: relayURLs, logRawJSON: logRawJSON, useOptimistic: false)
    }

    /// Common implementation for publishing events
    ///
    /// - Parameters:
    ///   - event: The event to publish
    ///   - relayURLs: Target relay URLs
    ///   - logRawJSON: Whether to log raw JSON
    ///   - useOptimistic: Whether to use optimistic publishing
    /// - Returns: Set of relays that accepted the event
    private func publishToRelays(event: NDKEvent, relayURLs: Set<String>, logRawJSON: Bool, useOptimistic: Bool) async throws -> Set<NDKRelay> {
        guard let ndk = ndk else {
            throw NDKError.notConfigured(ErrorMessageConstants.Messages.ndkReferenceLost)
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
                try await cache.addUnpublishedEvent(event, relays: relayURLs)
            } catch {
                NDKLogger.log(.warning, category: .cache, "Failed to add unpublished event to cache: \(error)")
            }

            // Always dispatch optimistically via cache (which notifies observers)
            // Cache processEvent already happened above, so observers are notified
        }

        if logRawJSON {
            do {
                let jsonString = try JSONCoding.encodeToString(event)
                NDKLogger.log(.debug, category: .event, "Publishing event JSON: \(jsonString)")
            } catch {
                NDKLogger.log(.warning, category: .event, "Failed to encode event to JSON for logging: \(error.localizedDescription)")
            }
        }

        // Prepare relays for publishing (add to pool and start connecting)
        let targetRelays = await ndk.pool.prepareRelays(Array(relayURLs), autoConnect: true)

        // Publish to relays
        var publishedRelays = Set<NDKRelay>()
        var failedRelays = Set<NDKRelay>()
        await withTaskGroup(of: (NDKRelay, Bool).self) { group in
            for relay in targetRelays {
                group.addTask {
                    do {
                        let result = try await relay.publish(event)
                        return (relay, result.success)
                    } catch let error as NDKError {
                        // Check if error is auth-required
                        if case let .publishFailed(_, message) = error {
                            let errorMsg = message.lowercased()
                            if errorMsg.contains("auth") || errorMsg.contains("restricted") || errorMsg.contains("authentication") {
                                // Track this event for retry after authentication
                                await self.trackPendingAuthEvent(event, for: relay.url)
                                NDKLogger.log(.info, category: .auth, "Event \(event.id) requires authentication on \(relay.url)")
                            } else {
                                NDKLogger.log(.error, category: .event, "Failed to publish to \(relay.url): \(error)")
                            }
                        } else {
                            NDKLogger.log(.error, category: .event, "Failed to publish to \(relay.url): \(error)")
                        }
                        return (relay, false)
                    } catch {
                        NDKLogger.log(.error, category: .event, "Failed to publish to \(relay.url): \(error)")
                        return (relay, false)
                    }
                }
            }

            for await(relay, success) in group {
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
    public func publish(_ builder: @Sendable (NDKEventBuilder) -> NDKEventBuilder) async throws -> (event: NDKEvent, relays: Set<NDKRelay>) {
        guard let ndk = ndk else {
            throw NDKError.notConfigured(ErrorMessageConstants.Messages.ndkReferenceLost)
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
    public func retryUnpublishedEvents(maxAge: TimeInterval = TimeConstants.unpublishedEventRetryWindow, limit: Int? = nil) async throws -> [(event: NDKEvent, relays: Set<NDKRelay>)] {
        guard ndk != nil else {
            throw NDKError.notConfigured(ErrorMessageConstants.Messages.ndkReferenceLost)
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

    // MARK: - Authentication-Related Methods

    /// Track an event that failed due to auth requirements
    func trackPendingAuthEvent(_ event: NDKEvent, for relay: RelayURL) {
        var pending = pendingAuthEvents[relay] ?? []
        if !pending.contains(where: { $0.id == event.id }) {
            pending.append(event)
            pendingAuthEvents[relay] = pending
            NDKLogger.log(.debug, category: .auth, "Tracked event \(event.id) pending auth for \(relay)")
        }
    }

    /// Get and clear pending auth events for a relay
    func getPendingAuthEvents(for relay: RelayURL) -> [NDKEvent] {
        return pendingAuthEvents.removeValue(forKey: relay) ?? []
    }

    /// Retry events that were pending authentication for a specific relay
    func retryAuthenticatedEvents(for relay: NDKRelay) async {
        let pendingEvents = getPendingAuthEvents(for: relay.url)

        guard !pendingEvents.isEmpty else { return }

        NDKLogger.log(.info, category: .auth, "Retrying \(pendingEvents.count) events after authentication on \(relay.url)")

        for event in pendingEvents {
            do {
                let result = try await relay.publish(event)
                if result.success {
                    NDKLogger.log(.debug, category: .auth, "Successfully published event \(event.id) after authentication")
                    try await cache.confirmEvent(eventId: event.id, onRelay: relay.url)
                } else {
                    NDKLogger.log(.warning, category: .auth, "Failed to publish event \(event.id) after authentication: \(result.message ?? "Unknown error")")
                }
            } catch {
                NDKLogger.log(.error, category: .auth, "Error publishing event \(event.id) after authentication: \(error)")
            }
        }
    }

    /// Publish queued events for a specific relay (called by NDKPool when relay connects)
    func publishQueuedEvents(for relay: NDKRelay) async {
        let unpublishedEvents = await cache.getUnpublishedEvents(maxAge: TimeConstants.unpublishedEventRetryWindow, limit: nil)

        // Count events targeted for this relay
        let eventsForRelay = unpublishedEvents.filter { $0.targetRelays.contains(relay.url) }

        // Only log if there are events to publish
        if !eventsForRelay.isEmpty {
            NDKLogger.log(.debug, category: .relay, "📤 Publishing \(eventsForRelay.count) queued events for newly connected relay: \(relay.url)")
        }

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
