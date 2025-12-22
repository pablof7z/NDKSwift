import Foundation
import Observation

/// Defines how the cache should be used for data requests
public enum CachePolicy: Sendable {
    /// Return cached data if available and fresh, otherwise fetch from network
    case cacheWithNetwork
    /// Only return data from the cache; never hit the network
    case cacheOnly
    /// Always fetch from the network, ignoring any cached data
    case networkOnly
}

/// Relay-level update information
public enum RelayUpdate: Sendable {
    /// Event received from a specific relay
    case event(NDKEvent, relay: String)
    /// End of stored events from a specific relay
    case eose(relay: String)
    /// Aggregated EOSE - all or enough relays have sent EOSE
    case aggregatedEose
    /// Subscription closed on a specific relay
    case closed(relay: String)
}

/// Primary API for declarative data access in NDKSwift
/// Automatically manages subscriptions, caching, and lifecycle
///
/// Thread Safety: This class uses internal actor isolation via `SubscriptionStateManager`
/// to protect mutable state. All mutable properties (filter, task, requirementHandle) are
/// accessed through the actor, ensuring thread-safe operations.
@Observable
public final class NDKSubscription<T: Sendable>: @unchecked Sendable {
    /// Automatically deduplicated and sorted (by default) accumulator of events
    public var data: [T] {
        sortedData.map { $0.event }
    }

    private var sortedData: [(event: T, timestamp: Timestamp)] = []

    /// AsyncStream for consuming event batches as they arrive
    /// Batches are yielded directly from cache (bulk) or network (single-element)
    public let events: AsyncStream<[T]>
    private let eventsContinuation: AsyncStream<[T]>.Continuation

    /// Relay-level updates (events, EOSE, closed) - opt-in via includeRelayUpdates parameter
    public let relayUpdates: AsyncStream<RelayUpdate>?
    private let relayUpdatesContinuation: AsyncStream<RelayUpdate>.Continuation?

    private let ndk: NDK
    private let transform: @Sendable (NDKEvent) -> T?
    private let maxAge: TimeInterval
    private let cachePolicy: CachePolicy
    private let relays: Set<RelayURL>?
    private let exclusiveRelays: Bool
    private let closeOnEose: Bool
    private let groupable: Bool
    private let groupableDelay: TimeInterval?
    private let groupableDelayType: NDKSubscriptionDelayType?
    private let correlationId: String
    private let subscriptionId: String?
    private let sorted: Bool

    /// Actor-protected mutable state for thread safety
    private let stateManager: SubscriptionStateManager

    /// Thread-safe cancellation handle for deinit
    private let cancellation = CancellationHandle()

    /// Thread-safe set of processed event IDs (protected via actor)
    private let processedEventIds = ProcessedEventIds()

    /// Actor that manages mutable subscription state in a thread-safe manner
    private actor SubscriptionStateManager {
        var filter: NDKFilter
        var task: Task<Void, Never>?
        var requirementHandle: NDKSubscriptionRequirementHandle?

        init(filter: NDKFilter) {
            self.filter = filter
        }

        func setFilter(_ newFilter: NDKFilter) {
            filter = newFilter
        }

        func getFilter() -> NDKFilter {
            filter
        }

        func setTask(_ newTask: Task<Void, Never>?) {
            task?.cancel()
            task = newTask
        }

        func cancelTask() {
            task?.cancel()
            task = nil
        }

        func setRequirementHandle(_ handle: NDKSubscriptionRequirementHandle?) {
            requirementHandle = handle
        }

        func getRequirementHandle() -> NDKSubscriptionRequirementHandle? {
            requirementHandle
        }

        func cancelRequirement() async {
            await requirementHandle?.cancel()
            requirementHandle = nil
        }
    }

    /// Thread-safe cancellation flag for safe deinit
    private final class CancellationHandle: @unchecked Sendable {
        private let lock = NSLock()
        private var _isCancelled = false

