import Foundation
import Combine

/// Defines how the cache should be used for data requests
public enum CachePolicy {
    /// Return cached data if available and fresh, otherwise fetch from network
    case cacheWithNetwork
    /// Only return data from the cache; never hit the network
    case cacheOnly
    /// Always fetch from the network, ignoring any cached data
    case networkOnly
}

/// Relay-level update information
public enum RelayUpdate {
    /// Event received from a specific relay
    case event(NDKEvent, relay: String)
    /// End of stored events from a specific relay
    case eose(relay: String)
    /// Subscription closed on a specific relay
    case closed(relay: String)
}

/// Primary API for declarative data access in NDKSwift
/// Automatically manages subscriptions, caching, and lifecycle
public final class NDKDataSource<T>: ObservableObject, CacheObserver {
    @Published public private(set) var data: [T] = []
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var error: Error?
    
    /// AsyncStream for consuming events as they arrive
    public let events: AsyncStream<T>
    private let eventsContinuation: AsyncStream<T>.Continuation
    
    /// Relay-level updates (events, EOSE, closed)
    public let relayUpdates: AsyncStream<RelayUpdate>
    private let relayUpdatesContinuation: AsyncStream<RelayUpdate>.Continuation
    
    private let filter: NDKFilter
    private let ndk: NDK
    private let transform: (NDKEvent) -> T?
    private let maxAge: TimeInterval
    private let cachePolicy: CachePolicy
    private let relays: Set<RelayURL>?
    private var requirementHandle: DataRequirementHandle?
    private var task: Task<Void, Never>?
    private let correlationId: String
    private let subscriptionId: String?
    
    // Actor for thread-safe state management
    private actor StateManager {
        var processedEventIds = Set<String>()
        
        func isProcessed(_ eventId: String) -> Bool {
            processedEventIds.contains(eventId)
        }
        
        func markProcessed(_ eventId: String) {
            processedEventIds.insert(eventId)
        }
        
        func clearProcessed() {
            processedEventIds.removeAll()
        }
    }
    
    private let stateManager = StateManager()
    
    /// Initialize a data source for NDKEvent objects
    public convenience init(
        ndk: NDK,
        filter: NDKFilter,
        maxAge: TimeInterval = 0,
        cachePolicy: CachePolicy = .cacheWithNetwork,
        relays: Set<RelayURL>? = nil,
        subscriptionId: String? = nil
    ) where T == NDKEvent {
        self.init(
            ndk: ndk,
            filter: filter,
            maxAge: maxAge,
            cachePolicy: cachePolicy,
            relays: relays,
            subscriptionId: subscriptionId,
            transform: { $0 }
        )
    }
    
    /// Initialize a data source with custom transform
    /// - Parameters:
    ///   - ndk: The NDK instance to use for fetching data
    ///   - filter: The NDKFilter describing the data requirement
    ///   - maxAge: Maximum age of cached data to consider fresh (in seconds).
    ///             0 = keep subscription open for real-time updates.
    ///             >0 = use cache if fresh enough, otherwise fetch and close after EOSE
    ///   - cachePolicy: Defines how the cache should be used for this request
    ///   - relays: Optional set of specific relay URLs to query
    ///   - subscriptionId: Optional custom subscription ID to use (for debugging/tracing)
    ///   - transform: Optional transform to convert NDKEvent to custom type
    public init(
        ndk: NDK,
        filter: NDKFilter,
        maxAge: TimeInterval = 0,
        cachePolicy: CachePolicy = .cacheWithNetwork,
        relays: Set<RelayURL>? = nil,
        subscriptionId: String? = nil,
        transform: @escaping (NDKEvent) -> T?
    ) {
        self.ndk = ndk
        self.filter = filter
        self.transform = transform
        self.maxAge = maxAge
        self.cachePolicy = cachePolicy
        self.relays = relays
        self.correlationId = IDGenerator.randomId(length: 8)
        self.subscriptionId = subscriptionId
        
        // Set up the AsyncStream for events
        var continuation: AsyncStream<T>.Continuation!
        self.events = AsyncStream { cont in
            continuation = cont
        }
        self.eventsContinuation = continuation
        
        // Set up the AsyncStream for relay updates
        var relayUpdatesCont: AsyncStream<RelayUpdate>.Continuation!
        self.relayUpdates = AsyncStream { cont in
            relayUpdatesCont = cont
        }
        self.relayUpdatesContinuation = relayUpdatesCont
        
        // Start observing immediately
        task = Task { [weak self] in
            guard let self = self else { return }
            await self.startObserving()
        }
    }
    
