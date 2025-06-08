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
public class AutoClosingSubscription {
    private let subscription: NDKSubscription
    
    public var onEvent: ((NDKEvent) -> Void)? {
        get { nil }
        set {
            if let handler = newValue {
                subscription.onEvent(handler)
            }
        }
    }
    
    public var onEOSE: (() -> Void)? {
        get { nil }
        set {
            if let handler = newValue {
                subscription.onEOSE(handler)
            }
        }
    }
    
    public var onError: ((Error) -> Void)? {
        get { nil }
        set {
            if let handler = newValue {
                subscription.onError(handler)
            }
        }
    }
    
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

/// Async sequence for subscription events
public struct SubscriptionEventSequence: AsyncSequence {
    public typealias Element = NDKEvent
    
    private let subscription: NDKSubscription
    
    init(_ subscription: NDKSubscription) {
        self.subscription = subscription
    }
    
    public func makeAsyncIterator() -> AsyncIterator {
        return AsyncIterator(subscription: subscription)
    }
    
    public struct AsyncIterator: AsyncIteratorProtocol {
        private let subscription: NDKSubscription
        private let stream: AsyncStream<NDKEvent>
        private var iterator: AsyncStream<NDKEvent>.AsyncIterator
        
        init(subscription: NDKSubscription) {
            self.subscription = subscription
            
            let (stream, continuation) = AsyncStream<NDKEvent>.makeStream()
            self.stream = stream
            self.iterator = stream.makeAsyncIterator()
            
            subscription.onEvent { event in
                continuation.yield(event)
            }
            
            subscription.onEOSE {
                // Don't finish on EOSE for continuous subscriptions
            }
            
            subscription.onError { _ in
                continuation.finish()
            }
            
            // Start the subscription if not already started
            if subscription.state == .pending {
                subscription.start()
            }
        }
        
        public mutating func next() async -> NDKEvent? {
            return await iterator.next()
        }
    }
}

extension NDKSubscription {
    /// Get an async sequence of events from this subscription
    public var events: SubscriptionEventSequence {
        return SubscriptionEventSequence(self)
    }
}