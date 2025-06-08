import Foundation

/// Actor for managing subscription state in a thread-safe manner
actor SubscriptionState {
    private var activeRelays: Set<NDKRelay> = []

    func addRelay(_ relay: NDKRelay) {
        activeRelays.insert(relay)
    }

    func getAllRelays() -> Set<NDKRelay> {
        activeRelays
    }

    func removeAllRelays() -> Set<NDKRelay> {
        let relays = activeRelays
        activeRelays.removeAll()
        return relays
    }

    func contains(_ relay: NDKRelay) -> Bool {
        activeRelays.contains(relay)
    }

    var count: Int {
        activeRelays.count
    }
}

/// Subscription options
public struct NDKSubscriptionOptions {
    /// Whether to close the subscription on EOSE
    public var closeOnEose: Bool = false

    /// Cache strategy
    public var cacheStrategy: NDKCacheStrategy = .cacheFirst

    /// Maximum number of events to receive
    public var limit: Int?

    /// Timeout for the subscription
    public var timeout: TimeInterval?

    /// Specific relays to use for this subscription
    public var relays: Set<NDKRelay>?

    public init() {}
}

/// Cache strategy for subscriptions
public enum NDKCacheStrategy {
    case cacheFirst // Check cache first, then relays
    case cacheOnly // Only check cache
    case relayOnly // Only check relays
    case parallel // Check cache and relays in parallel
}

/// Update type for subscription stream
public enum NDKSubscriptionUpdate {
    case event(NDKEvent)
    case eose
    case error(Error)
}

/// Real implementation of NDKSubscription
public final class NDKSubscription: AsyncSequence {
    public typealias Element = NDKEvent
    /// Unique subscription ID
    public let id: String

    /// Filters for this subscription
    public let filters: [NDKFilter]

    /// Subscription options
    public let options: NDKSubscriptionOptions

    /// Reference to NDK instance
    public weak var ndk: NDK?

    
    /// Current subscription state
    public private(set) var state: NDKSubscriptionState = .pending

    /// Events received so far
    public private(set) var events: [NDKEvent] = []

    /// Whether EOSE has been received from all relays
    public private(set) var eoseReceived: Bool = false
    
    /// Track EOSE received from individual relays
    private var eoseReceivedFromRelays: Set<String> = []
    private let eoseReceivedLock = NSLock()

    /// Whether the subscription is active
    public private(set) var isActive: Bool = false

    /// Whether the subscription is closed
    public private(set) var isClosed: Bool = false

    /// Thread-safe relay state management
    private let relayState = SubscriptionState()

    /// Event deduplication - protected by lock
    private var receivedEventIds: Set<EventID> = []
    private let receivedEventIdsLock = NSLock()

    /// Timer for timeout
    private var timeoutTimer: Timer?

    /// The stream continuation for sending events
    private var continuation: AsyncStream<NDKEvent>.Continuation?
    
    /// The async stream of events
    private let stream: AsyncStream<NDKEvent>
    
    /// Update stream for those who want all updates (events, EOSE, errors)
    public let updates: AsyncStream<NDKSubscriptionUpdate>
    private var updateContinuation: AsyncStream<NDKSubscriptionUpdate>.Continuation?

    /// Events array lock
    private let eventsLock = NSLock()

    /// State locks
    private let stateLock = NSLock()
    
    /// Task that handles registration with the subscription manager
    internal var registrationTask: Task<Void, Never>?

    public init(
        id: String = String(Int.random(in: 100000...999999)),
        filters: [NDKFilter],
        options: NDKSubscriptionOptions = NDKSubscriptionOptions(),
        ndk: NDK? = nil
    ) {
        self.id = id
        self.filters = filters
        self.options = options
        self.ndk = ndk
        
        // Create the main event stream
        var streamContinuation: AsyncStream<NDKEvent>.Continuation?
        self.stream = AsyncStream<NDKEvent> { continuation in
            streamContinuation = continuation
        }
        self.continuation = streamContinuation
        
        // Create the update stream
        var updateStreamContinuation: AsyncStream<NDKSubscriptionUpdate>.Continuation?
        self.updates = AsyncStream<NDKSubscriptionUpdate> { continuation in
            updateStreamContinuation = continuation
        }
        self.updateContinuation = updateStreamContinuation

        setupTimeoutIfNeeded()
    }

