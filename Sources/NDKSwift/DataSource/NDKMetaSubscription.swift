import Foundation
import Observation

/// Sort options for NDKMetaSubscription
public enum NDKMetaSubscriptionSort: Sendable {
    /// Sort by content creation time (newest first)
    case time
    /// Sort by number of interactions (most engaged first)
    case count
    /// Sort by most recent interaction (freshest activity first)
    case tagTime
    /// Sort by author diversity (broadest reach first)
    case uniqueAuthors
}

/// A reactive subscription that returns events pointed to by e-tags and a-tags,
/// rather than the matching events themselves.
///
/// This is useful for:
/// - Discovery feeds ("trending in your network")
/// - Notifications (interactions pointing to your content)
/// - Article comments (finding discussed content)
///
/// ## Example
/// ```swift
/// // Show content reposted by people you follow
/// let feed = ndk.metaSubscribe(
///     filter: NDKFilter(kinds: [6, 16], authors: follows),
///     sort: .tagTime
/// )
///
/// // In SwiftUI
/// ForEach(feed.events) { event in
///     let reposters = feed.eventsTagging(event)
///     PostCard(event: event, repostedBy: reposters.count)
/// }
/// ```
@available(iOS 17.0, macOS 14.0, *)
@Observable
public final class NDKMetaSubscription: @unchecked Sendable {
    // MARK: - Public Properties

    /// The pointed-to events, sorted according to current sort mode
    public private(set) var events: [NDKEvent] = []

    /// Whether EOSE has been received from the subscription
    public private(set) var eosed: Bool = false

    /// Number of pointed-to events
    public var count: Int { events.count }

    /// Current sort mode - changing this triggers an instant re-sort without refetching
    public var sort: NDKMetaSubscriptionSort {
        didSet {
            if sort != oldValue {
                updateSortedEvents()
            }
        }
    }

    // MARK: - Private Properties

    private let ndk: NDK
    private let filter: NDKFilter
    private let options: NDKSubscriptionOptions

    /// Map of tagAddress -> pointed-to event
    private var targetEvents: [String: NDKEvent] = [:]

    /// Map of tagAddress -> array of pointer events
    private var pointersByTarget: [String: [NDKEvent]] = [:]

    /// The underlying subscription to pointer events
    private var pointerSubscription: NDKSubscription<NDKEvent>?

    /// Task for processing events
    private var processingTask: Task<Void, Never>?

    /// Batch of references to fetch
    private var pendingReferences: Set<String> = []

    /// Debounce task for batching fetches
    private var fetchDebounceTask: Task<Void, Never>?

    /// Lock for thread-safe access to internal state
    private let lock = NSLock()

    // MARK: - Initialization

    /// Create a new meta subscription
    /// - Parameters:
    ///   - ndk: The NDK instance
    ///   - filter: Filter for pointer events (reposts, zaps, comments, etc.)
    ///   - sort: How to sort the pointed-to events
    ///   - options: Subscription options
    public init(
        ndk: NDK,
        filter: NDKFilter,
        sort: NDKMetaSubscriptionSort = .tagTime,
        options: NDKSubscriptionOptions = .default
    ) {
        self.ndk = ndk
        self.filter = filter
        self.sort = sort
        self.options = options

        start()
    }

    deinit {
        stop()
    }

    // MARK: - Public Methods

    /// Get all interaction events pointing to a specific event
    /// - Parameter event: The event to get pointers for
    /// - Returns: Array of events that point to this event (via e-tag or a-tag)
    public func eventsTagging(_ event: NDKEvent) -> [NDKEvent] {
        lock.lock()
        defer { lock.unlock() }
        return pointersByTarget[event.tagAddress] ?? []
    }

    /// Stop the subscription
    public func stop() {
        processingTask?.cancel()
        processingTask = nil
        fetchDebounceTask?.cancel()
        fetchDebounceTask = nil
        pointerSubscription = nil
    }

    /// Clear all data and reset state
    public func clear() {
        lock.lock()
        targetEvents.removeAll()
        pointersByTarget.removeAll()
        pendingReferences.removeAll()
        lock.unlock()

        events = []
        eosed = false
    }

    // MARK: - Private Methods

    private func start() {
        // Subscribe to pointer events
        pointerSubscription = ndk.subscribe(
            filter: filter,
            maxAge: options.maxAge,
            cachePolicy: options.cachePolicy,
            relays: options.relays,
            exclusiveRelays: options.exclusiveRelays,
            subscriptionId: options.subscriptionId,
            closeOnEose: options.closeOnEose
        )

        guard let subscription = pointerSubscription else { return }

        // Process events as they arrive
        processingTask = Task { [weak self] in
            // Monitor for EOSE
            Task { [weak self] in
                for await update in subscription.relayUpdates {
                    guard let self = self else { return }
                    if case .aggregatedEose = update {
                        await MainActor.run {
                            self.eosed = true
                        }
                    }
                }
            }

            // Process pointer events
            for await pointerEvent in subscription.events {
                guard let self = self else { return }
                await self.handlePointerEvent(pointerEvent)
            }
        }
    }

