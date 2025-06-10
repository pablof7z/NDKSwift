import Foundation

/// Actor for thread-safe subscription state management
actor SubscriptionStateActor {
    private var state: NDKSubscriptionState = .pending
    private var activeRelays: Set<NDKRelay> = []
    private var eoseReceivedFrom: Set<String> = []
    
    func transitionToActive() -> Bool {
        guard state == .pending || state == .inactive else { return false }
        state = .active
        return true
    }
    
    func transitionToClosed() -> (Bool, Set<NDKRelay>) {
        guard state != .closed else { return (false, []) }
        state = .closed
        let relays = activeRelays
        activeRelays.removeAll()
        return (true, relays)
    }
    
    func addRelay(_ relay: NDKRelay) {
        activeRelays.insert(relay)
    }
    
    func handleEOSE(fromRelay relay: RelayProtocol?, expectedRelays: Set<NDKRelay>) -> Bool {
        let relayUrl = relay?.url ?? "cache"
        eoseReceivedFrom.insert(relayUrl)
        
        // Check if we've received EOSE from all expected relays
        let expectedUrls = Set(expectedRelays.map { $0.url })
        return expectedUrls.isSubset(of: eoseReceivedFrom)
    }
    
    var currentState: NDKSubscriptionState { state }
    var isActive: Bool { state == .active }
    var isClosed: Bool { state == .closed }
}

/// Simplified subscription options
public struct NDKSubscriptionOptions {
    /// Whether to close the subscription on EOSE
    public var closeOnEose: Bool = false
    
    /// Use cache for initial events
    public var useCache: Bool = true
    
    /// Maximum number of events to receive
    public var limit: Int?
    
    /// Timeout for the subscription
    public var timeout: TimeInterval?
    
    /// Specific relays to use for this subscription
    public var relays: Set<NDKRelay>?
    
    /// Legacy cache strategy support
    public var cacheStrategy: NDKCacheStrategy {
        get { useCache ? .cacheFirst : .relayOnly }
        set { useCache = newValue != .relayOnly }
    }
    
    public init() {}
}

/// Cache strategy for subscriptions (kept for compatibility)
public enum NDKCacheStrategy {
    case cacheFirst // Check cache first, then relays
    case cacheOnly // Only check cache
    case relayOnly // Only check relays
    case parallel // Check cache and relays in parallel
}

/// Update type for subscription stream (kept for compatibility)
public enum NDKSubscriptionUpdate {
    case event(NDKEvent)
    case eose
    case error(Error)
}