    deinit {
        NDKLogger.log(.debug, category: .subscription, "🔚 NDKDataSource deinit - Cleaning up resources", correlationId: correlationId)
        task?.cancel()
        eventsContinuation.finish()
        relayUpdatesContinuation.finish()
        let handle = requirementHandle
        Task {
            await handle?.release()
        }
    }
    
    private func startObserving() async {
        isLoading = true
        error = nil
        
        // Use the new data requirement manager if available
        if let requirementManager = ndk.dataRequirementManager {
            requirementHandle = await requirementManager.registerRequirement(
                filter: filter,
                observer: self,
                maxAge: maxAge,
                cachePolicy: cachePolicy,
                relays: relays,
                subscriptionId: subscriptionId
            )
        } else {
            // No data requirement manager available
            NDKLogger.log(.error, category: .subscription, "❌ No data requirement manager available! Data source will not receive events", correlationId: correlationId)
            if ndk.debugMode {
                print("[NDKDataSource] Warning: No data requirement manager available")
            }
        }
        
        isLoading = false
    }
    
    // MARK: - CacheObserver
    
    public func handleEvent(_ event: NDKEvent) async {
        NDKLogger.log(.trace, category: .subscription, "📥 Received event - id: \(event.id), kind: \(event.kind), author: \(String(event.pubkey.prefix(8)))...", correlationId: correlationId)
        
        // Check if we've already processed this event
        guard await !stateManager.isProcessed(event.id) else {
            NDKLogger.log(.trace, category: .subscription, "⏭️ Skipping duplicate event - id: \(event.id)", correlationId: correlationId)
            return
        }
        await stateManager.markProcessed(event.id)
        
        NDKLogger.log(.debug, category: .subscription, "🔄 Processing new event - id: \(event.id)", correlationId: correlationId)
        
        if let transformed = transform(event) {
            NDKLogger.log(.trace, category: .subscription, "✅ Transform successful - yielding to stream and updating data", correlationId: correlationId)
            
            // Yield to AsyncStream
            eventsContinuation.yield(transformed)
            
            // Update @Published property on MainActor
            await MainActor.run {
                data.append(transformed)
                NDKLogger.log(.trace, category: .subscription, "📈 Data array updated - count: \(self.data.count)", correlationId: self.correlationId)
            }
        } else {
            NDKLogger.log(.trace, category: .subscription, "❌ Transform failed - event not added to data", correlationId: correlationId)
        }
    }
    
    /// Handle relay-level updates (EOSE, subscription status, etc)
    /// This needs to be called by the internal subscription system
    public func handleRelayUpdate(_ update: RelayUpdate) async {
        relayUpdatesContinuation.yield(update)
    }
    
    /// Manually refresh the data
    public func refresh() async {
        NDKLogger.log(.info, category: .subscription, "🔄 Refreshing data source", correlationId: correlationId)
        data.removeAll()
        await stateManager.clearProcessed()
        
        if let handle = requirementHandle {
            NDKLogger.log(.debug, category: .subscription, "Releasing existing requirement handle", correlationId: correlationId)
            await handle.release()
        }
        requirementHandle = nil
        
        NDKLogger.log(.debug, category: .subscription, "Restarting observation", correlationId: correlationId)
        await startObserving()
    }
    
    /// Get the current data snapshot
    /// Useful for internal components that need one-shot access
    public func currentValue() async -> [T] {
        return data
    }
}