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
public enum RelayUpdate {
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
@Observable
public final class NDKSubscription<T> {
    public private(set) var data: [T] = []
    public private(set) var isLoading: Bool = false
    public private(set) var error: Error?

    /// AsyncStream for consuming events as they arrive
    public let events: AsyncStream<T>
    private let eventsContinuation: AsyncStream<T>.Continuation

    /// Relay-level updates (events, EOSE, closed)
    public let relayUpdates: AsyncStream<RelayUpdate>
    private let relayUpdatesContinuation: AsyncStream<RelayUpdate>.Continuation

    private var filter: NDKFilter
    private let ndk: NDK
    private let transform: (NDKEvent) -> T?
    private let maxAge: TimeInterval
    private let cachePolicy: CachePolicy
    private let relays: Set<RelayURL>?
    private let exclusiveRelays: Bool
    private let closeOnEose: Bool
    private let groupable: Bool
    private let groupableDelay: TimeInterval?
    private let groupableDelayType: NDKSubscriptionDelayType?
    private var requirementHandle: NDKSubscriptionRequirementHandle?
    private var task: Task<Void, Never>?
    private let correlationId: String
    private let subscriptionId: String?

    /// Thread-safe set of processed event IDs (protected via actor)
    private let processedEventIds = ProcessedEventIds()

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

    /// Batch buffer for MainActor updates
    /// Accumulates events and flushes them in a single MainActor operation
    /// This eliminates UI flickering when loading bulk data from cache
    private var pendingBatch: [T] = []
    private var flushTask: Task<Void, Never>?

    /// Initialize a data source for NDKEvent objects
    public convenience init(
        ndk: NDK,
        filter: NDKFilter,
        maxAge: TimeInterval = 0,
        cachePolicy: CachePolicy = .cacheWithNetwork,
        relays: Set<RelayURL>? = nil,
        exclusiveRelays: Bool = false,
        subscriptionId: String? = nil,
        closeOnEose: Bool = false
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
            transform: { $0 }
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
        transform: @escaping (NDKEvent) -> T?
    ) {
        self.ndk = ndk
        self.filter = filter
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

        NDKLogger.log(.trace, category: .subscription, "🏗️ NDKSubscription init - filter: \(filter), maxAge: \(maxAge), cachePolicy: \(cachePolicy)", correlationId: correlationId)

        // Set up the AsyncStream for events
        var continuation: AsyncStream<T>.Continuation!
        events = AsyncStream { cont in
            continuation = cont
        }
        eventsContinuation = continuation

        // Set up the AsyncStream for relay updates
        var relayUpdatesCont: AsyncStream<RelayUpdate>.Continuation!
        relayUpdates = AsyncStream { cont in
            relayUpdatesCont = cont
        }
        relayUpdatesContinuation = relayUpdatesCont

        // Start observing immediately
        task = Task { [weak self] in
            guard let self = self else { return }
            await self.startObserving()
        }
    }

    /// Initialize a data source with custom options
    /// - Parameters:
    ///   - ndk: The NDK instance
    ///   - filter: The NDKFilter describing the data requirement
    ///   - options: Subscription configuration options
    ///   - transform: Optional transform to convert NDKEvent to custom type
    public init(
        ndk: NDK,
        filter: NDKFilter,
        options: NDKSubscriptionOptions,
        transform: @escaping (NDKEvent) -> T? = { $0 as? T }
    ) {
        self.ndk = ndk
        self.filter = filter
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

        NDKLogger.log(.trace, category: .subscription, "🏗️ NDKSubscription init with options - filter: \(filter), maxAge: \(maxAge), cachePolicy: \(cachePolicy)", correlationId: correlationId)

        // Set up the AsyncStream for events
        var continuation: AsyncStream<T>.Continuation!
        events = AsyncStream { cont in
            continuation = cont
        }
        eventsContinuation = continuation

        // Set up the AsyncStream for relay updates
        var relayUpdatesCont: AsyncStream<RelayUpdate>.Continuation!
        relayUpdates = AsyncStream { cont in
            relayUpdatesCont = cont
        }
        relayUpdatesContinuation = relayUpdatesCont

        // Start observing immediately
        task = Task { [weak self] in
            guard let self = self else { return }
            await self.startObserving()
        }
    }

    deinit {
        NDKLogger.log(.trace, category: .subscription, "🔚 NDKSubscription deinit - Cleaning up resources", correlationId: correlationId)
        task?.cancel()
        flushTask?.cancel()
        eventsContinuation.finish()
        relayUpdatesContinuation.finish()
        let handle = requirementHandle
        Task {
            await handle?.cancel()
        }
    }