/// Simplified subscription implementation
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
    
    /// Current subscription state (public read-only)
    public private(set) var state: NDKSubscriptionState = .pending
    
    /// Events received so far
    public private(set) var events: [NDKEvent] = []
    private let eventsLock = NSLock()
    
    /// Thread-safe state management
    private let stateActor = SubscriptionStateActor()
    
    /// Event deduplication - thread-safe set
    private let seenEventIdsLock = NSLock()
    private var seenEventIds: Set<EventID> = []
    
    /// Timer for timeout
    private var timeoutTimer: Timer?
    
    /// The stream continuation for sending events
    private var continuation: AsyncStream<NDKEvent>.Continuation?
    
    /// The async stream of events
    private let stream: AsyncStream<NDKEvent>
    
    /// Update stream for backward compatibility
    public let updates: AsyncStream<NDKSubscriptionUpdate>
    private var updateContinuation: AsyncStream<NDKSubscriptionUpdate>.Continuation?
    
    /// Task that handles registration with the subscription manager
    internal var registrationTask: Task<Void, Never>?
    
    // State properties that need to be synchronous for compatibility
    public var eoseReceived: Bool = false
    public var isActive: Bool = false
    public var isClosed: Bool = false

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
        
        // Create the event stream with proper cleanup
        var streamContinuation: AsyncStream<NDKEvent>.Continuation?
        self.stream = AsyncStream<NDKEvent> { continuation in
            streamContinuation = continuation
            continuation.onTermination = { _ in
                // Clean up when stream is terminated
            }
        }
        self.continuation = streamContinuation
        
        // Create the update stream for compatibility
        var updateStreamContinuation: AsyncStream<NDKSubscriptionUpdate>.Continuation?
        self.updates = AsyncStream<NDKSubscriptionUpdate> { continuation in
            updateStreamContinuation = continuation
            continuation.onTermination = { _ in
                // Clean up when stream is terminated
            }
        }
        self.updateContinuation = updateStreamContinuation
        
        setupTimeoutIfNeeded()
    }

    deinit {
        // Don't call close() here as it creates a retain cycle
        // Instead, just clean up synchronous resources
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        
        // Finish the streams if they're still open
        continuation?.finish()
        updateContinuation?.finish()
        
        // Cancel the registration task
        registrationTask?.cancel()
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
        Task.detached { [weak self] in
            guard let self = self else { return }
            
            let shouldStart = await self.stateActor.transitionToActive()
            guard shouldStart else { return }
            
            // Update public state
            await MainActor.run {
                self.state = .active
                self.isActive = true
            }
            
            // Start with cache if needed
            if self.options.useCache {
                await self.checkCache()
            }
            
            // Query relays
            await self.queryRelays()
        }
    }

    /// Close the subscription
    public func close() {
        // Create a detached task to avoid retain cycles
        Task.detached { [weak self, id = self.id] in
            guard let self = self else { return }
            
            let (shouldClose, relays) = await self.stateActor.transitionToClosed()
            guard shouldClose else { return }
            
            // Update public state
            await MainActor.run {
                self.state = .closed
                self.isClosed = true
                self.isActive = false
                
                self.timeoutTimer?.invalidate()
                self.timeoutTimer = nil
            }
            
            // Close on all active relays
            for relay in relays {
                await relay.subscriptionManager.removeSubscription(id)
                relay.removeSubscription(byId: id)
            }
            
            // Complete the streams
            await MainActor.run {
                self.continuation?.finish()
                self.updateContinuation?.finish()
            }
        }
    }

    // MARK: - Cache Handling

    private func checkCache() async {
        guard let ndk = ndk, let cache = ndk.cache else { return }
        
        var cachedEvents: [NDKEvent] = []
        for filter in filters {
            let events = await cache.queryEvents(filter)
            cachedEvents.append(contentsOf: events)
        }
        
        for event in cachedEvents {
            handleEvent(event, fromRelay: nil)
        }
    }

    // MARK: - Relay Handling

    private func queryRelays() async {
        guard let ndk = ndk else { return }
        
        let relaysToUse = options.relays ?? Set(ndk.relays)
        
        for relay in relaysToUse {
            await stateActor.addRelay(relay)
            // Note: The main subscription manager handles the actual subscription
        }
    }

    // MARK: - Event Handling

    /// Handle an event received from a relay
    public func handleEvent(_ event: NDKEvent, fromRelay relay: RelayProtocol?) {
        guard state != .closed else { return }
        
        guard let eventId = event.id else { return }
        
        // Deduplicate event (thread-safe)
        seenEventIdsLock.lock()
        let alreadySeen = seenEventIds.contains(eventId)
        if !alreadySeen {
            seenEventIds.insert(eventId)
        }
        seenEventIdsLock.unlock()
        
        guard !alreadySeen else {
            return // Already seen
        }
        
        // Check if event matches our filters
        guard filters.contains(where: { $0.matches(event: event) }) else {
            return
        }
        
        // Store event (thread-safe)
        eventsLock.lock()
        events.append(event)
        eventsLock.unlock()
        let currentEventCount = events.count
        
        // Store in cache if available
        if let ndk = ndk, let cache = ndk.cache {
            Task {
                try? await cache.saveEvent(event)
            }
        }
        
        // Send event to streams
        continuation?.yield(event)
        updateContinuation?.yield(.event(event))
        
        // Check limit
        if let limit = options.limit, currentEventCount >= limit {
            close()
        }
    }

    /// Handle EOSE (End of Stored Events)
    public func handleEOSE(fromRelay relay: RelayProtocol? = nil) {
        Task {
            let shouldComplete = await stateActor.handleEOSE(
                fromRelay: relay,
                expectedRelays: options.relays ?? Set(ndk?.relays ?? [])
            )
            
            if shouldComplete {
                // Send EOSE update
                self.updateContinuation?.yield(.eose)
                self.eoseReceived = true
                
                if self.options.closeOnEose {
                    self.close()
                }
            }
        }
    }

    /// Handle subscription error
    public func handleError(_ error: Error) {
        // Send error update
        updateContinuation?.yield(.error(error))
        
        // Log if debug mode
        if let ndk = ndk, ndk.debugMode {
            print("❌ Subscription error: \(error)")
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

// MARK: - Backward Compatibility

extension NDKSubscription {
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
    
    /// Wait for EOSE as async
    public func waitForEOSE() async {
        for await update in updates {
            if case .eose = update {
                break
            }
        }
    }
}

