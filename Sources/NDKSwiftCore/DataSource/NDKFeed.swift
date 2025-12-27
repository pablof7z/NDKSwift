import Foundation
import Observation

/// UI-optimized feed that accumulates events from an NDKSubscription
///
/// NDKFeed provides a MainActor-isolated, observable collection of events
/// optimized for SwiftUI rendering. It consumes events from an NDKSubscription's
/// AsyncStream and maintains a sorted, deduplicated list.
///
/// ## Usage
/// ```swift
/// let filter = NDKFilter(kinds: [1], limit: 100)
/// let feed = ndk.feed(filter: filter)
///
/// // In SwiftUI:
/// List(feed.events) { event in
///     EventRow(event: event)
/// }
/// ```
///
/// ## Thread Safety
/// NDKFeed is isolated to MainActor, making it safe for direct UI binding.
/// The underlying NDKSubscription handles all networking on background threads.
@Observable
@MainActor
public final class NDKFeed {
    /// Sorted events (newest first by default)
    public private(set) var events: [NDKEvent] = []

    /// Number of events in the feed
    public var count: Int { events.count }

    /// Whether the feed is empty
    public var isEmpty: Bool { events.isEmpty }

    /// Internal storage with timestamps for efficient sorting
    private var sortedData: [(event: NDKEvent, timestamp: Timestamp)] = []

    /// Set of event IDs for deduplication
    private var eventIds: Set<String> = []

    /// Thread-safe cancellation handle for deinit
    private let cancellation = CancellationHandle()

    /// Sort order for events
    private let newestFirst: Bool

    /// Creates a new NDKFeed
    /// - Parameter newestFirst: If true, sorts events newest-first (default). If false, oldest-first.
    public init(newestFirst: Bool = true) {
        self.newestFirst = newestFirst
    }

    deinit {
        cancellation.cancel()
    }

    /// Start observing events from a subscription
    /// - Parameter subscription: The subscription to consume events from
    public func observe(_ subscription: NDKSubscription<NDKEvent>) {
        let cancellation = self.cancellation

        Task { [weak self] in
            for await batch in subscription.events {
                guard !cancellation.isCancelled else { break }
                guard let self else { break }

                await MainActor.run {
                    self.addEvents(batch)
                }
            }
        }
    }

    /// Get event at a specific index
    /// - Parameter index: The index to retrieve
    /// - Returns: The event at that index, or nil if out of bounds
    public func event(at index: Int) -> NDKEvent? {
        guard index >= 0, index < sortedData.count else { return nil }
        return sortedData[index].event
    }

    /// Clear all events from the feed
    public func clear() {
        sortedData.removeAll()
        eventIds.removeAll()
        events = []
    }

    // MARK: - Private

    private func addEvents(_ newEvents: [NDKEvent]) {
        var added = false

        for event in newEvents {
            // Skip duplicates
            guard !eventIds.contains(event.id) else { continue }
            eventIds.insert(event.id)

            // Binary search for insertion point
            let timestamp = event.createdAt
            let insertIndex: Int

            if newestFirst {
                // Newest first: find first item with smaller timestamp
                insertIndex = sortedData.firstIndex { $0.timestamp < timestamp } ?? sortedData.endIndex
            } else {
                // Oldest first: find first item with larger timestamp
                insertIndex = sortedData.firstIndex { $0.timestamp > timestamp } ?? sortedData.endIndex
            }

            sortedData.insert((event: event, timestamp: timestamp), at: insertIndex)
            added = true
        }

        // Only rebuild events array if something changed
        if added {
            events = sortedData.map { $0.event }
        }
    }
}

/// Thread-safe cancellation handle that can be accessed from deinit
private final class CancellationHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var _isCancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isCancelled
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        _isCancelled = true
    }
}
