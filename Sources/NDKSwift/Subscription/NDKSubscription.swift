import Foundation

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
    case cacheFirst    // Check cache first, then relays
    case cacheOnly     // Only check cache
    case relayOnly     // Only check relays
    case parallel      // Check cache and relays in parallel
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
    
    /// Relays this subscription is active on
    private var activeRelays: Set<NDKRelay> = []
    
    /// Event deduplication
    private var receivedEventIds: Set<EventID> = []
    
    /// Timer for timeout
    private var timeoutTimer: Timer?
    
    /// Event callbacks
    internal var eventCallbacks: [(NDKEvent) -> Void] = []
    
    /// EOSE callbacks
    internal var eoseCallbacks: [() -> Void] = []
    
    /// Error callbacks
    internal var errorCallbacks: [(Error) -> Void] = []
    
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
        eventCallbacks.append(callback)
    }
    
    /// Add a callback for EOSE
    public func onEOSE(_ callback: @escaping () -> Void) {
        eoseCallbacks.append(callback)
    }
    
    /// Add a callback for errors
    public func onError(_ callback: @escaping (Error) -> Void) {
        errorCallbacks.append(callback)
    }
    
    // MARK: - Subscription Control
    
    /// Start the subscription
    public func start() {
        guard !isActive && !isClosed else { return }
        
        isActive = true
        
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
        guard !isClosed else { return }
        
        isClosed = true
        isActive = false
        
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        
        // Close on all active relays using subscription manager
        Task {
            for relay in activeRelays {
                await relay.subscriptionManager.removeSubscription(id)
                relay.removeSubscription(self)
            }
        }
        
        activeRelays.removeAll()
        eventCallbacks.removeAll()
        eoseCallbacks.removeAll()
        errorCallbacks.removeAll()
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
                activeRelays.insert(relay)
                relay.addSubscription(self)
            }
        }
    }
    
    // MARK: - Event Handling
    
    /// Handle an event received from a relay
    public func handleEvent(_ event: NDKEvent, fromRelay relay: NDKRelay?) {
        guard !isClosed else { return }
        
        guard let eventId = event.id, !receivedEventIds.contains(eventId) else {
            return // Deduplicate
        }
        
        // Check if event matches our filters
        guard filters.contains(where: { $0.matches(event: event) }) else {
            return
        }
        
        receivedEventIds.insert(eventId)
        events.append(event)
        
        // Store in cache if available
        if let ndk = ndk, let cache = ndk.cacheAdapter {
            Task {
                await cache.setEvent(event, filters: filters, relay: relay)
            }
        }
        
        // Notify callbacks and delegate
        for callback in eventCallbacks {
            callback(event)
        }
        delegate?.subscription(self, didReceiveEvent: event)
        
        // Check limit
        if let limit = options.limit, events.count >= limit {
            close()
        }
    }
    
    /// Handle EOSE (End of Stored Events)
    public func handleEOSE(fromRelay relay: NDKRelay? = nil) {
        guard !eoseReceived else { return }
        
        eoseReceived = true
        
        // Notify callbacks and delegate
        for callback in eoseCallbacks {
            callback()
        }
        delegate?.subscription(self, didReceiveEOSE: ())
        
        if options.closeOnEose {
            close()
        }
    }
    
    /// Handle subscription error
    public func handleError(_ error: Error) {
        for callback in errorCallbacks {
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
            
            eventCallbacks.append(callback)
            
            // Handle completion
            let eoseCallback = {
                continuation.finish()
            }
            eoseCallbacks.append(eoseCallback)
            
            continuation.onTermination = { _ in
                // Clean up when stream is cancelled
                if let index = self.eventCallbacks.firstIndex(where: { _ in true }) {
                    self.eventCallbacks.remove(at: index)
                }
                if let index = self.eoseCallbacks.firstIndex(where: { _ in true }) {
                    self.eoseCallbacks.remove(at: index)
                }
            }
        }
    }
    
    /// Wait for EOSE as async
    public func waitForEOSE() async {
        await withCheckedContinuation { continuation in
            if eoseReceived {
                continuation.resume()
                return
            }
            
            let callback = {
                continuation.resume()
            }
            eoseCallbacks.append(callback)
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
              options.cacheStrategy == other.options.cacheStrategy else {
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