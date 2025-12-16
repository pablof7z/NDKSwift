import Foundation

/// Default implementation of RelayIntelligence that uses HintIndex and pool relays
///
/// Note: @unchecked Sendable is safe here because:
/// - `ndk` is weak and only read (never mutated after init)
/// - `eventStream` is let (immutable after init) and IntelligenceEventStream is an actor
public final class DefaultRelayIntelligence: RelayIntelligence, @unchecked Sendable {
    private weak var ndk: NDK?
    private let eventStream: IntelligenceEventStream?

    public init(ndk: NDK, eventStream: IntelligenceEventStream? = nil) {
        self.ndk = ndk
        self.eventStream = eventStream
    }

    // MARK: - Publishing

    public func relaysForPublishing(event: NDKEvent) async -> Set<RelayURL> {
        guard let ndk = ndk else { return [] }

        var relays = Set<RelayURL>()
        var reason = "explicit relays"

        // Get explicit relays from pool (always include for publishing)
        let explicitRelays = await getExplicitRelays()
        relays.formUnion(explicitRelays)

        // For replies/mentions, also include relays where targets might see the event
        let targetPubkeys = extractTargetPubkeys(from: event)
        for pubkey in targetPubkeys {
            let hints = await ndk.hintIndex.hints(for: pubkey)
            let hintUrls = hints.map { $0.relay }
            if !hintUrls.isEmpty {
                relays.formUnion(hintUrls)
                reason = "explicit + hints for \(targetPubkeys.count) targets"
            }
        }

        await emitRelaySelected(operation: .publish, relays: relays, reason: reason)
        return relays
    }

    // MARK: - Fetching

    public func relaysForFetching(filter: NDKFilter) async -> Set<RelayURL> {
        return await relaysForFetchingInternal(filter: filter, emitEvent: true)
    }

    private func relaysForFetchingInternal(filter: NDKFilter, emitEvent: Bool) async -> Set<RelayURL> {
        guard let ndk = ndk else { return [] }

        var relays = Set<RelayURL>()
        var hasHints = false

        // Check for pubkey hints
        if let authors = filter.authors {
            for author in authors {
                let hints = await ndk.hintIndex.hints(for: author)
                let hintUrls = hints.map { $0.relay }
                if !hintUrls.isEmpty {
                    hasHints = true
                    relays.formUnion(hintUrls)
                }
            }
        }

        // Check for event ID hints
        if let ids = filter.ids {
            for eventId in ids {
                let hints = await ndk.hintIndex.hints(forEventId: eventId)
                let hintUrls = hints.map { $0.relay }
                if !hintUrls.isEmpty {
                    hasHints = true
                    relays.formUnion(hintUrls)
                }
            }
        }

        // Always include explicit relays as fallback/supplement
        let explicitRelays = await getExplicitRelays()
        relays.formUnion(explicitRelays)

        let reason = hasHints ? "hints + explicit relays" : "explicit relays (no hints)"
        if emitEvent {
            await emitRelaySelected(operation: .fetch, relays: relays, reason: reason)
        }
        return relays
    }

    // MARK: - Subscribing

    public func relaysForSubscribing(filters: [NDKFilter]) async -> Set<RelayURL> {
        var relays = Set<RelayURL>()

        // Aggregate hints from all filters (without emitting individual events)
        for filter in filters {
            let filterRelays = await relaysForFetchingInternal(filter: filter, emitEvent: false)
            relays.formUnion(filterRelays)
        }

        let reason = "aggregated from \(filters.count) filter(s)"
        await emitRelaySelected(operation: .subscribe, relays: relays, reason: reason)
        return relays
    }

    // MARK: - Private Helpers

    private func getExplicitRelays() async -> Set<RelayURL> {
        guard let ndk = ndk else { return [] }

        var explicitUrls = Set<RelayURL>()
        let poolRelays = await ndk.pool.relays
        for relay in poolRelays {
            let isPersistent = await relay.isPersistent
            if isPersistent {
                explicitUrls.insert(relay.url)
            }
        }
        return explicitUrls
    }

    /// Extract pubkeys that the event is targeting (p tags)
    private func extractTargetPubkeys(from event: NDKEvent) -> [String] {
        return event.tags
            .filter { $0.first == "p" && $0.count >= 2 }
            .compactMap { $0[safe: 1] }
    }

    /// Emit a relay selection event to the event stream
    private func emitRelaySelected(operation: RelayOperation, relays: Set<RelayURL>, reason: String) async {
        guard let eventStream = eventStream else { return }
        await eventStream.emit(.relaySelected(operation: operation, relays: relays, reason: reason))
    }
}
