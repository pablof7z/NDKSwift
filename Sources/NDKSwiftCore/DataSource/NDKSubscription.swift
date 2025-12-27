import Foundation

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
    /// Subscription activated on a relay with specific filter
    case subscriptionActivated(relay: String, kinds: [Int], authorCount: Int)
}

/// Pure streaming subscription - no accumulation
/// Use NDKFeed for UI accumulation of events
///
/// Thread Safety: This class uses internal actor isolation via `SubscriptionStateManager`
/// to protect mutable state. All mutable properties (filter, task, requirementHandle) are
/// accessed through the actor, ensuring thread-safe operations.
public final class NDKSubscription<T: Sendable>: Sendable {
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
        groupable = true
        groupableDelay = nil
        groupableDelayType = nil
        correlationId = IDGenerator.randomId(length: 8)
        self.subscriptionId = subscriptionId

        NDKLogger.log(.trace, category: .subscription, "NDKSubscription init - filter: \(filter), maxAge: \(maxAge), cachePolicy: \(cachePolicy), includeRelayUpdates: \(includeRelayUpdates)", correlationId: correlationId)

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
    ///   - includeRelayUpdates: Whether to include relay-level updates stream (default: false)
    ///   - transform: Optional transform to convert NDKEvent to custom type
    public init(
        ndk: NDK,
        filter: NDKFilter,
        options: NDKSubscriptionOptions,
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
        groupable = options.groupable
        groupableDelay = options.groupableDelay
        groupableDelayType = options.groupableDelayType
        correlationId = IDGenerator.randomId(length: 8)
        subscriptionId = options.subscriptionId

        NDKLogger.log(.trace, category: .subscription, "NDKSubscription init with options - filter: \(filter), maxAge: \(maxAge), cachePolicy: \(cachePolicy), includeRelayUpdates: \(includeRelayUpdates)", correlationId: correlationId)

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

    /// Handle a batch of events - deduplicate and forward to stream
    private func handleEvents(_ events: [NDKEvent]) async {
        var newTransformed: [T] = []

        for event in events {
            // Check if we've already processed this event (thread-safe via actor)
            let alreadyProcessed = await processedEventIds.contains(event.id)
            if alreadyProcessed { continue }
            await processedEventIds.insert(event.id)

            if let transformed = transform(event) {
                newTransformed.append(transformed)
            } else {
                NDKLogger.log(.debug, category: .subscription, "[NDKSubscription] Transform failed - event not forwarded - id: \(event.id.prefix(10)), correlationId: \(correlationId)")
            }
        }

        guard !newTransformed.isEmpty else { return }

        // Yield batch to AsyncStream
        eventsContinuation.yield(newTransformed)
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

    /// Manually refresh the subscription
    public func refresh() async {
        NDKLogger.log(.info, category: .subscription, "Refreshing subscription", correlationId: correlationId)
        await processedEventIds.clear()

        if let handle = await stateManager.getRequirementHandle() {
            NDKLogger.log(.trace, category: .subscription, "Releasing existing requirement handle", correlationId: correlationId)
            await handle.cancel()
        }
        await stateManager.setRequirementHandle(nil)

        NDKLogger.log(.trace, category: .subscription, "Restarting observation", correlationId: correlationId)
        await startObserving()
    }

    /// Update the filter for this subscription
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

        // Remove old requirement if exists
        await stateManager.cancelRequirement()

        // Start new observation with updated filter
        await startObserving()
    }
}

// MARK: - EOSE-based collection helper

public extension NDK {
    /// Collect events until EOSE is received from relays
    /// This is the proper way to fetch initial data - waits for relay EOSE signal, not arbitrary timeout
    /// - Parameters:
    ///   - filter: The filter for events
    ///   - maxAge: Maximum age for cached data
    ///   - cachePolicy: Cache policy to use
    ///   - relays: Optional specific relays to query
    ///   - exclusiveRelays: If true, only use specified relays
    ///   - timeout: Fallback timeout in case relays don't send EOSE
    /// - Returns: Array of events received before EOSE
    func fetchEvents(
        filter: NDKFilter,
        maxAge: TimeInterval = 0,
        cachePolicy: CachePolicy = .cacheWithNetwork,
        relays: Set<RelayURL>? = nil,
        exclusiveRelays: Bool = false,
        timeout: TimeInterval = 10.0
    ) async -> [NDKEvent] {
        var collected: [NDKEvent] = []

        let subscription = NDKSubscription<NDKEvent>(
            ndk: self,
            filter: filter,
            maxAge: maxAge,
            cachePolicy: cachePolicy,
            relays: relays,
            exclusiveRelays: exclusiveRelays,
            includeRelayUpdates: true
        )

        // Use a task group to race between event collection and EOSE/timeout
        await withTaskGroup(of: Void.self) { group in
            // Task to collect events
            group.addTask {
                for await batch in subscription.events {
                    collected.append(contentsOf: batch)
                }
            }

            // Task to wait for EOSE or timeout
            group.addTask {
                guard let relayUpdates = subscription.relayUpdates else {
                    try? await Task.sleep(nanoseconds: UInt64(timeout * Double(TimeConstants.nanosecondsPerSecond)))
                    return
                }

                for await update in relayUpdates {
                    if case .aggregatedEose = update {
                        return
                    }
                }
            }

            // Wait for EOSE task to complete, then cancel the collection task
            await group.next()
            group.cancelAll()
        }

        return collected
    }
}
