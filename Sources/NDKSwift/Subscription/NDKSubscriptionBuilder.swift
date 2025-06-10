import Foundation

/// A builder for creating subscriptions with a fluent API
public class NDKSubscriptionBuilder {
    private let ndk: NDK
    private var filters: [NDKFilter] = []
    private var currentFilter: NDKFilter?
    private var options = NDKSubscriptionOptions()
    private var eventHandler: ((NDKEvent) -> Void)?
    private var eoseHandler: (() -> Void)?
    private var errorHandler: ((Error) -> Void)?
    private var autoStart = true
    
    init(ndk: NDK) {
        self.ndk = ndk
    }
    
    // MARK: - Filter Building
    
    /// Add a filter to the subscription
    @discardableResult
    public func filter(_ filter: NDKFilter) -> Self {
        filters.append(filter)
        currentFilter = nil  // Reset current filter when adding a complete filter
        return self
    }
    
    /// Get or create the current filter being built
    private func ensureCurrentFilter() {
        if currentFilter == nil {
            currentFilter = NDKFilter()
        }
    }
    
    /// Add a filter for specific event kinds
    @discardableResult
    public func kinds(_ kinds: [Kind]) -> Self {
        ensureCurrentFilter()
        currentFilter?.kinds = kinds
        return self
    }
    
    /// Add a filter for specific authors
    @discardableResult
    public func authors(_ authors: [PublicKey]) -> Self {
        ensureCurrentFilter()
        currentFilter?.authors = authors
        return self
    }
    
    /// Add a filter for events since a specific time
    @discardableResult
    public func since(_ timestamp: Timestamp) -> Self {
        ensureCurrentFilter()
        currentFilter?.since = timestamp
        return self
    }
    
    /// Add a filter for events until a specific time
    @discardableResult
    public func until(_ timestamp: Timestamp) -> Self {
        ensureCurrentFilter()
        currentFilter?.until = timestamp
        return self
    }
    
    /// Add a limit to the subscription
    @discardableResult
    public func limit(_ limit: Int) -> Self {
        ensureCurrentFilter()
        currentFilter?.limit = limit
        return self
    }
    
    /// Add hashtag filters
    @discardableResult
    public func hashtags(_ tags: [String]) -> Self {
        ensureCurrentFilter()
        currentFilter?.addTagFilter("t", values: tags.map { $0.lowercased() })
        return self
    }
    
    // MARK: - Options Configuration
    
    /// Set cache strategy
    @discardableResult
    public func cacheStrategy(_ strategy: NDKCacheStrategy) -> Self {
        options.cacheStrategy = strategy
        return self
    }
    
    /// Close subscription on EOSE
    @discardableResult
    public func closeOnEose() -> Self {
        options.closeOnEose = true
        return self
    }
    
    /// Set specific relays for this subscription
    @discardableResult
    public func relays(_ relays: Set<NDKRelay>) -> Self {
        options.relays = relays
        return self
    }
    
    /// Disable auto-start behavior
    @discardableResult
    public func manualStart() -> Self {
        autoStart = false
        return self
    }
    
    // MARK: - Event Handlers
    
    /// Set event handler
    @discardableResult
    public func onEvent(_ handler: @escaping (NDKEvent) -> Void) -> Self {
        eventHandler = handler
        return self
    }
    
    /// Set EOSE handler
    @discardableResult
    public func onEose(_ handler: @escaping () -> Void) -> Self {
        eoseHandler = handler
        return self
    }
    
    /// Set error handler
    @discardableResult
    public func onError(_ handler: @escaping (Error) -> Void) -> Self {
        errorHandler = handler
        return self
    }
    
    // MARK: - Build and Start
    
    /// Build and optionally start the subscription
    public func build() -> NDKSubscription {
        // Add the current filter if we have one
        if let filter = currentFilter {
            filters.append(filter)
        }
        
        // If no filters were added, create an empty one
        if filters.isEmpty {
            filters.append(NDKFilter())
        }
        
        let subscription = ndk.subscribe(filters: filters, options: options)
        
        // Handle legacy callback handlers by converting to async
        if eventHandler != nil || eoseHandler != nil || errorHandler != nil {
            Task { [weak subscription] in
                guard let subscription = subscription else { return }
                for await update in subscription.updates {
                    switch update {
                    case .event(let event):
                        eventHandler?(event)
                    case .eose:
                        eoseHandler?()
                    case .error(let error):
                        errorHandler?(error as? NDKError ?? NDKError.runtime("subscription_error", error.localizedDescription))
                        break
                    }
                }
            }
        }
        
        if autoStart {
            subscription.start()
        }
        
        return subscription
    }
    
