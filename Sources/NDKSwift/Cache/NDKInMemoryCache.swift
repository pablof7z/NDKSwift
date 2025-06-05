import Foundation

/// In-memory implementation of NDKCacheAdapter
public final class NDKInMemoryCache: NDKCacheAdapter {
    private var events: [EventID: NDKEvent] = [:]
    private var eventsByFilter: [String: Set<EventID>] = [:]
    private var profiles: [PublicKey: NDKCacheEntry<NDKUserProfile>] = [:]
    private var nip05Cache: [String: (pubkey: PublicKey, relays: [String])] = [:]
    private var relayStatus: [RelayURL: NDKRelayConnectionState] = [:]
    private var unpublishedEvents: [RelayURL: Set<EventID>] = [:]

    private let queue = DispatchQueue(label: "com.ndkswift.inmemorycache", attributes: .concurrent)

    public var locking: Bool { true }
    public var ready: Bool { true }

    public init() {}

    // MARK: - Event Management

    public func query(subscription: NDKSubscription) async -> [NDKEvent] {
        return await withCheckedContinuation { continuation in
            queue.async {
                var results = Set<NDKEvent>()

                for filter in subscription.filters {
                    // Get all events that match this filter
                    let filterKey = self.filterKey(from: filter)
                    if let eventIds = self.eventsByFilter[filterKey] {
                        for eventId in eventIds {
                            if let event = self.events[eventId], filter.matches(event: event) {
                                results.insert(event)
                            }
                        }
                    }

                    // Also check all events if filter is broad
                    if self.isBroadFilter(filter) {
                        for event in self.events.values {
                            if filter.matches(event: event) {
                                results.insert(event)
                            }
                        }
                    }
                }

                continuation.resume(returning: Array(results))
            }
        }
    }

    public func setEvent(_ event: NDKEvent, filters: [NDKFilter], relay _: NDKRelay?) async {
        guard let eventId = event.id else { return }

        await withCheckedContinuation { continuation in
            queue.async(flags: .barrier) {
                // Store the event
                self.events[eventId] = event

                // Index by filters
                for filter in filters {
                    let key = self.filterKey(from: filter)
                    if self.eventsByFilter[key] == nil {
                        self.eventsByFilter[key] = []
                    }
                    self.eventsByFilter[key]?.insert(eventId)
                }

                // Index by common queries
                self.indexEvent(event)

                continuation.resume()
            }
        }
    }

    // MARK: - Profile Management

    public func fetchProfile(pubkey: PublicKey) async -> NDKUserProfile? {
        return await withCheckedContinuation { continuation in
            queue.async {
                if let entry = self.profiles[pubkey], !entry.isExpired {
                    continuation.resume(returning: entry.value)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    public func saveProfile(pubkey: PublicKey, profile: NDKUserProfile) async {
        await withCheckedContinuation { continuation in
            queue.async(flags: .barrier) {
                let entry = NDKCacheEntry(
                    value: profile,
                    expiresAt: Date().addingTimeInterval(3600) // 1 hour cache
                )
                self.profiles[pubkey] = entry
                continuation.resume()
            }
        }
    }

    // MARK: - NIP-05 Management

    public func loadNip05(_ nip05: String) async -> (pubkey: PublicKey, relays: [String])? {
        return await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.nip05Cache[nip05.lowercased()])
            }
        }
    }

    public func saveNip05(_ nip05: String, pubkey: PublicKey, relays: [String]) async {
        await withCheckedContinuation { continuation in
            queue.async(flags: .barrier) {
                self.nip05Cache[nip05.lowercased()] = (pubkey, relays)
                continuation.resume()
            }
        }
    }

    // MARK: - Relay Status

    public func updateRelayStatus(_ url: RelayURL, status: NDKRelayConnectionState) async {
        await withCheckedContinuation { continuation in
            queue.async(flags: .barrier) {
                self.relayStatus[url] = status
                continuation.resume()
            }
        }
    }

    public func getRelayStatus(_ url: RelayURL) async -> NDKRelayConnectionState? {
        return await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.relayStatus[url])
            }
        }
    }

    // MARK: - Unpublished Events

    public func addUnpublishedEvent(_ event: NDKEvent, relayUrls: [RelayURL]) async {
        guard let eventId = event.id else { return }

        await withCheckedContinuation { continuation in
            queue.async(flags: .barrier) {
                for url in relayUrls {
                    if self.unpublishedEvents[url] == nil {
                        self.unpublishedEvents[url] = []
                    }
                    self.unpublishedEvents[url]?.insert(eventId)
                }

                // Also store the event itself
                self.events[eventId] = event

                continuation.resume()
            }
        }
    }

    public func getUnpublishedEvents(for relayUrl: RelayURL) async -> [NDKEvent] {
        return await withCheckedContinuation { continuation in
            queue.async {
                guard let eventIds = self.unpublishedEvents[relayUrl] else {
                    continuation.resume(returning: [])
                    return
                }

                let events = eventIds.compactMap { self.events[$0] }
                continuation.resume(returning: events)
            }
        }
    }

    public func removeUnpublishedEvent(_ eventId: EventID, from relayUrl: RelayURL) async {
        await withCheckedContinuation { continuation in
            queue.async(flags: .barrier) {
                self.unpublishedEvents[relayUrl]?.remove(eventId)
                continuation.resume()
            }
        }
    }

    // MARK: - Private Helpers

    private func filterKey(from filter: NDKFilter) -> String {
        var parts: [String] = []

        if let kinds = filter.kinds {
            parts.append("kinds:\(kinds.sorted().map(String.init).joined(separator: ","))")
        }
        if let authors = filter.authors {
            parts.append("authors:\(authors.sorted().joined(separator: ","))")
        }
        if let ids = filter.ids {
            parts.append("ids:\(ids.sorted().joined(separator: ","))")
        }

        return parts.joined(separator: "|")
    }

    private func isBroadFilter(_ filter: NDKFilter) -> Bool {
        return filter.ids == nil && filter.authors == nil && filter.kinds == nil
    }

    private func indexEvent(_ event: NDKEvent) {
        guard let eventId = event.id else { return }

        // Index by author
        let authorKey = "authors:\(event.pubkey)"
        if eventsByFilter[authorKey] == nil {
            eventsByFilter[authorKey] = []
        }
        eventsByFilter[authorKey]?.insert(eventId)

        // Index by kind
        let kindKey = "kinds:\(event.kind)"
        if eventsByFilter[kindKey] == nil {
            eventsByFilter[kindKey] = []
        }
        eventsByFilter[kindKey]?.insert(eventId)
    }

    // MARK: - Cache Management

    /// Clear all cached data
    public func clear() async {
        await withCheckedContinuation { continuation in
            queue.async(flags: .barrier) {
                self.events.removeAll()
                self.eventsByFilter.removeAll()
                self.profiles.removeAll()
                self.nip05Cache.removeAll()
                self.relayStatus.removeAll()
                self.unpublishedEvents.removeAll()
                continuation.resume()
            }
        }
    }

    /// Get cache statistics
    public func statistics() async -> (events: Int, profiles: Int, nip05: Int) {
        return await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: (
                    events: self.events.count,
                    profiles: self.profiles.count,
                    nip05: self.nip05Cache.count
                ))
            }
        }
    }
}