    private func handlePointerEvent(_ pointerEvent: NDKEvent) async {
        // Extract e-tags and a-tags
        let eTags = pointerEvent.tags(withName: "e")
        let aTags = pointerEvent.tags(withName: "a")

        var newReferences: [String] = []

        lock.lock()

        // Process e-tags
        for eTag in eTags {
            guard eTag.count > 1 else { continue }
            let eventId = eTag[1]

            // Track the pointer relationship
            var pointers = pointersByTarget[eventId] ?? []
            if !pointers.contains(where: { $0.id == pointerEvent.id }) {
                pointers.append(pointerEvent)
                pointersByTarget[eventId] = pointers
            }

            // Queue for fetching if we don't have the target event
            if targetEvents[eventId] == nil {
                pendingReferences.insert(eventId)
                newReferences.append(eventId)
            }
        }

        // Process a-tags
        for aTag in aTags {
            guard aTag.count > 1 else { continue }
            let address = aTag[1]

            // Track the pointer relationship
            var pointers = pointersByTarget[address] ?? []
            if !pointers.contains(where: { $0.id == pointerEvent.id }) {
                pointers.append(pointerEvent)
                pointersByTarget[address] = pointers
            }

            // Queue for fetching if we don't have the target event
            if targetEvents[address] == nil {
                pendingReferences.insert(address)
                newReferences.append(address)
            }
        }

        lock.unlock()

        // If we already have the target events, just update the sort
        if newReferences.isEmpty {
            await MainActor.run {
                self.updateSortedEvents()
            }
        } else {
            // Debounce and batch fetch
            scheduleFetch()
        }
    }

    private func scheduleFetch() {
        fetchDebounceTask?.cancel()
        fetchDebounceTask = Task { [weak self] in
            // Small delay to batch multiple references
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            guard let self = self, !Task.isCancelled else { return }
            await self.fetchPendingReferences()
        }
    }

    private func fetchPendingReferences() async {
        lock.lock()
        let references = pendingReferences
        pendingReferences.removeAll()
        lock.unlock()

        guard !references.isEmpty else { return }

        // Separate event IDs from NIP-33 addresses
        var eventIds: [String] = []
        var addresses: [String] = []

        for ref in references {
            if ref.contains(":") {
                addresses.append(ref)
            } else {
                eventIds.append(ref)
            }
        }

        // Build filters
        var filters: [NDKFilter] = []

        if !eventIds.isEmpty {
            filters.append(NDKFilter(ids: eventIds))
        }

        // Group addresses by author for efficient querying
        if !addresses.isEmpty {
            var byAuthor: [String: (kinds: Set<Int>, dTags: Set<String>)] = [:]

            for addr in addresses {
                let parts = addr.split(separator: ":")
                guard parts.count >= 3 else { continue }

                let kindStr = String(parts[0])
                let pubkey = String(parts[1])
                let dTag = String(parts[2])

                guard let kind = Int(kindStr) else { continue }

                var entry = byAuthor[pubkey] ?? (kinds: Set<Int>(), dTags: Set<String>())
                entry.kinds.insert(kind)
                entry.dTags.insert(dTag)
                byAuthor[pubkey] = entry
            }

            for (pubkey, entry) in byAuthor {
                filters.append(NDKFilter(
                    authors: [pubkey],
                    kinds: Array(entry.kinds),
                    tags: ["d": entry.dTags]
                ))
            }
        }

        guard !filters.isEmpty else { return }

        // Fetch all referenced events
        for filter in filters {
            let subscription = ndk.subscribe(
                filter: filter,
                closeOnEose: true
            )

            let fetchedEvents = await subscription.collect(timeout: 5.0)

            lock.lock()
            for event in fetchedEvents {
                let tagAddr = event.tagAddress
                targetEvents[tagAddr] = event

                // Also store by event ID for e-tag lookups
                if tagAddr != event.id {
                    targetEvents[event.id] = event
                }
            }
            lock.unlock()
        }

        await MainActor.run {
            self.updateSortedEvents()
        }
    }

    private func updateSortedEvents() {
        lock.lock()
        var allEvents = Array(targetEvents.values)
        let pointers = pointersByTarget
        lock.unlock()

        // Remove duplicates (same event might be stored by both ID and address)
        var seen = Set<String>()
        allEvents = allEvents.filter { event in
            if seen.contains(event.id) {
                return false
            }
            seen.insert(event.id)
            return true
        }

        // Sort based on current mode
        switch sort {
        case .time:
            allEvents.sort { $0.createdAt > $1.createdAt }

        case .count:
            allEvents.sort { event1, event2 in
                let count1 = (pointers[event1.tagAddress]?.count ?? 0) + (pointers[event1.id]?.count ?? 0)
                let count2 = (pointers[event2.tagAddress]?.count ?? 0) + (pointers[event2.id]?.count ?? 0)
                return count1 > count2
            }

        case .tagTime:
            allEvents.sort { event1, event2 in
                let pointers1 = (pointers[event1.tagAddress] ?? []) + (pointers[event1.id] ?? [])
                let pointers2 = (pointers[event2.tagAddress] ?? []) + (pointers[event2.id] ?? [])
                let maxTime1 = pointers1.map { $0.createdAt }.max() ?? 0
                let maxTime2 = pointers2.map { $0.createdAt }.max() ?? 0
                return maxTime1 > maxTime2
            }

        case .uniqueAuthors:
            allEvents.sort { event1, event2 in
                let pointers1 = (pointers[event1.tagAddress] ?? []) + (pointers[event1.id] ?? [])
                let pointers2 = (pointers[event2.tagAddress] ?? []) + (pointers[event2.id] ?? [])
                let unique1 = Set(pointers1.map { $0.pubkey }).count
                let unique2 = Set(pointers2.map { $0.pubkey }).count
                return unique1 > unique2
            }
        }

        events = allEvents
    }
}
