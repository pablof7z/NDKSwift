import Foundation

/// Default implementation of RelayIntelligence that uses HintIndex and pool relays
public final class DefaultRelayIntelligence: RelayIntelligence, @unchecked Sendable {
    private weak var ndk: NDK?

    public init(ndk: NDK) {
        self.ndk = ndk
    }

    // MARK: - Publishing

    public func relaysForPublishing(event: NDKEvent) async -> Set<RelayURL> {
        guard let ndk = ndk else { return [] }

        var relays = Set<RelayURL>()

        // Get explicit relays from pool (always include for publishing)
        let explicitRelays = await getExplicitRelays()
        relays.formUnion(explicitRelays)

        // For replies/mentions, also include relays where targets might see the event
        let targetPubkeys = extractTargetPubkeys(from: event)
        for pubkey in targetPubkeys {
            let hints = await ndk.hintIndex.hints(for: pubkey)
            let hintUrls = hints.map { $0.relay }
            relays.formUnion(hintUrls)
        }

        return relays
    }

    // MARK: - Fetching

    public func relaysForFetching(filter: NDKFilter) async -> Set<RelayURL> {
        guard let ndk = ndk else { return [] }

        var relays = Set<RelayURL>()

        // Check for pubkey hints
        if let authors = filter.authors {
            for author in authors {
                let hints = await ndk.hintIndex.hints(for: author)
                let hintUrls = hints.map { $0.relay }
                relays.formUnion(hintUrls)
            }
        }

        // Check for event ID hints
        if let ids = filter.ids {
            for eventId in ids {
                let hints = await ndk.hintIndex.hints(forEventId: eventId)
                let hintUrls = hints.map { $0.relay }
                relays.formUnion(hintUrls)
            }
        }

        // Always include explicit relays as fallback/supplement
        let explicitRelays = await getExplicitRelays()
        relays.formUnion(explicitRelays)

        return relays
    }

    // MARK: - Subscribing

    public func relaysForSubscribing(filters: [NDKFilter]) async -> Set<RelayURL> {
        var relays = Set<RelayURL>()

        // Aggregate hints from all filters
        for filter in filters {
            let filterRelays = await relaysForFetching(filter: filter)
            relays.formUnion(filterRelays)
        }

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
}