        var isCancelled: Bool {
            lock.withLock { _isCancelled }
        }

        func cancel() {
            lock.withLock { _isCancelled = true }
        }
    }

    private actor ProcessedEventIds {
        private var ids: Set<String> = []

        func contains(_ id: String) -> Bool {
            ids.contains(id)
        }

        func insert(_ id: String) {
            ids.insert(id)
        }

        func clear() {
            ids.removeAll()
        }
    }

    /// Initialize a data source for NDKEvent objects
    public convenience init(
        ndk: NDK,
        filter: NDKFilter,
        maxAge: TimeInterval = 0,
        cachePolicy: CachePolicy = .cacheWithNetwork,
        relays: Set<RelayURL>? = nil,
        exclusiveRelays: Bool = false,
        subscriptionId: String? = nil,
        closeOnEose: Bool = false,
        sorted: Bool = true,
        includeRelayUpdates: Bool = false
    ) where T == NDKEvent {
        self.init(
            ndk: ndk,
            filter: filter,
            maxAge: maxAge,
            cachePolicy: cachePolicy,
            relays: relays,
            exclusiveRelays: exclusiveRelays,
            subscriptionId: subscriptionId,
            closeOnEose: closeOnEose,
            sorted: sorted,
            includeRelayUpdates: includeRelayUpdates,
            transform: { @Sendable in $0 }
        )
    }

    /// Initialize a data source with custom transform
    /// - Parameters:
    ///   - ndk: The NDK instance to use for fetching data
    ///   - filter: The NDKFilter describing the data requirement
    ///   - maxAge: Maximum age of cached data to consider fresh (in seconds).
    ///             0 = keep subscription open for real-time updates.
    ///             >0 = use cache if fresh enough, otherwise fetch and close after EOSE
    ///   - cachePolicy: Defines how the cache should be used for this request
    ///   - relays: Optional set of specific relay URLs to query
    ///   - subscriptionId: Optional custom subscription ID to use (for debugging/tracing)
    ///   - sorted: Whether to automatically sort events by created_at (default: true)
    ///   - includeRelayUpdates: Whether to include relay-level updates stream (default: false)
    ///   - transform: Optional transform to convert NDKEvent to custom type
    public init(
        ndk: NDK,
        filter: NDKFilter,
        maxAge: TimeInterval = 0,
        cachePolicy: CachePolicy = .cacheWithNetwork,
        relays: Set<RelayURL>? = nil,
        exclusiveRelays: Bool = false,
        subscriptionId: String? = nil,
        closeOnEose: Bool = false,
        sorted: Bool = true,
        includeRelayUpdates: Bool = false,
        transform: @escaping @Sendable (NDKEvent) -> T?
    ) {
        self.ndk = ndk
        self.stateManager = SubscriptionStateManager(filter: filter)
        self.transform = transform
        self.maxAge = maxAge
        self.cachePolicy = cachePolicy
        self.relays = relays
        self.exclusiveRelays = exclusiveRelays
        self.closeOnEose = closeOnEose
        self.sorted = sorted
        groupable = true
        groupableDelay = nil
        groupableDelayType = nil
        correlationId = IDGenerator.randomId(length: 8)
        self.subscriptionId = subscriptionId

        NDKLogger.log(.trace, category: .subscription, "NDKSubscription init - filter: \(filter), maxAge: \(maxAge), cachePolicy: \(cachePolicy), sorted: \(sorted), includeRelayUpdates: \(includeRelayUpdates)", correlationId: correlationId)

        // Set up the AsyncStream for event batches
        var continuation: AsyncStream<[T]>.Continuation!
        events = AsyncStream { cont in
            continuation = cont
        }
        eventsContinuation = continuation

        // Set up the AsyncStream for relay updates (opt-in)
        if includeRelayUpdates {
            var relayUpdatesCont: AsyncStream<RelayUpdate>.Continuation!
            relayUpdates = AsyncStream { cont in
                relayUpdatesCont = cont
            }
            relayUpdatesContinuation = relayUpdatesCont
        } else {
            relayUpdates = nil
            relayUpdatesContinuation = nil
        }

        // Start observing immediately
        let manager = stateManager
        let observeTask = Task { [weak self] in
            guard let self = self else { return }
            await self.startObserving()
        }
        Task { await manager.setTask(observeTask) }
    }

