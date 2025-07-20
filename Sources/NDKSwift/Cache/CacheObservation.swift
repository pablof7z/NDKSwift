import Foundation

/// Protocol for objects that observe cache changes
public protocol CacheObserver: AnyObject {
    /// Called when a new event matching the observer's filter is added to cache
    func handleEvent(_ event: NDKEvent) async
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
    private let id = UUID()
    
    init(_ observer: CacheObserver) {
        self.observer = observer
    }
    
    static func == (lhs: WeakObserver, rhs: WeakObserver) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Filter signature for efficient matching
struct FilterSignature: Hashable {
    let kinds: [Int]?
    let authors: [String]?
    let tags: [String: [String]]?
    
    init(from filter: NDKFilter) {
        self.kinds = filter.kinds?.sorted()
        self.authors = filter.authors?.sorted()
        self.tags = filter.tags?.mapValues { $0.sorted() }
    }
}