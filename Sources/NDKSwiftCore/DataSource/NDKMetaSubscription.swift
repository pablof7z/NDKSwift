import Foundation
import Observation

/// Sort options for NDKMetaSubscription
public enum NDKMetaSubscriptionSort: Sendable, Equatable {
    /// Sort by content creation time (newest first)
    case time
    /// Sort by number of interactions (most engaged first)
    case count
    /// Sort by most recent interaction (freshest activity first)
    case tagTime
    /// Sort by author diversity (broadest reach first)
    case uniqueAuthors
}

/// Actor that manages all mutable state for NDKMetaSubscription
/// This provides thread-safe access to internal state and task lifecycle
@available(iOS 17.0, macOS 14.0, *)
private actor MetaSubscriptionStateManager {
    var targetEvents: [String: NDKEvent] = [:]
    var pointersByTarget: [String: [NDKEvent]] = [:]
    var pendingReferences: Set<String> = []
    var processingTask: Task<Void, Never>?
    var fetchDebounceTask: Task<Void, Never>?
    var pointerSubscription: NDKSubscription<NDKEvent>?

    func getPointers(for tagAddress: String) -> [NDKEvent] {
        pointersByTarget[tagAddress] ?? []
    }

    func addPointer(_ pointer: NDKEvent, for address: String) {
        var pointers = pointersByTarget[address] ?? []
        if !pointers.contains(where: { $0.id == pointer.id }) {
            pointers.append(pointer)
            pointersByTarget[address] = pointers
        }
    }

    func hasTarget(_ address: String) -> Bool {
        targetEvents[address] != nil
    }

    func addPendingReference(_ ref: String) {
        pendingReferences.insert(ref)
    }

    func takePendingReferences() -> Set<String> {
        let refs = pendingReferences
        pendingReferences.removeAll()
        return refs
    }

    func setTarget(_ event: NDKEvent, for address: String) {
        targetEvents[address] = event
    }

    func getAllTargetEvents() -> [NDKEvent] {
        Array(targetEvents.values)
    }

    func getAllPointers() -> [String: [NDKEvent]] {
        pointersByTarget
    }

    func clear() {
        targetEvents.removeAll()
        pointersByTarget.removeAll()
        pendingReferences.removeAll()
    }

    func setProcessingTask(_ task: Task<Void, Never>?) {
        processingTask = task
    }

    func setFetchDebounceTask(_ task: Task<Void, Never>?) {
        fetchDebounceTask = task
    }

    func cancelFetchDebounceTask() {
        fetchDebounceTask?.cancel()
    }

    func setPointerSubscription(_ subscription: NDKSubscription<NDKEvent>?) {
        pointerSubscription = subscription
    }

    func stop() {
        processingTask?.cancel()
        processingTask = nil
        fetchDebounceTask?.cancel()
        fetchDebounceTask = nil
        pointerSubscription = nil
    }
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
/// let feed = await ndk.metaSubscribe(
///     filter: NDKFilter(kinds: [6, 16], authors: follows),
///     sort: .tagTime
/// )
///
/// // In SwiftUI
/// ForEach(feed.events) { event in
///     PostCard(event: event)
///         .task {
///             let reposters = await feed.eventsTagging(event)
///             // Update repost count
///         }
/// }
/// ```
@available(iOS 17.0, macOS 14.0, *)
@Observable
public final class NDKMetaSubscription {
    // MARK: - Public Properties

    /// The pointed-to events, sorted according to current sort mode
    @MainActor public private(set) var events: [NDKEvent] = []

    /// Whether EOSE has been received from the subscription
    @MainActor public private(set) var eosed: Bool = false

    /// Number of pointed-to events
    @MainActor public var count: Int { events.count }

    /// Current sort mode - changing this triggers an instant re-sort without refetching
    @MainActor public var sort: NDKMetaSubscriptionSort {
        didSet {
            if sort != oldValue {
                Task {
                    await updateSortedEvents()
                }
            }
        }
    }

    // MARK: - Private Properties

    private let ndk: NDK
    private let filter: NDKFilter
    private let options: NDKSubscriptionOptions

    /// Actor for thread-safe state management including task lifecycle
    private let stateManager = MetaSubscriptionStateManager()

    // MARK: - Initialization

    /// Create a new meta subscription
    /// - Parameters:
    ///   - ndk: The NDK instance
    ///   - filter: Filter for pointer events (reposts, zaps, comments, etc.)
    ///   - sort: How to sort the pointed-to events
    ///   - options: Subscription options
    @MainActor
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

        Task {
            await self.start()
        }
    }

    deinit {
        let manager = stateManager
        Task {
            await manager.stop()
        }
    }

    // MARK: - Public Methods

    /// Get all interaction events pointing to a specific event
    /// - Parameter event: The event to get pointers for
    /// - Returns: Array of events that point to this event (via e-tag or a-tag)
    public func eventsTagging(_ event: NDKEvent) async -> [NDKEvent] {
        await stateManager.getPointers(for: event.tagAddress)
    }

    /// Stop the subscription
    public func stop() async {
        await stateManager.stop()
    }

    /// Clear all data and reset state
    @MainActor
    public func clear() async {
        await stateManager.clear()
        events = []
        eosed = false
    }

    // MARK: - Private Methods

    private func start() async {
        let subscription = ndk.subscribe(
            filter: filter,
            maxAge: options.maxAge,
            cachePolicy: options.cachePolicy,
            relays: options.relays,
            exclusiveRelays: options.exclusiveRelays,
            subscriptionId: options.subscriptionId,
            closeOnEose: options.closeOnEose,
            includeRelayUpdates: true
        )

        await stateManager.setPointerSubscription(subscription)

        let processingTask = Task { [weak self] in
            Task { [weak self] in
                guard let relayUpdates = subscription.relayUpdates else { return }
                for await update in relayUpdates {
                    guard let self = self else { return }
                    if case .aggregatedEose = update {
                        await MainActor.run {
                            self.eosed = true
                        }
                    }
                }
            }

            for await batch in subscription.events {
                for pointerEvent in batch {
                    guard let self = self else { return }
                    await self.handlePointerEvent(pointerEvent)
                }
            }
        }

        await stateManager.setProcessingTask(processingTask)
    }

    private func handlePointerEvent(_ pointerEvent: NDKEvent) async {
        let eTags = pointerEvent.tags(withName: "e")
        let aTags = pointerEvent.tags(withName: "a")

        var newReferences: [String] = []

        for eTag in eTags {
            guard eTag.count > 1 else { continue }
            let eventId = eTag[1]

            await stateManager.addPointer(pointerEvent, for: eventId)

            if await !stateManager.hasTarget(eventId) {
                await stateManager.addPendingReference(eventId)
                newReferences.append(eventId)
            }
        }

        for aTag in aTags {
            guard aTag.count > 1 else { continue }
            let address = aTag[1]

            await stateManager.addPointer(pointerEvent, for: address)

            if await !stateManager.hasTarget(address) {
                await stateManager.addPendingReference(address)
                newReferences.append(address)
            }
        }

        if newReferences.isEmpty {
            await updateSortedEvents()
        } else {
            scheduleFetch()
        }
    }

    private func scheduleFetch() {
        Task {
            await stateManager.cancelFetchDebounceTask()
            let task = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
                guard let self = self, !Task.isCancelled else { return }
                await self.fetchPendingReferences()
            }
            await stateManager.setFetchDebounceTask(task)
        }
    }

    private func fetchPendingReferences() async {
        let references = await stateManager.takePendingReferences()

        guard !references.isEmpty else { return }

        var eventIds: [String] = []
        var addresses: [String] = []

        for ref in references {
            if ref.contains(":") {
                addresses.append(ref)
            } else {
                eventIds.append(ref)
            }
        }

        var filters: [NDKFilter] = []

        if !eventIds.isEmpty {
            filters.append(NDKFilter(ids: eventIds))
        }

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

        for filter in filters {
            let subscription = ndk.subscribe(
                filter: filter,
                closeOnEose: true
            )

            let fetchedEvents = await subscription.collect(timeout: 5.0)

            for event in fetchedEvents {
                let tagAddr = event.tagAddress
                await stateManager.setTarget(event, for: tagAddr)

                if tagAddr != event.id {
                    await stateManager.setTarget(event, for: event.id)
                }
            }
        }

        await updateSortedEvents()
    }

    private func updateSortedEvents() async {
        var allEvents = await stateManager.getAllTargetEvents()
        let pointers = await stateManager.getAllPointers()
        let currentSort = await MainActor.run { self.sort }

        var seen = Set<String>()
        allEvents = allEvents.filter { event in
            if seen.contains(event.id) {
                return false
            }
            seen.insert(event.id)
            return true
        }

        switch currentSort {
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

        let sortedEvents = allEvents
        await MainActor.run {
            self.events = sortedEvents
        }
    }
}
