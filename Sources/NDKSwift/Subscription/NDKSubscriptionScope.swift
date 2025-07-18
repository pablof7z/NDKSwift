import Foundation

private extension Array where Element: Hashable {
    var set: Set<Element> {
        Set(self)
    }
}

/// Provides scoped subscription management with automatic cleanup
public extension NDK {
    /// Execute a block with a subscription that automatically closes when the block exits
    func withSubscription<T>(
        _ filter: NDKFilter,
        options: NDKSubscriptionOptions = NDKSubscriptionOptions(),
        handler: (NDKSubscription) async throws -> T
    ) async rethrows -> T {
        let subscription = await subscribe(
            filters: [filter], 
            relays: options.relays?.compactMap { $0.url }.set,
            id: nil,
            closeOnEose: options.closeOnEose
        )
        // Note: subscription.start() removed to prevent duplicate REQ messages
        // The subscription is already started by NDKSubscriptionManager via subscribe()
        
        defer {
            Task {
                await subscription.close()
            }
        }
        
        return try await handler(subscription)
    }
    
    /// Execute a block with multiple subscriptions that automatically close when the block exits
    func withSubscriptions<T>(
        _ filters: [NDKFilter],
        options: NDKSubscriptionOptions = NDKSubscriptionOptions(),
        handler: ([NDKSubscription]) async throws -> T
    ) async rethrows -> T {
        var subscriptions: [NDKSubscription] = []
        for filter in filters {
            let sub = await subscribe(
                filters: [filter], 
                relays: options.relays?.compactMap { $0.url }.set,
                id: nil,
                closeOnEose: options.closeOnEose
            )
            // Note: sub.start() removed to prevent duplicate REQ messages
            // The subscription is already started by NDKSubscriptionManager via subscribe()
            subscriptions.append(sub)
        }
        
        defer {
            Task {
                for subscription in subscriptions {
                    await subscription.close()
                }
            }
        }
        
        return try await handler(subscriptions)
    }
    
    /// Execute a block with a subscription group that automatically closes when the block exits
    func withSubscriptionGroup<T>(
        handler: (NDKSubscriptionGroup) async throws -> T
    ) async rethrows -> T {
        let group = subscriptionGroup()
        
        do {
            let result = try await handler(group)
            await group.closeAll()
            return result
        } catch {
            await group.closeAll()
            throw error
        }
    }
}

/// A subscription wrapper that automatically closes on deinitialization
public class AutoClosingSubscription: AsyncSequence {
    public typealias Element = NDKEvent
    
    private let subscription: NDKSubscription
    
    public init(_ subscription: NDKSubscription, autoStart: Bool = true) {
        self.subscription = subscription
        if autoStart {
            Task {
                // Note: subscription.start() removed to prevent duplicate REQ messages
        // The subscription is already started by NDKSubscriptionManager via subscribe()
            }
        }
    }
    
    deinit {
        Task { [subscription] in
            await subscription.close()
        }
    }
    
    /// Start the subscription if it was created with autoStart = false
    public func start() {
        Task {
            // Note: subscription.start() removed to prevent duplicate REQ messages
        // The subscription is already started by NDKSubscriptionManager via subscribe()
        }
    }
    
    /// Get the underlying subscription
    public var underlying: NDKSubscription {
        return subscription
    }
    
    /// AsyncSequence conformance - delegate to underlying subscription
    public func makeAsyncIterator() -> NDKSubscription.AsyncIterator {
        subscription.makeAsyncIterator()
    }
    
    // Note: NDKSubscription doesn't have updates property anymore.
    // Use the AsyncSequence directly to iterate over events.
}

extension NDK {
    /// Create an auto-closing subscription
    public func autoSubscribe(
        filters: [NDKFilter],
        options: NDKSubscriptionOptions = NDKSubscriptionOptions()
    ) async -> AutoClosingSubscription {
        let subscription = await subscribe(
            filters: filters, 
            relays: options.relays?.compactMap { $0.url }.set,
            id: nil,
            closeOnEose: options.closeOnEose
        )
        return AutoClosingSubscription(subscription)
    }
    
    /// Create an auto-closing subscription with a single filter
    public func autoSubscribe(
        filter: NDKFilter,
        options: NDKSubscriptionOptions = NDKSubscriptionOptions()
    ) async -> AutoClosingSubscription {
        return await autoSubscribe(filters: [filter], options: options)
    }
}

/// A subscription handle that can be cancelled
public struct SubscriptionHandle {
    private let subscription: NDKSubscription
    
    init(_ subscription: NDKSubscription) {
        self.subscription = subscription
    }
    
    /// Cancel the subscription
    public func cancel() async {
        await subscription.close()
    }
    
    /// Check if the subscription is still active
    public var isActive: Bool {
        get async {
            return !subscription.isClosed
        }
    }
}
