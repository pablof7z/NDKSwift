import Foundation

/// Provides scoped subscription management with automatic cleanup
public extension NDK {
    /// Execute a block with a subscription that automatically closes when the block exits
    func withSubscription<T>(
        _ filter: NDKFilter,
        options: NDKSubscriptionOptions = NDKSubscriptionOptions(),
        handler: (NDKSubscription) async throws -> T
    ) async rethrows -> T {
        let subscription = subscribe(filters: [filter], options: options)
        subscription.start()
        
        defer {
            subscription.close()
        }
        
        return try await handler(subscription)
    }
    
    /// Execute a block with multiple subscriptions that automatically close when the block exits
    func withSubscriptions<T>(
        _ filters: [NDKFilter],
        options: NDKSubscriptionOptions = NDKSubscriptionOptions(),
        handler: ([NDKSubscription]) async throws -> T
    ) async rethrows -> T {
        let subscriptions = filters.map { filter in
            let sub = subscribe(filters: [filter], options: options)
            sub.start()
            return sub
        }
        
        defer {
            for subscription in subscriptions {
                subscription.close()
            }
        }
        
        return try await handler(subscriptions)
    }
    
    /// Execute a block with a subscription group that automatically closes when the block exits
    func withSubscriptionGroup<T>(
        handler: (NDKSubscriptionGroup) async throws -> T
    ) async rethrows -> T {
        let group = subscriptionGroup()
        
        defer {
            group.closeAll()
        }
        
        return try await handler(group)
    }
}

/// A subscription wrapper that automatically closes on deinitialization
public class AutoClosingSubscription: AsyncSequence {
    public typealias Element = NDKEvent
    
    private let subscription: NDKSubscription
    
    public init(_ subscription: NDKSubscription, autoStart: Bool = true) {
        self.subscription = subscription
        if autoStart {
            subscription.start()
        }
    }
    
    deinit {
        subscription.close()
    }
    
    /// Start the subscription if it was created with autoStart = false
    public func start() {
        subscription.start()
    }
    
    /// Get the underlying subscription
    public var underlying: NDKSubscription {
        return subscription
    }
    
    /// AsyncSequence conformance - delegate to underlying subscription
    public func makeAsyncIterator() -> NDKSubscription.AsyncIterator {
        subscription.makeAsyncIterator()
    }
    
    /// Access to update stream for EOSE and errors
    public var updates: AsyncStream<NDKSubscriptionUpdate> {
        subscription.updates
    }
}

extension NDK {
    /// Create an auto-closing subscription
    public func autoSubscribe(
        filters: [NDKFilter],
        options: NDKSubscriptionOptions = NDKSubscriptionOptions()
    ) -> AutoClosingSubscription {
        let subscription = subscribe(filters: filters, options: options)
        return AutoClosingSubscription(subscription)
    }
    
    /// Create an auto-closing subscription with a single filter
    public func autoSubscribe(
        filter: NDKFilter,
        options: NDKSubscriptionOptions = NDKSubscriptionOptions()
    ) -> AutoClosingSubscription {
        return autoSubscribe(filters: [filter], options: options)
    }
}

/// A subscription handle that can be cancelled
public struct SubscriptionHandle {
    private let subscription: NDKSubscription
    
    init(_ subscription: NDKSubscription) {
        self.subscription = subscription
    }
    
    /// Cancel the subscription
    public func cancel() {
        subscription.close()
    }
    
    /// Check if the subscription is still active
    public var isActive: Bool {
        return subscription.state != .closed
    }
}