    deinit {
        close()
    }

    // MARK: - AsyncSequence Conformance
    
    public struct AsyncIterator: AsyncIteratorProtocol {
        private var iterator: AsyncStream<NDKEvent>.AsyncIterator
        
        init(iterator: AsyncStream<NDKEvent>.AsyncIterator) {
            self.iterator = iterator
        }
        
        public mutating func next() async -> NDKEvent? {
            await iterator.next()
        }
    }
    
    public func makeAsyncIterator() -> AsyncIterator {
        // Auto-start subscription when iteration begins
        if state == .pending {
            start()
        }
        return AsyncIterator(iterator: stream.makeAsyncIterator())
    }

    // MARK: - Subscription Control

    /// Start the subscription
    public func start() {
        stateLock.lock()
        let currentState = state
        let shouldStart = currentState == .pending || currentState == .inactive
        if shouldStart {
            state = .active
            isActive = true
        }
        stateLock.unlock()
        
        guard shouldStart else { return }

        // Start with cache if needed
        if options.cacheStrategy == .cacheFirst || options.cacheStrategy == .cacheOnly || options.cacheStrategy == .parallel {
            checkCache()
        }

        // Query relays if needed
        if options.cacheStrategy != .cacheOnly {
            queryRelays()
        }
    }

    /// Close the subscription
    public func close() {
        stateLock.lock()
        let shouldClose = state != .closed
        if shouldClose {
            state = .closed
            isClosed = true
            isActive = false
        }
        stateLock.unlock()
        
        guard shouldClose else { return }

        timeoutTimer?.invalidate()
        timeoutTimer = nil

        // Close on all active relays using subscription manager
        // Capture id before Task to avoid accessing self in async context
        let subscriptionId = id
        Task {
            let relays = await relayState.removeAllRelays()
            for relay in relays {
                await relay.subscriptionManager.removeSubscription(subscriptionId)
                relay.removeSubscription(byId: subscriptionId)
            }
        }
        
        // Complete the streams
        continuation?.finish()
        updateContinuation?.finish()
    }

    // MARK: - Cache Handling

    private func checkCache() {
        guard let ndk = ndk, let cache = ndk.cache else { return }

        Task {
            var cachedEvents: [NDKEvent] = []
            for filter in filters {
                let events = await cache.queryEvents(filter)
                cachedEvents.append(contentsOf: events)
            }

            let eventsCopy = cachedEvents
            await MainActor.run {
                for event in eventsCopy {
                    self.handleEvent(event, fromRelay: nil)
                }

                // If cache-only strategy, mark as EOSE
                if self.options.cacheStrategy == .cacheOnly {
                    self.handleEOSE()
                }
            }
        }
    }

    // MARK: - Relay Handling

    private func queryRelays() {
        guard let ndk = ndk else { return }

        let relaysToUse = options.relays ?? Set(ndk.relays)

        Task {
            for relay in relaysToUse {
                // Only track the relay state - the main subscription manager handles the actual subscription
                await relayState.addRelay(relay)
                // Note: Don't call relay.subscriptionManager.addSubscription() as it's handled by the main NDKSubscriptionManager
            }
        }
    }

    // MARK: - Event Handling

    /// Handle an event received from a relay
    public func handleEvent(_ event: NDKEvent, fromRelay relay: NDKRelay?) {
        stateLock.lock()
        let closed = isClosed
        stateLock.unlock()
        
        guard !closed else { return }

        guard let eventId = event.id else { return }
        
        // Thread-safe event deduplication
        receivedEventIdsLock.lock()
        let alreadyReceived = receivedEventIds.contains(eventId)
        if !alreadyReceived {
            receivedEventIds.insert(eventId)
        }
        receivedEventIdsLock.unlock()
        
        guard !alreadyReceived else {
            return // Deduplicate
        }

        // Check if event matches our filters
        guard filters.contains(where: { $0.matches(event: event) }) else {
            return
        }

        // Thread-safe event storage
        eventsLock.lock()
        events.append(event)
        let currentEventCount = events.count
        eventsLock.unlock()

        // Store in cache if available
        if let ndk = ndk, let cache = ndk.cache {
            Task {
                try? await cache.saveEvent(event)
            }
        }

        // Send event to streams
        continuation?.yield(event)
        updateContinuation?.yield(.event(event))

        // Check limit with thread-safe access
        if let limit = options.limit, currentEventCount >= limit {
            close()
        }
    }

