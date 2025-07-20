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

/// Primary API for declarative data access in NDKSwift
/// Automatically manages subscriptions, caching, and lifecycle
public final class NDKDataSource<T>: ObservableObject, DataSourceObserver {
    @Published public private(set) var data: [T] = []
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var error: Error?
    
    /// AsyncStream for consuming events as they arrive
    public let events: AsyncStream<T>
    private let eventsContinuation: AsyncStream<T>.Continuation
    
    private let filter: NDKFilter
    private let ndk: NDK
    private let transform: (NDKEvent) -> T?
    private let maxAge: TimeInterval
    private let cachePolicy: CachePolicy
    private let relays: Set<RelayURL>?
    private var requirementHandle: DataRequirementHandle?
    private var task: Task<Void, Never>?
    
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
        relays: Set<RelayURL>? = nil
    ) where T == NDKEvent {
        self.init(
            ndk: ndk,
            filter: filter,
            maxAge: maxAge,
            cachePolicy: cachePolicy,
            relays: relays,
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
    ///   - transform: Optional transform to convert NDKEvent to custom type
    public init(
        ndk: NDK,
        filter: NDKFilter,
        maxAge: TimeInterval = 0,
        cachePolicy: CachePolicy = .cacheWithNetwork,
        relays: Set<RelayURL>? = nil,
        transform: @escaping (NDKEvent) -> T?
    ) {
        self.ndk = ndk
        self.filter = filter
        self.transform = transform
        self.maxAge = maxAge
        self.cachePolicy = cachePolicy
        self.relays = relays
        
        // Set up the AsyncStream
        var continuation: AsyncStream<T>.Continuation!
        self.events = AsyncStream { cont in
            continuation = cont
        }
        self.eventsContinuation = continuation
        
        // Start observing immediately
        task = Task { [weak self] in
            await self?.startObserving()
        }
    }
    
    deinit {
        task?.cancel()
        eventsContinuation.finish()
        Task {
            await requirementHandle?.release()
        }
    }
    
    private func startObserving() async {
        isLoading = true
        error = nil
        
        // Use the new data requirement manager if available
        if let requirementManager = await ndk.dataRequirementManager {
            requirementHandle = await requirementManager.registerRequirement(
                filter: filter,
                observer: self,
                maxAge: maxAge,
                cachePolicy: cachePolicy,
                relays: relays
            )
        } else {
            // No data requirement manager available
            print("[NDKDataSource] Warning: No data requirement manager available")
        }
        
        isLoading = false
    }
    
    // MARK: - DataSourceObserver
    
    nonisolated func handleEvent(_ event: NDKEvent) async {
        // Check if we've already processed this event
        guard await !stateManager.isProcessed(event.id) else { return }
        await stateManager.markProcessed(event.id)
        
        if let transformed = transform(event) {
            // Yield to AsyncStream
            eventsContinuation.yield(transformed)
            
            // Update @Published property on MainActor
            await MainActor.run {
                data.append(transformed)
            }
        }
    }
    
    nonisolated func handleError(_ error: Error) async {
        await MainActor.run {
            self.error = error
            self.isLoading = false
        }
    }
    
    /// Manually refresh the data
    public func refresh() async {
        data.removeAll()
        await stateManager.clearProcessed()
        await requirementHandle?.release()
        requirementHandle = nil
        await startObserving()
    }
    
    /// Get the current data snapshot
    /// Useful for internal components that need one-shot access
    public func currentValue() async -> [T] {
        return data
    }
}

/// Options for configuring data source behavior
public struct DataSourceOptions {
    public let updatePolicy: UpdatePolicy
    public let deduplication: DeduplicationStrategy
    
    public init(
        updatePolicy: UpdatePolicy = .continuous,
        deduplication: DeduplicationStrategy = .byEventId
    ) {
        self.updatePolicy = updatePolicy
        self.deduplication = deduplication
    }
    
    public static let `default` = DataSourceOptions()
}

public enum UpdatePolicy {
    case continuous  // Keep subscription open
    case oneShot    // Close after EOSE
}

public enum DeduplicationStrategy {
    case byEventId
    case none
    case custom((NDKEvent, NDKEvent) -> Bool)
}