    /// Initialize a data source with custom options
    /// - Parameters:
    ///   - ndk: The NDK instance
    ///   - filter: The NDKFilter describing the data requirement
    ///   - options: Subscription configuration options
    ///   - sorted: Whether to automatically sort events by created_at (default: true)
    ///   - includeRelayUpdates: Whether to include relay-level updates stream (default: false)
    ///   - transform: Optional transform to convert NDKEvent to custom type
    public init(
        ndk: NDK,
        filter: NDKFilter,
        options: NDKSubscriptionOptions,
        sorted: Bool = true,
        includeRelayUpdates: Bool = false,
        transform: @escaping @Sendable (NDKEvent) -> T? = { $0 as? T }
    ) {
        self.ndk = ndk
        self.stateManager = SubscriptionStateManager(filter: filter)
        self.transform = transform
        maxAge = options.maxAge
        cachePolicy = options.cachePolicy
        relays = options.relays
        exclusiveRelays = options.exclusiveRelays
        closeOnEose = options.closeOnEose ?? false
        self.sorted = sorted
        groupable = options.groupable
        groupableDelay = options.groupableDelay
        groupableDelayType = options.groupableDelayType
        correlationId = IDGenerator.randomId(length: 8)
        subscriptionId = options.subscriptionId

        NDKLogger.log(.trace, category: .subscription, "NDKSubscription init with options - filter: \(filter), maxAge: \(maxAge), cachePolicy: \(cachePolicy), sorted: \(sorted), includeRelayUpdates: \(includeRelayUpdates)", correlationId: correlationId)

        // Set up the AsyncStream for event batches
        var continuation: AsyncStream<[T]>.Continuation!
        events = AsyncStream { cont in
            continuation = cont
        }
        eventsContinuation = continuation

        // Set up the AsyncStream for relay updates (opt-in)
        if includeRelayUpdates {
            var relayUpdatesCont: AsyncStream<RelayUpdate>.Continuation!
            relayUpdates = AsyncStream { cont in
                relayUpdatesCont = cont
            }
            relayUpdatesContinuation = relayUpdatesCont
        } else {
            relayUpdates = nil
            relayUpdatesContinuation = nil
        }

        // Start observing immediately
        let manager = stateManager
        let observeTask = Task { [weak self] in
            guard let self = self else { return }
            await self.startObserving()
        }
        Task { await manager.setTask(observeTask) }
    }

    deinit {
        cancellation.cancel()
        eventsContinuation.finish()
        relayUpdatesContinuation?.finish()
        let manager = stateManager
        Task {
            await manager.cancelTask()
            await manager.cancelRequirement()
        }
    }

    private func startObserving() async {
        let filter = await stateManager.getFilter()
        NDKLogger.log(.info, category: .subscription, "NDKSubscription.startObserving() called - filter: \(filter), subscriptionId: \(subscriptionId ?? "auto")", correlationId: correlationId)

        // Use the data requirement manager
        let requirementManager = ndk.dataRequirementManager
        NDKLogger.log(.debug, category: .subscription, "Using dataRequirementManager, registering requirement", correlationId: correlationId)

        let (handle, eventStream, relayUpdateStream) = await requirementManager.registerRequirement(
            filter: filter,
            maxAge: maxAge,
            cachePolicy: cachePolicy,
            relays: relays,
            exclusiveRelays: exclusiveRelays,
            subscriptionId: subscriptionId,
            closeOnEose: closeOnEose,
            isGroupable: groupable,
            groupableDelay: groupableDelay,
            groupableDelayType: groupableDelayType
        )
        await stateManager.setRequirementHandle(handle)

        // Process event batches from the stream
        Task { [weak self] in
            guard let self = self else { return }
            for await batch in eventStream {
                await self.handleEvents(batch)
            }
        }

        // Process relay updates from the stream (only if opt-in)
        if relayUpdatesContinuation != nil {
            Task { [weak self] in
                guard let self = self else { return }
                for await update in relayUpdateStream {
                    self.relayUpdatesContinuation?.yield(update)
                }
            }
        }

        NDKLogger.log(.trace, category: .subscription, "Requirement registered with handle", correlationId: correlationId)
    }