    /// Handle EOSE (End of Stored Events)
    public func handleEOSE(fromRelay relay: NDKRelay? = nil) {
        // Track EOSE from this specific relay
        let relayUrl = relay?.url ?? "unknown"
        var shouldComplete = false
        
        eoseReceivedLock.lock()
        eoseReceivedFromRelays.insert(relayUrl)
        
        // Check if we've received EOSE from all expected relays
        let expectedRelays = options.relays ?? Set(ndk?.relays ?? [])
        let expectedRelayUrls = Set(expectedRelays.map { $0.url })
        let allEoseReceived = expectedRelayUrls.isSubset(of: eoseReceivedFromRelays)
        eoseReceivedLock.unlock()
        
        if allEoseReceived {
            stateLock.lock()
            let alreadyCompleted = eoseReceived
            if !alreadyCompleted {
                eoseReceived = true
                shouldComplete = true
            }
            stateLock.unlock()
            
            if shouldComplete {
                // Send EOSE update
                updateContinuation?.yield(.eose)

                if options.closeOnEose {
                    close()
                }
            }
        }
    }

    /// Handle subscription error
    public func handleError(_ error: Error) {
        // Send error update
        updateContinuation?.yield(.error(error))
    }

    // MARK: - Async Support (for modern Swift)

    /// Wait for EOSE as async
    public func waitForEOSE() async {
        for await update in updates {
            if case .eose = update {
                break
            }
        }
    }
    
    // MARK: - Backward Compatibility
    
    /// Add a callback for events (deprecated, use AsyncSequence instead)
    @available(*, deprecated, message: "Use for-await-in loop instead")
    public func onEvent(_ callback: @escaping (NDKEvent) -> Void) {
        Task {
            for await event in self {
                callback(event)
            }
        }
    }
    
    /// Add a callback for EOSE (deprecated, use updates stream instead)
    @available(*, deprecated, message: "Use updates stream instead")
    public func onEOSE(_ callback: @escaping () -> Void) {
        Task {
            for await update in updates {
                if case .eose = update {
                    callback()
                    break
                }
            }
        }
    }
    
    /// Add a callback for errors (deprecated, use updates stream instead)
    @available(*, deprecated, message: "Use updates stream instead")
    public func onError(_ callback: @escaping (Error) -> Void) {
        Task {
            for await update in updates {
                if case .error(let error) = update {
                    callback(error)
                }
            }
        }
    }

    // MARK: - Private Helpers

    private func setupTimeoutIfNeeded() {
        guard let timeout = options.timeout else { return }

        timeoutTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            self?.close()
        }
    }
}

// MARK: - Equatable & Hashable

extension NDKSubscription: Equatable, Hashable {
    public static func == (lhs: NDKSubscription, rhs: NDKSubscription) -> Bool {
        return lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Subscription grouping utilities

public extension NDKSubscription {
    /// Check if this subscription can be merged with another
    func canMerge(with other: NDKSubscription) -> Bool {
        // Basic checks
        guard !isClosed && !other.isClosed,
              options.closeOnEose == other.options.closeOnEose,
              options.cacheStrategy == other.options.cacheStrategy
        else {
            return false
        }

        // Check if filters can be merged
        for filter in filters {
            for otherFilter in other.filters {
                if filter.merged(with: otherFilter) != nil {
                    return true
                }
            }
        }

        return false
    }

    /// Merge with another subscription
    func merge(with other: NDKSubscription) -> NDKSubscription? {
        guard canMerge(with: other) else { return nil }

        // Combine filters
        var mergedFilters: [NDKFilter] = []
        mergedFilters.append(contentsOf: filters)
        mergedFilters.append(contentsOf: other.filters)

        // Use combined options
        var mergedOptions = options
        if let otherLimit = other.options.limit {
            mergedOptions.limit = Swift.max(options.limit ?? 0, otherLimit)
        }

        return NDKSubscription(
            filters: mergedFilters,
            options: mergedOptions,
            ndk: ndk
        )
    }
}
