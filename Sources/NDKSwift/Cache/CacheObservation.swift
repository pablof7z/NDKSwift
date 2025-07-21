import Foundation

/// Protocol for objects that observe cache changes
public protocol CacheObserver: AnyObject {
    /// Called when a new event matching the observer's filter is added to cache
    func handleEvent(_ event: NDKEvent) async
    
    /// Called when a relay update is received (optional)
    func handleRelayUpdate(_ update: RelayUpdate) async
}

// Default implementation for backward compatibility
public extension CacheObserver {
    func handleRelayUpdate(_ update: RelayUpdate) async {
        // Default implementation does nothing
    }
}

/// Handle for managing observation lifecycle
public struct ObservationHandle {
    private let cancellation: () async -> Void
    
    public init(cancellation: @escaping () async -> Void) {
        self.cancellation = cancellation
    }
    
    /// Stop observing cache changes
    public func cancel() async {
        await cancellation()
    }
}

/// Weak wrapper for cache observers to prevent retain cycles
struct WeakObserver: Hashable {
    weak var observer: CacheObserver?
    private let objectIdentifier: ObjectIdentifier
    
    init(observer: CacheObserver) {
        self.observer = observer
        self.objectIdentifier = ObjectIdentifier(observer)
    }
    
    static func == (lhs: WeakObserver, rhs: WeakObserver) -> Bool {
        lhs.objectIdentifier == rhs.objectIdentifier
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(objectIdentifier)
    }
}

/// Filter signature for efficient matching
struct FilterSignature: Hashable {
    let kinds: [Int]?
    let authors: [String]?
    let ids: [String]?
    let tags: [String: [String]]?
    
    init(from filter: NDKFilter) {
        self.kinds = filter.kinds?.sorted()
        self.authors = filter.authors?.sorted()
        self.ids = filter.ids?.sorted()
        self.tags = filter.tags?.mapValues { $0.sorted() }
    }
}