    // MARK: - Event Handling

    /// Handle a batch of events
    /// Updates data array directly - automatically deduplicates and sorts (if enabled)
    private func handleEvents(_ events: [NDKEvent]) async {
        var newTransformed: [(event: T, timestamp: Timestamp)] = []

        for event in events {
            // Check if we've already processed this event (thread-safe via actor)
            let alreadyProcessed = await processedEventIds.contains(event.id)
            if alreadyProcessed { continue }
            await processedEventIds.insert(event.id)

            if let transformed = transform(event) {
                newTransformed.append((event: transformed, timestamp: event.createdAt))
            } else {
                NDKLogger.log(.debug, category: .subscription, "[NDKSubscription] Transform failed - event not added to data - id: \(event.id.prefix(10)), correlationId: \(correlationId)")
            }
        }

        guard !newTransformed.isEmpty else { return }

        // Yield batch to AsyncStream (for programmatic consumers)
        eventsContinuation.yield(newTransformed.map { $0.event })

        // Update data array with automatic sorting
        if sorted {
            // Insert in sorted order by timestamp
            for item in newTransformed {
                let insertIndex = sortedData.firstIndex { $0.timestamp < item.timestamp } ?? sortedData.endIndex
                sortedData.insert(item, at: insertIndex)
            }
        } else {
            // Just append
            sortedData.append(contentsOf: newTransformed)
        }
    }

    /// Handle relay-level updates (EOSE, subscription status, etc)
    /// This needs to be called by the internal subscription system
    public func handleRelayUpdate(_ update: RelayUpdate) async {
        relayUpdatesContinuation?.yield(update)

        // Also process events directly (as single-element batch)
        if case let .event(event, _) = update {
            await handleEvents([event])
        }
    }

    /// Manually refresh the data
    public func refresh() async {
        NDKLogger.log(.info, category: .subscription, "Refreshing data source", correlationId: correlationId)
        sortedData.removeAll()
        await processedEventIds.clear()

        if let handle = await stateManager.getRequirementHandle() {
            NDKLogger.log(.trace, category: .subscription, "Releasing existing requirement handle", correlationId: correlationId)
            await handle.cancel()
        }
        await stateManager.setRequirementHandle(nil)

        NDKLogger.log(.trace, category: .subscription, "Restarting observation", correlationId: correlationId)
        await startObserving()
    }

    // MARK: - One-Shot Query Conveniences

