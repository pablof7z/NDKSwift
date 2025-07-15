import Foundation

/// A builder for creating subscriptions with a fluent API
public class NDKSubscriptionBuilder {
    private let ndk: NDK
    private var filters: [NDKFilter] = []
    private var currentFilter: NDKFilter?
    private var options = NDKSubscriptionOptions()
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
    
    /// Enable or disable cache usage
    @discardableResult
    public func useCache(_ useCache: Bool) -> Self {
        options.useCache = useCache
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
    
    // MARK: - Build and Start
    
    /// Build and optionally start the subscription
    public func build() async -> NDKSubscription {
        // Add the current filter if we have one
        if let filter = currentFilter {
            filters.append(filter)
        }
        
        // If no filters were added, create an empty one
        if filters.isEmpty {
            filters.append(NDKFilter())
        }
        
        let relayUrls = options.relays?.compactMap { $0.url }
        let relaySet = relayUrls.map { Set($0) }
        
        let subscription = await ndk.subscribe(
            filters: filters,
            relays: relaySet,
            closeOnEose: options.closeOnEose
        )
        
        if autoStart {
            Task {
                await subscription.start()
            }
        }
        
        return subscription
    }
    
    /// Build and start the subscription (alias for build when autoStart is true)
    public func start() async -> NDKSubscription {
        return await build()
    }
}

// MARK: - Convenience Extensions

extension NDK {
    /// Create a subscription using the builder pattern
    public func subscription() -> NDKSubscriptionBuilder {
        return NDKSubscriptionBuilder(ndk: self)
    }
    
    /// Fetch events and auto-close on EOSE
    public func fetch(
        _ filter: NDKFilter,
        timeout: TimeInterval = 5.0
    ) async throws -> [NDKEvent] {
        var options = NDKSubscriptionOptions()
        options.closeOnEose = true
        
        let relayUrls = options.relays?.compactMap { $0.url }
        let relaySet = relayUrls.map { Set($0) }
        
        let subscription = await subscribe(
            filters: [filter],
            relays: relaySet,
            closeOnEose: options.closeOnEose
        )
        var events: [NDKEvent] = []
        
        // Collect events asynchronously
        Task { [weak subscription] in
            guard let subscription = subscription else { return }
            do {
                for try await event in subscription {
                    events.append(event)
                }
            } catch {
                // Ignore errors for fetch operation
            }
        }
        
        await subscription.start()
        
        // Wait for EOSE or timeout
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                await subscription.waitForEOSE()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw NDKError.timeout(operation: "Fetch events", seconds: Int(timeout))
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
        
        let relayUrls = options.relays?.compactMap { $0.url }
        let relaySet = relayUrls.map { Set($0) }
        
        let subscription = await subscribe(
            filters: filters,
            relays: relaySet,
            closeOnEose: options.closeOnEose
        )
        var events: [NDKEvent] = []
        
        // Collect events asynchronously
        Task { [weak subscription] in
            guard let subscription = subscription else { return }
            do {
                for try await event in subscription {
                    events.append(event)
                }
            } catch {
                // Ignore errors for fetch operation
            }
        }
        
        await subscription.start()
        
        // Wait for EOSE or timeout
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                await subscription.waitForEOSE()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw NDKError.timeout(operation: "Fetch events", seconds: Int(timeout))
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
            // Handle subscription updates asynchronously
            _ = Task {
                let subscription = await subscribe(filters: filters)
                
                // Set up termination handler
                continuation.onTermination = { _ in
                    Task {
                        await subscription.close()
                    }
                }
                
                // Start the subscription
                await subscription.start()
                
                do {
                    for try await event in subscription {
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish()
                }
            }
        }
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
    public func subscribe(_ filter: NDKFilter) async -> NDKSubscription {
        let subscription = await ndk.subscribe(filters: [filter])
        subscriptions.append(subscription)
        await subscription.start()
        return subscription
    }
    
    /// Add multiple filters as a single subscription
    @discardableResult
    public func subscribe(filters: [NDKFilter]) async -> NDKSubscription {
        let subscription = await ndk.subscribe(filters: filters)
        subscriptions.append(subscription)
        await subscription.start()
        return subscription
    }
    
    /// Close all subscriptions in the group
    public func closeAll() async {
        for subscription in subscriptions {
            await subscription.close()
        }
        subscriptions.removeAll()
    }
    
    /// Get all active subscriptions
    public var activeSubscriptions: [NDKSubscription] {
        get async {
            var active: [NDKSubscription] = []
            for subscription in subscriptions {
                if await subscription.state != .closed {
                    active.append(subscription)
                }
            }
            return active
        }
    }
}

extension NDK {
    /// Create a subscription group for managing multiple subscriptions
    public func subscriptionGroup() -> NDKSubscriptionGroup {
        return NDKSubscriptionGroup(ndk: self)
    }
}