    private func startObserving() async {
        NDKLogger.log(.info, category: .subscription, "🔍 NDKSubscription.startObserving() called - filter: \(filter), subscriptionId: \(subscriptionId ?? "auto")", correlationId: correlationId)

        isLoading = true
        error = nil

        // Use the data requirement manager
        let requirementManager = ndk.dataRequirementManager
        NDKLogger.log(.debug, category: .subscription, "✅ Using dataRequirementManager, registering requirement", correlationId: correlationId)

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
            requirementHandle = handle

            // Process events from the stream
            Task { [weak self] in
                guard let self = self else { return }
                for await event in eventStream {
                    await self.handleEvent(event)
                }
            }

            // Process relay updates from the stream
            Task { [weak self] in
                guard let self = self else { return }
                for await update in relayUpdateStream {
                    self.relayUpdatesContinuation.yield(update)
                }
            }

            NDKLogger.log(.trace, category: .subscription, "✅ Requirement registered with handle", correlationId: correlationId)

        isLoading = false
    }

    // MARK: - Event Handling

    private func handleEvent(_ event: NDKEvent) async {
        // Check if we've already processed this event (thread-safe via actor)
        let alreadyProcessed = await processedEventIds.contains(event.id)
        if !alreadyProcessed {
            await processedEventIds.insert(event.id)
        }

        guard !alreadyProcessed else {
            return
        }

        if let transformed = transform(event) {
            // Yield to AsyncStream immediately (for programmatic consumers)
            eventsContinuation.yield(transformed)

            // Add to pending batch for UI update
            pendingBatch.append(transformed)

            // Cancel previous flush task and schedule new one
            // Events arriving within 1ms get batched together
            flushTask?.cancel()
            flushTask = Task { [weak self] in
                // Wait 1ms for more events to arrive
                try? await Task.sleep(for: .milliseconds(1))
                await self?.flushBatch()
            }
        } else {
            NDKLogger.log(.debug, category: .subscription, "❌ [NDKSubscription] Transform failed - event not added to data - id: \(event.id.prefix(10)), correlationId: \(correlationId)")
        }
    }

    /// Flush pending batch to MainActor
    /// Updates the observable data array in a single operation
    private func flushBatch() async {
        guard !pendingBatch.isEmpty else { return }

        let batch = pendingBatch
        pendingBatch.removeAll()
        flushTask = nil

        // Single MainActor update for entire batch
        await MainActor.run {
            data.append(contentsOf: batch)
        }
    }

    /// Handle relay-level updates (EOSE, subscription status, etc)
    /// This needs to be called by the internal subscription system
    public func handleRelayUpdate(_ update: RelayUpdate) async {
        relayUpdatesContinuation.yield(update)

        // Also process events directly
        if case let .event(event, _) = update {
            await handleEvent(event)
        }
    }

    /// Manually refresh the data
    public func refresh() async {
        NDKLogger.log(.info, category: .subscription, "🔄 Refreshing data source", correlationId: correlationId)
        data.removeAll()
        await processedEventIds.clear()

        // Clear pending batch
        flushTask?.cancel()
        flushTask = nil
        pendingBatch.removeAll()

        if let handle = requirementHandle {
            NDKLogger.log(.trace, category: .subscription, "Releasing existing requirement handle", correlationId: correlationId)
            await handle.cancel()
        }
        requirementHandle = nil

        NDKLogger.log(.trace, category: .subscription, "Restarting observation", correlationId: correlationId)
        await startObserving()
    }

    // MARK: - Event-Driven Methods

    /// Wait for the first event to arrive
    /// - Parameters:
    ///   - timeout: Maximum time to wait (default: 10 seconds)
    /// - Returns: The first event, or nil if timeout/EOSE with no events
    public func first(timeout: TimeInterval = NetworkConstants.timeoutRelayInfo) async -> T? {
        // If we already have data, return the first item
        if let firstItem = data.first {
            return firstItem
        }

        return await withTaskGroup(of: T?.self) { group in
            // Timeout task
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * Double(TimeConstants.nanosecondsPerSecond)))
                return nil
            }

            // Event monitoring task
            group.addTask { [weak self] in
                guard let self = self else { return nil }

                // Create a new iterator to avoid consuming the main stream
                var iterator = self.events.makeAsyncIterator()
                return await iterator.next()
            }

            // EOSE monitoring task
            group.addTask { [weak self] in
                guard let self = self else { return nil }

                var activeRelays = Set<String>()
                var eoseReceived = Set<String>()

                for await update in self.relayUpdates {
                    switch update {
                    case .event:
                        // An event arrived, the event monitoring task will handle it
                        break

                    case let .eose(relay):
                        activeRelays.insert(relay)
                        eoseReceived.insert(relay)

                        // If all active relays sent EOSE and no events
                        if !activeRelays.isEmpty, activeRelays == eoseReceived, self.data.isEmpty {
                            return nil
                        }

                    case .aggregatedEose:
                        // Aggregated EOSE received with no events
                        if self.data.isEmpty {
                            return nil
                        }

                    case .closed:
                        break
                    }
                }

                return nil
            }

            // Return first non-nil result
            for await result in group {
                if result != nil {
                    group.cancelAll()
                    return result
                }
            }