    /// Collect all events until timeout (convenience for one-shot queries)
    /// - Parameters:
    ///   - timeout: Maximum time to wait (default: 10 seconds)
    ///   - limit: Maximum number of events to collect (nil = unlimited)
    /// - Returns: Array of collected events
    ///
    /// Note: This is a convenience method for request-response patterns.
    /// For ongoing subscriptions, use the `events` or `data` streams directly.
    public func collect(timeout: TimeInterval = 10.0, limit: Int? = nil) async -> [T] {
        var collected: [T] = []

        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: UInt64(timeout * Double(TimeConstants.nanosecondsPerSecond)))
        }

        for await batch in events {
            collected.append(contentsOf: batch)
            if let limit = limit, collected.count >= limit {
                break
            }
            if timeoutTask.isCancelled {
                break
            }
        }

        timeoutTask.cancel()
        return collected
    }

    /// Wait for the first event to arrive (convenience for one-shot queries)
    /// - Parameters:
    ///   - timeout: Maximum time to wait (default: 10 seconds)
    /// - Returns: The first event, or nil if timeout
    ///
    /// Note: This is a convenience method for request-response patterns.
    /// For ongoing subscriptions, use the `events` or `data` streams directly.
    public func first(timeout: TimeInterval = NetworkConstants.timeoutRelayInfo) async -> T? {
        // If we already have data, return the first item
        if let firstItem = data.first {
            return firstItem
        }

        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: UInt64(timeout * Double(TimeConstants.nanosecondsPerSecond)))
        }

        for await batch in events {
            if let first = batch.first {
                timeoutTask.cancel()
                return first
            }
            if timeoutTask.isCancelled {
                return nil
            }
        }

        timeoutTask.cancel()
        return nil
    }

    // MARK: - Private Helper Methods

    /// Fetch events from cache
    private func fetchFromCache() async -> [NDKEvent]? {
        // Check if data is already available from existing load
        if !sortedData.isEmpty {
            return sortedData.compactMap { $0.event as? NDKEvent }
        }
        return nil
    }

    /// Process cached events as a batch
    private func processCachedEvents(_ events: [NDKEvent]) async {
        await handleEvents(events)
    }

    /// Process fetched events as a batch
    private func processFetchedEvents(_ events: [NDKEvent]) async {
        await handleEvents(events)
    }

    /// Update the filter for this data source
    /// - Parameter newFilter: The new filter to apply
    /// - Note: This method cancels the current subscription and starts a new one
    ///
    /// ## Usage
    /// ```swift
    /// let subscription = ndk.subscribe(filter: NDKFilter(kinds: [1]))
    ///
    /// // Later, update to show only events from specific authors
    /// await subscription.updateFilter(NDKFilter(kinds: [1], authors: ["pubkey1", "pubkey2"]))
    /// ```
    public func updateFilter(_ newFilter: NDKFilter) async {
        // Update the filter property
        await stateManager.setFilter(newFilter)

        // Cancel current task
        await stateManager.cancelTask()

        // Clear processed events (thread-safe via actor)
        await processedEventIds.clear()

        // Clear current data
        sortedData.removeAll()

        // Remove old requirement if exists
        await stateManager.cancelRequirement()

        // Start new task with updated filter
        let manager = stateManager
        let newTask = Task { [weak self] in
            guard let self = self else { return }
            await self.fetchAndSubscribe(filter: newFilter)
        }
        await manager.setTask(newTask)
    }

    /// Helper method to fetch and subscribe with a given filter
    private func fetchAndSubscribe(filter: NDKFilter) async {
        switch cachePolicy {
        case .cacheOnly:
            if let cachedEvents = await fetchFromCache() {
                await processCachedEvents(cachedEvents)
            }

        case .cacheWithNetwork:
            if let cachedEvents = await fetchFromCache() {
                await processCachedEvents(cachedEvents)
            }

            // For cache with network, always subscribe for continuous updates
            await subscribeToEvents(filter: filter)

        case .networkOnly:
            // For network only, subscribe for events
            await subscribeToEvents(filter: filter)
        }
    }

    /// Subscribe to events with the given filter
    private func subscribeToEvents(filter: NDKFilter) async {
        let subscription = NDKSubscription<NDKEvent>(
            ndk: ndk,
            filter: filter,
            maxAge: 0,
            cachePolicy: cachePolicy,
            relays: relays,
            subscriptionId: subscriptionId,
            sorted: sorted,
            includeRelayUpdates: relayUpdatesContinuation != nil
        )

        // Process event batches from the nested subscription
        for await batch in subscription.events {
            await handleEvents(batch)
        }
    }
}
