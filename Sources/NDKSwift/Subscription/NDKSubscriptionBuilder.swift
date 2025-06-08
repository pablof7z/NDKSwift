import Foundation

/// A builder for creating subscriptions with a fluent API
public class NDKSubscriptionBuilder {
    private let ndk: NDK
    private var filters: [NDKFilter] = []
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
        return self
    }
    
    /// Add a filter for specific event kinds
    @discardableResult
    public func kinds(_ kinds: [Kind]) -> Self {
        var filter = NDKFilter()
        filter.kinds = kinds
        filters.append(filter)
        return self
    }
    
    /// Add a filter for specific authors
    @discardableResult
    public func authors(_ authors: [PublicKey]) -> Self {
        var filter = NDKFilter()
        filter.authors = authors
        filters.append(filter)
        return self
    }
    
    /// Add a filter for events since a specific time
    @discardableResult
    public func since(_ timestamp: Timestamp) -> Self {
        for i in filters.indices {
            filters[i].since = timestamp
        }
        if filters.isEmpty {
            var filter = NDKFilter()
            filter.since = timestamp
            filters.append(filter)
        }
        return self
    }
    
    /// Add a filter for events until a specific time
    @discardableResult
    public func until(_ timestamp: Timestamp) -> Self {
        for i in filters.indices {
            filters[i].until = timestamp
        }
        if filters.isEmpty {
            var filter = NDKFilter()
            filter.until = timestamp
            filters.append(filter)
        }
        return self
    }
    
    /// Add a limit to the subscription
    @discardableResult
    public func limit(_ limit: Int) -> Self {
        for i in filters.indices {
            filters[i].limit = limit
        }
        if filters.isEmpty {
            var filter = NDKFilter()
            filter.limit = limit
            filters.append(filter)
        }
        return self
    }
    
    /// Add hashtag filters
    @discardableResult
    public func hashtags(_ tags: [String]) -> Self {
        var filter = NDKFilter()
        filter.addTagFilter("t", values: tags.map { $0.lowercased() })
        filters.append(filter)
        return self
    }
    
    // MARK: - Options Configuration
    
    /// Set cache strategy
    @discardableResult
    public func cacheStrategy(_ strategy: CacheStrategy) -> Self {
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
        let subscription = ndk.subscribe(filters: filters, options: options)
        
        if let handler = eventHandler {
            subscription.onEvent(handler)
        }
        
        if let handler = eoseHandler {
            subscription.onEOSE(handler)
        }
        
        if let handler = errorHandler {
            subscription.onError(handler)
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
        subscription.onEvent(onEvent)
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
        
        subscription.onEvent { event in
            events.append(event)
        }
        
        subscription.start()
        
        // Wait for EOSE or timeout
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                await subscription.waitForEOSE()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw NDKUnifiedError.network(.timeout)
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
        
        subscription.onEvent { event in
            events.append(event)
        }
        
        subscription.start()
        
        // Wait for EOSE or timeout
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                await subscription.waitForEOSE()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw NDKUnifiedError.network(.timeout)
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
            
            subscription.onEvent { event in
                continuation.yield(event)
            }
            
            subscription.onError { error in
                continuation.finish()
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
        let subscription = subscribe(filters: [filter])
        
        subscription.onEvent { event in
            collectedEvents.append(event)
            if collectedEvents.count >= limit {
                subscription.close()
                completion(collectedEvents)
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