            return nil
        }
    }

    /// Collect all events until EOSE or timeout
    /// - Parameters:
    ///   - timeout: Maximum time to wait if no EOSE received (default: 10 seconds)
    ///   - limit: Maximum number of events to collect (nil = unlimited)
    /// - Returns: Array of collected events
    ///
    /// ## Usage
    /// ```swift
    /// // Collect all text notes from the last hour
    /// let subscription = ndk.subscribe(filter: NDKFilter(kinds: [1]), maxAge: 3600)
    /// let events = await subscription.collect(timeout: 5.0)
    ///
    /// // Collect up to 100 events
    /// let limitedEvents = await subscription.collect(limit: 100)
    /// ```
    ///
    /// - Note: This method returns immediately when aggregated EOSE is received (using smart timeout logic from ndk-core)
    public func collect(timeout: TimeInterval = 10.0, limit: Int? = nil) async -> [T] {
        var collected: [T] = []

        await withTaskGroup(of: Void.self) { group in
            // Timeout task (only as fallback)
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * Double(TimeConstants.nanosecondsPerSecond)))
            }

            // Collection task
            group.addTask { [weak self] in
                guard let self = self else { return }

                var eventTask: Task<Void, Never>?

                // Start event collection
                eventTask = Task {
                    for await event in self.events {
                        collected.append(event)
                        if let limit = limit, collected.count >= limit {
                            break
                        }
                    }
                }

                // Monitor relay updates for aggregated EOSE
                for await update in self.relayUpdates {
                    switch update {
                    case .event:
                        // Events are handled by the event collection task
                        break

                    case .eose:
                        // Individual relay EOSE - handled by EOSETracker
                        break

                    case .aggregatedEose:
                        // All/enough relays have sent EOSE - we're done!
                        eventTask?.cancel()
                        return

                    case .closed:
                        eventTask?.cancel()
                        return
                    }
                }
            }

            // Wait for first task to complete
            await group.next()
            group.cancelAll()
        }

        return collected
    }

    /// Create an AsyncStream that emits events and completes on EOSE
    /// Useful for one-shot queries that need to process events as they arrive
    public var eventsUntilEOSE: AsyncStream<T> {
        AsyncStream { continuation in
            Task { [weak self] in
                guard let self = self else {
                    continuation.finish()
                    return
                }

                // Start forwarding events
                let eventTask = Task {
                    for await event in self.events {
                        continuation.yield(event)
                    }
                }

                // Monitor for aggregated EOSE
                for await update in self.relayUpdates {
                    switch update {
                    case .event:
                        // Events are handled by the event task
                        break

                    case .eose:
                        // Individual relay EOSE - handled by EOSETracker
                        break

                    case .aggregatedEose:
                        // All/enough relays have sent EOSE - complete the stream
                        eventTask.cancel()
                        continuation.finish()
                        return

                    case .closed:
                        eventTask.cancel()
                        continuation.finish()
                        return
                    }
                }

                continuation.finish()
            }
        }
    }

    // MARK: - Private Helper Methods

    /// Fetch events from cache
    private func fetchFromCache() async -> [NDKEvent]? {
        // Check if data is already available from existing load
        if !data.isEmpty {
            return data.compactMap { $0 as? NDKEvent }
        }
        return nil
    }

    /// Process cached events
    private func processCachedEvents(_ events: [NDKEvent]) async {
        for event in events {
            await handleEvent(event)
        }
    }

    /// Process fetched events
    private func processFetchedEvents(_ events: [NDKEvent]) async {
        for event in events {
            await handleEvent(event)
        }
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
        filter = newFilter

        // Cancel current task
        task?.cancel()

        // Clear processed events (thread-safe via actor)
        await processedEventIds.clear()

        // Clear pending batch
        flushTask?.cancel()
        flushTask = nil
        pendingBatch.removeAll()

        // Clear current data
        await MainActor.run {
            self.data.removeAll()
        }

        // Remove old requirement if exists
        if let handle = requirementHandle {
            await handle.cancel()
        }

        // Update the requirement handle for new filter
        // The requirement will be added when fetchAndSubscribe is called
        requirementHandle = nil

        // Start new task with updated filter
        task = Task { [weak self] in
            guard let self = self else { return }
            await self.fetchAndSubscribe(filter: newFilter)
        }
    }

    /// Helper method to fetch and subscribe with a given filter
    private func fetchAndSubscribe(filter: NDKFilter) async {
        await MainActor.run {
            self.isLoading = true
            self.error = nil
        }

        switch cachePolicy {
        case .cacheOnly:
            if let cachedEvents = await fetchFromCache() {
                await processCachedEvents(cachedEvents)
            }
            await MainActor.run {
                self.isLoading = false
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
            subscriptionId: subscriptionId
        )

        await MainActor.run {
            self.isLoading = false
        }

        // Process events from the nested subscription
        for await event in subscription.events {
            await handleEvent(event)
        }
    }
}
