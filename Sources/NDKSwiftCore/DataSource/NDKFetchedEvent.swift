import Foundation

/// Observable wrapper for fetching a single event by identifier or tag.
///
/// `NDKFetchedEvent` provides a modern, cache-first API for fetching individual events
/// with intelligent relay selection and automatic updates for replaceable events.
///
/// ## Features
/// - **Cache-first**: Returns cached non-replaceable events immediately without network fetch
/// - **Smart updates**: For replaceable events, returns cached version immediately and updates when newer version arrives
/// - **Relay hints**: Extracts and uses relay hints from bech32 identifiers (nevent1, naddr1) and NIP-10 tags
/// - **Outbox model**: Falls back to author's write relays using pubkey hints
/// - **Observable**: Automatically updates UI when newer event arrives
///
/// ## Usage
/// ```swift
/// // Fetch by identifier (hex, note1, nevent1, naddr1)
/// let fetched = ndk.fetchEvent("nevent1qqs...")
/// // UI binds to fetched.event
///
/// // Fetch from NIP-10 tag with hints
/// let tag = ["e", "event-id", "wss://relay.com", "reply", "author-pubkey"]
/// let fetched = ndk.fetchEvent(tag: tag)
/// ```
@Observable
@MainActor
public final class NDKFetchedEvent {
    /// The fetched event, updates when newer version arrives (for replaceable events)
    public private(set) var event: NDKEvent?

    /// Whether the fetch is currently in progress
    public private(set) var isLoading: Bool = false

    /// Error if fetch failed
    public private(set) var error: Error?

    private weak var ndk: NDK?

    /// Thread-safe cancellation handle
    private let cancellation = CancellationHandle()

    /// Active subscription for network fetch
    private var subscription: NDKSubscription<NDKEvent>?

    // MARK: - Initialization

    init(ndk: NDK, identifier: String) {
        self.ndk = ndk
        Task { await startFetching(identifier: identifier) }
    }

    init(ndk: NDK, tag: Tag) {
        self.ndk = ndk
        Task { await startFetching(tag: tag) }
    }

    deinit {
        cancellation.cancel()
    }

    // MARK: - Fetching Logic

    private func startFetching(identifier: String) async {
        guard let ndk else { return }

        isLoading = true
        error = nil

        do {
            // Parse identifier and extract hints
            let filter = try NostrIdentifier.createFilter(from: identifier)
            guard let eventId = filter.ids?.first else {
                throw NDKError.invalidEventID("No event ID found in identifier")
            }

            // Extract relay hints from bech32 if available
            var relayHints: [String]?
            if Bech32.isBech32(identifier) {
                if let decoded = try? ContentTagger.decodeNostrEntity(identifier) {
                    relayHints = decoded.relays
                }
            }

            await performFetch(eventId: eventId, filter: filter, bech32Relays: relayHints, tagRelayHint: nil, pubkeyHint: nil)
        } catch {
            self.error = error
            self.isLoading = false
        }
    }

    private func startFetching(tag: Tag) async {
        guard let ndk else { return }

        isLoading = true
        error = nil

        // Parse tag format: ["e", "event-id", "relay-hint", "marker", "pubkey-hint"]
        let (eventId, relayHint, pubkeyHint) = extractHintsFromTag(tag)

        guard let eventId else {
            error = NDKError.invalidEventID("Tag missing event ID")
            isLoading = false
            return
        }

        let filter = NDKFilter(ids: [eventId])
        await performFetch(eventId: eventId, filter: filter, bech32Relays: nil, tagRelayHint: relayHint, pubkeyHint: pubkeyHint)
    }

    private func performFetch(
        eventId: String,
        filter: NDKFilter,
        bech32Relays: [String]?,
        tagRelayHint: String?,
        pubkeyHint: String?
    ) async {
        guard let ndk else { return }

        // Check cache first
        let cachedEvent = await ndk.cache.getEvent(id: eventId)

        if let cachedEvent {
            // Set cached event immediately
            self.event = cachedEvent

            // For non-replaceable events, we have the canonical version - skip network
            if !cachedEvent.isReplaceable && !cachedEvent.isParameterizedReplaceable {
                self.isLoading = false
                return
            }
        }

        // Select relays using priority: bech32 hints > tag hints > outbox > all connected
        let relays = await selectRelays(
            bech32Relays: bech32Relays,
            tagRelayHint: tagRelayHint,
            pubkeyHint: pubkeyHint
        )

        // Create subscription for network fetch
        let subscription = ndk.subscribe(
            filter: filter,
            maxAge: 0,
            cachePolicy: .cacheWithNetwork,
            relays: relays.isEmpty ? nil : relays,
            closeOnEose: true
        )

        self.subscription = subscription

        let cancellation = self.cancellation

        Task { [weak self] in
            for await newEvent in subscription.events {
                guard !cancellation.isCancelled else { break }
                guard let self else { break }

                await self.handleEvent(newEvent)
            }

            await MainActor.run { [weak self] in
                self?.isLoading = false
            }
        }
    }

    // MARK: - Event Handling

    private func handleEvent(_ newEvent: NDKEvent) async {
        if let currentEvent = event {
            // Only update if newer (for replaceable events)
            if newEvent.createdAt > currentEvent.createdAt {
                self.event = newEvent
            }
        } else {
            // First event
            self.event = newEvent
        }
    }

    // MARK: - Helper Methods

    /// Extract hints from NIP-10 tag: ["e", "event-id", "relay-hint", "marker", "pubkey-hint"]
    private func extractHintsFromTag(_ tag: Tag) -> (eventId: String?, relayHint: String?, pubkeyHint: String?) {
        guard tag.first == "e", tag.count >= 2 else {
            return (nil, nil, nil)
        }

        let eventId = tag[1]
        let relayHint = tag.count > 2 && !tag[2].isEmpty ? tag[2] : nil
        let pubkeyHint = tag.count > 4 && !tag[4].isEmpty ? tag[4] : nil

        return (eventId, relayHint, pubkeyHint)
    }

    /// Select relays using priority: bech32 > tag > outbox > all connected
    private func selectRelays(
        bech32Relays: [String]?,
        tagRelayHint: String?,
        pubkeyHint: String?
    ) async -> Set<String> {
        guard let ndk else { return [] }

        var relays = Set<String>()

        // Priority 1: Bech32 relay hints
        if let bech32Relays, !bech32Relays.isEmpty {
            relays.formUnion(bech32Relays)
        }

        // Priority 2: Tag relay hint
        if let tagRelay = tagRelayHint, !tagRelay.isEmpty {
            relays.insert(tagRelay)
        }

        // Priority 3: Outbox model with pubkey hint
        if relays.isEmpty, let pubkeyHint {
            do {
                if let outboxItem = try await ndk.outbox.getRelaysFor(pubkey: pubkeyHint, maxAge: TimeConstants.day, type: .write) {
                    let writeRelayUrls = outboxItem.writeRelays.map { $0.url }
                    relays.formUnion(writeRelayUrls)
                }
            } catch {
                // Outbox lookup failed, continue with fallback
            }
        }

        // Priority 4: Return empty set to use all connected relays (default behavior)
        return relays
    }
}

/// Thread-safe cancellation handle that can be accessed from deinit
private final class CancellationHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var _isCancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isCancelled
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        _isCancelled = true
    }
}
