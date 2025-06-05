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

/// Delegate for subscription events
public protocol NDKSubscriptionDelegate: AnyObject {
    func subscription(_ subscription: NDKSubscription, didReceiveEvent event: NDKEvent)
    func subscription(_ subscription: NDKSubscription, didReceiveEOSE: Void)
    func subscription(_ subscription: NDKSubscription, didReceiveError error: Error)
}

/// Real implementation of NDKSubscription
public final class NDKSubscription {
    /// Unique subscription ID
    public let id: String

    /// Filters for this subscription
    public let filters: [NDKFilter]

    /// Subscription options
    public let options: NDKSubscriptionOptions

    /// Reference to NDK instance
    public weak var ndk: NDK?

    /// Subscription delegate
    public weak var delegate: NDKSubscriptionDelegate?

    /// Events received so far
    public private(set) var events: [NDKEvent] = []

    /// Whether EOSE has been received
    public private(set) var eoseReceived: Bool = false

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

    /// Event callbacks - protected by lock
    var eventCallbacks: [(NDKEvent) -> Void] = []
    private let eventCallbacksLock = NSLock()

    /// EOSE callbacks - protected by lock  
    var eoseCallbacks: [() -> Void] = []
    private let eoseCallbacksLock = NSLock()

    /// Error callbacks - protected by lock
    var errorCallbacks: [(Error) -> Void] = []
    private let errorCallbacksLock = NSLock()

    /// Events array lock
    private let eventsLock = NSLock()

    /// State locks
    private let stateLock = NSLock()

    public init(
        id: String = UUID().uuidString,
        filters: [NDKFilter],
        options: NDKSubscriptionOptions = NDKSubscriptionOptions(),
        ndk: NDK? = nil
    ) {
        self.id = id
        self.filters = filters
        self.options = options
        self.ndk = ndk

        setupTimeoutIfNeeded()
    }

    deinit {
        close()
    }

    // MARK: - Callback Registration

    /// Add a callback for events
    public func onEvent(_ callback: @escaping (NDKEvent) -> Void) {
        eventCallbacksLock.lock()
        eventCallbacks.append(callback)
        eventCallbacksLock.unlock()
    }

    /// Add a callback for EOSE
    public func onEOSE(_ callback: @escaping () -> Void) {
        eoseCallbacksLock.lock()
        eoseCallbacks.append(callback)
        eoseCallbacksLock.unlock()
    }

    /// Add a callback for errors
    public func onError(_ callback: @escaping (Error) -> Void) {
        errorCallbacksLock.lock()
        errorCallbacks.append(callback)
        errorCallbacksLock.unlock()
    }

    // MARK: - Subscription Control

    /// Start the subscription
    public func start() {
        stateLock.lock()
        let shouldStart = !isActive && !isClosed
        if shouldStart {
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
        let shouldClose = !isClosed
        if shouldClose {
            isClosed = true
            isActive = false
        }
        stateLock.unlock()
        
        guard shouldClose else { return }

        timeoutTimer?.invalidate()
        timeoutTimer = nil

        // Close on all active relays using subscription manager
        Task {
            let relays = await relayState.removeAllRelays()
            for relay in relays {
                await relay.subscriptionManager.removeSubscription(id)
                relay.removeSubscription(self)
            }
        }
        
        // Thread-safe callback cleanup
        eventCallbacksLock.lock()
        eventCallbacks.removeAll()
        eventCallbacksLock.unlock()
        
        eoseCallbacksLock.lock()
        eoseCallbacks.removeAll()
        eoseCallbacksLock.unlock()
        
        errorCallbacksLock.lock()
        errorCallbacks.removeAll()
        errorCallbacksLock.unlock()
    }

    // MARK: - Cache Handling

    private func checkCache() {
        guard let ndk = ndk, let cache = ndk.cacheAdapter else { return }

        Task {
            let cachedEvents = await cache.query(subscription: self)

            await MainActor.run {
                for event in cachedEvents {
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
                // Use the relay's subscription manager which handles connection state
                let _ = await relay.subscriptionManager.addSubscription(self, filters: filters)
                await relayState.addRelay(relay)
                relay.addSubscription(self)
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
        if let ndk = ndk, let cache = ndk.cacheAdapter {
            Task {
                await cache.setEvent(event, filters: filters, relay: relay)
            }
        }

        // Thread-safe callback execution
        eventCallbacksLock.lock()
        let callbacks = eventCallbacks
        eventCallbacksLock.unlock()
        
        for callback in callbacks {
            callback(event)
        }
        delegate?.subscription(self, didReceiveEvent: event)

        // Check limit with thread-safe access
        if let limit = options.limit, currentEventCount >= limit {
            close()
        }
    }

    /// Handle EOSE (End of Stored Events)
    public func handleEOSE(fromRelay _: NDKRelay? = nil) {
        stateLock.lock()
        let alreadyReceived = eoseReceived
        if !alreadyReceived {
            eoseReceived = true
        }
        stateLock.unlock()
        
        guard !alreadyReceived else { return }

        // Thread-safe callback execution
        eoseCallbacksLock.lock()
        let callbacks = eoseCallbacks
        eoseCallbacksLock.unlock()
        
        for callback in callbacks {
            callback()
        }
        delegate?.subscription(self, didReceiveEOSE: ())

        if options.closeOnEose {
            close()
        }
    }

    /// Handle subscription error
    public func handleError(_ error: Error) {
        // Thread-safe callback execution
        errorCallbacksLock.lock()
        let callbacks = errorCallbacks
        errorCallbacksLock.unlock()
        
        for callback in callbacks {
            callback(error)
        }
        delegate?.subscription(self, didReceiveError: error)
    }

    // MARK: - Async Support (for modern Swift)

    /// Stream of events as an async sequence
    public func eventStream() -> AsyncStream<NDKEvent> {
        return AsyncStream { continuation in
            let callback: (NDKEvent) -> Void = { event in
                continuation.yield(event)
            }

            // Thread-safe callback registration
            eventCallbacksLock.lock()
            eventCallbacks.append(callback)
            eventCallbacksLock.unlock()

            // Handle completion
            let eoseCallback = {
                continuation.finish()
            }
            
            eoseCallbacksLock.lock()
            eoseCallbacks.append(eoseCallback)
            eoseCallbacksLock.unlock()

            continuation.onTermination = { _ in
                // Thread-safe cleanup when stream is cancelled
                self.eventCallbacksLock.lock()
                if let index = self.eventCallbacks.firstIndex(where: { _ in true }) {
                    self.eventCallbacks.remove(at: index)
                }
                self.eventCallbacksLock.unlock()
                
                self.eoseCallbacksLock.lock()
                if let index = self.eoseCallbacks.firstIndex(where: { _ in true }) {
                    self.eoseCallbacks.remove(at: index)
                }
                self.eoseCallbacksLock.unlock()
            }
        }
    }

    /// Wait for EOSE as async
    public func waitForEOSE() async {
        await withCheckedContinuation { continuation in
            stateLock.lock()
            let received = eoseReceived
            stateLock.unlock()
            
            if received {
                continuation.resume()
                return
            }

            let callback = {
                continuation.resume()
            }
            
            eoseCallbacksLock.lock()
            eoseCallbacks.append(callback)
            eoseCallbacksLock.unlock()
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
            mergedOptions.limit = max(options.limit ?? 0, otherLimit)
        }

        return NDKSubscription(
            filters: mergedFilters,
            options: mergedOptions,
            ndk: ndk
        )
    }
}