    /// Build and start the subscription (alias for build when autoStart is true)
    public func start() -> NDKSubscription {
        return build()
    }
}

// MARK: - Convenience Extensions

extension NDK {
    /// Create a subscription using the builder pattern
    public func subscription() -> NDKSubscriptionBuilder {
        return NDKSubscriptionBuilder(ndk: self)
    }
    
    /// Subscribe with auto-start and inline event handler
    @discardableResult
    public func subscribe(
        filters: [NDKFilter],
        options: NDKSubscriptionOptions = NDKSubscriptionOptions(),
        onEvent: @escaping (NDKEvent) -> Void
    ) -> NDKSubscription {
        let subscription = subscribe(filters: filters, options: options)
        
        // Handle events asynchronously
        Task { [weak subscription] in
            guard let subscription = subscription else { return }
            for await event in subscription {
                onEvent(event)
            }
        }
        
        subscription.start()
        return subscription
    }
    
    /// Subscribe to a single filter with auto-start
    @discardableResult
    public func subscribe(
        filter: NDKFilter,
        options: NDKSubscriptionOptions = NDKSubscriptionOptions(),
        onEvent: @escaping (NDKEvent) -> Void
    ) -> NDKSubscription {
        return subscribe(filters: [filter], options: options, onEvent: onEvent)
    }
    
    /// Fetch events and auto-close on EOSE
    public func fetch(
        _ filter: NDKFilter,
        timeout: TimeInterval = 5.0
    ) async throws -> [NDKEvent] {
        var options = NDKSubscriptionOptions()
        options.closeOnEose = true
        
        let subscription = subscribe(filters: [filter], options: options)
        var events: [NDKEvent] = []
        
        // Collect events asynchronously
        Task { [weak subscription] in
            guard let subscription = subscription else { return }
            for await event in subscription {
                events.append(event)
            }
        }
        
        subscription.start()
        
        // Wait for EOSE or timeout
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                await subscription.waitForEOSE()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw NDKError.network("timeout", "Operation timed out")
            }
            
            try await group.next()
            group.cancelAll()
        }
        
        return events
    }
    
    /// Fetch events from multiple filters
    public func fetch(
        _ filters: [NDKFilter],
        timeout: TimeInterval = 5.0
    ) async throws -> [NDKEvent] {
        var options = NDKSubscriptionOptions()
        options.closeOnEose = true
        
        let subscription = subscribe(filters: filters, options: options)
        var events: [NDKEvent] = []
        
        // Collect events asynchronously
        Task { [weak subscription] in
            guard let subscription = subscription else { return }
            for await event in subscription {
                events.append(event)
            }
        }
        
        subscription.start()
        
        // Wait for EOSE or timeout
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                await subscription.waitForEOSE()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw NDKError.network("timeout", "Operation timed out")
            }
            
            try await group.next()
            group.cancelAll()
        }
        
        return events
    }
    
    /// Create a streaming subscription that returns an AsyncStream
    public func stream(_ filter: NDKFilter) -> AsyncStream<NDKEvent> {
        return stream([filter])
    }
    
    /// Create a streaming subscription for multiple filters
    public func stream(_ filters: [NDKFilter]) -> AsyncStream<NDKEvent> {
        AsyncStream { continuation in
            let subscription = subscribe(filters: filters)
            
            // Handle subscription updates asynchronously
            Task { [weak subscription] in
                guard let subscription = subscription else {
                    continuation.finish()
                    return
                }
                
                for await update in subscription.updates {
                    switch update {
                    case .event(let event):
                        continuation.yield(event)
                    case .eose, .error:
                        continuation.finish()
                        break
                    }
                }
            }
            
            subscription.start()
            
            continuation.onTermination = { _ in
                subscription.close()
            }
        }
    }
    
    /// Subscribe and automatically close after receiving N events
    @discardableResult
    public func subscribeOnce(
        _ filter: NDKFilter,
        limit: Int = 1,
        completion: @escaping ([NDKEvent]) -> Void
    ) -> NDKSubscription {
        var collectedEvents: [NDKEvent] = []
        var completed = false
        let subscription = subscribe(filters: [filter])
        
        // Collect events asynchronously
        Task { [weak subscription] in
            guard let subscription = subscription else { return }
            
            for await event in subscription {
                guard !completed else { break }
                collectedEvents.append(event)
                if collectedEvents.count >= limit {
                    completed = true
                    subscription.close()
                    completion(Array(collectedEvents.prefix(limit)))
                    break
                }
            }
        }
        
        subscription.start()
        return subscription
    }
}

// MARK: - Profile Fetching Convenience

extension NDK {
    /// Fetch a single user profile
    public func fetchProfile(_ pubkey: PublicKey) async throws -> NDKUserProfile? {
        var filter = NDKFilter()
        filter.authors = [pubkey]
        filter.kinds = [0] // Profile metadata
        filter.limit = 1
        
        let events = try await fetch(filter, timeout: 3.0)
        
        if let profileEvent = events.first,
           let profileData = profileEvent.content.data(using: .utf8),
           let profile = try? JSONCoding.decoder.decode(NDKUserProfile.self, from: profileData) {
            return profile
        }
        
        return nil
    }
    
    /// Fetch multiple user profiles
    public func fetchProfiles(_ pubkeys: [PublicKey]) async throws -> [PublicKey: NDKUserProfile] {
        var filter = NDKFilter()
        filter.authors = pubkeys
        filter.kinds = [0] // Profile metadata
        
        let events = try await fetch(filter, timeout: 5.0)
        var profiles: [PublicKey: NDKUserProfile] = [:]
        
        for event in events {
            if let profileData = event.content.data(using: .utf8),
               let profile = try? JSONCoding.decoder.decode(NDKUserProfile.self, from: profileData) {
                profiles[event.pubkey] = profile
            }
        }
        
        return profiles
    }
    
    /// Subscribe to profile updates for a user
    @discardableResult
    public func subscribeToProfile(
        _ pubkey: PublicKey,
        onUpdate: @escaping (NDKUserProfile) -> Void
    ) -> NDKSubscription {
        var filter = NDKFilter()
        filter.authors = [pubkey]
        filter.kinds = [0] // Profile metadata
        
        return subscribe(filter: filter) { event in
            if let profileData = event.content.data(using: .utf8),
               let profile = try? JSONCoding.decoder.decode(NDKUserProfile.self, from: profileData) {
                onUpdate(profile)
            }
        }
    }
}

// MARK: - Subscription Groups

/// Manages a group of subscriptions for bulk operations
public class NDKSubscriptionGroup {
    private var subscriptions: [NDKSubscription] = []
    private let ndk: NDK
    
    public init(ndk: NDK) {
        self.ndk = ndk
    }
    
    /// Add a subscription to the group
    @discardableResult
    public func subscribe(
        _ filter: NDKFilter,
        onEvent: @escaping (NDKEvent) -> Void
    ) -> NDKSubscription {
        let subscription = ndk.subscribe(filter: filter, onEvent: onEvent)
        subscriptions.append(subscription)
        return subscription
    }
    
    /// Add multiple filters as a single subscription
    @discardableResult
    public func subscribe(
        filters: [NDKFilter],
        onEvent: @escaping (NDKEvent) -> Void
    ) -> NDKSubscription {
        let subscription = ndk.subscribe(filters: filters, onEvent: onEvent)
        subscriptions.append(subscription)
        return subscription
    }
    
    /// Close all subscriptions in the group
    public func closeAll() {
        for subscription in subscriptions {
            subscription.close()
        }
        subscriptions.removeAll()
    }
    
    /// Get all active subscriptions
    public var activeSubscriptions: [NDKSubscription] {
        return subscriptions.filter { $0.state != .closed }
    }
}

extension NDK {
    /// Create a subscription group for managing multiple subscriptions
    public func subscriptionGroup() -> NDKSubscriptionGroup {
        return NDKSubscriptionGroup(ndk: self)
    }
}