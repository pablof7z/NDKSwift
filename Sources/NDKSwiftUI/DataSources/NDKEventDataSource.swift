import Foundation
import NDKSwiftCore
import Observation
import SwiftUI

// MARK: - NDKEventDataSource

/// Observable data source for Nostr events with flexible filtering
///
/// This data source provides reactive access to filtered events with:
/// - Real-time streaming updates
/// - Configurable sorting (newest first by default)
/// - Automatic caching and network fallback
/// - Progressive loading of event streams
/// - Memory efficient subscription management
///
/// ## Usage
///
/// ```swift
/// // Feed of text notes
/// @State private var feedDataSource = NDKEventDataSource(
///     ndk: ndk,
///     filter: NDKFilter(kinds: [1], limit: 20)
/// )
///
/// // User's posts
/// @State private var userPostsDataSource = NDKEventDataSource(
///     ndk: ndk,
///     filter: NDKFilter(authors: [pubkey], kinds: [1])
/// )
/// ```
@Observable
@MainActor
public final class NDKEventDataSource: @preconcurrency NDKSubscriptionProtocol {
    // MARK: - Published Properties

    /// Array of events matching the filter, sorted by creation time
    public private(set) var events: [NDKEvent] = []

    /// Whether the data source is currently loading
    public private(set) var isLoading = false

    /// Any error that occurred during loading
    public private(set) var error: Error?

    // MARK: - Private Properties

    private let ndk: NDK
    private let filter: NDKFilter
    private let sortDescending: Bool
    private let dataSource: NDKSubscription<NDKEvent>
    @ObservationIgnored private var observationTask: Task<Void, Never>?

    // MARK: - Initialization

    /// Initialize an event data source with a filter
    /// - Parameters:
    ///   - ndk: The NDK instance to use for data fetching
    ///   - filter: The filter to apply to events
    ///   - sortDescending: Whether to sort events newest first (default: true)
    ///   - maxAge: Maximum age of cached data in seconds (default: 0 for real-time)
    public init(
        ndk: NDK,
        filter: NDKFilter,
        sortDescending: Bool = true,
        maxAge: TimeInterval = 0
    ) {
        self.ndk = ndk
        self.filter = filter
        self.sortDescending = sortDescending

        // Create data source with the provided filter
        dataSource = ndk.subscribe(
            filter: filter,
            maxAge: maxAge,
            cachePolicy: .cacheWithNetwork
        )

        // Start observing events
        observeEventData()
    }

    deinit {
        observationTask?.cancel()
    }

    // MARK: - Private Methods

    private func observeEventData() {
        observationTask = Task { @MainActor in
            var eventList: [NDKEvent] = []

            for await event in dataSource.events {
                eventList.append(event)

                // Sort events
                events = sortDescending
                    ? eventList.sorted { $0.createdAt > $1.createdAt }
                    : eventList.sorted { $0.createdAt < $1.createdAt }
            }
        }

        // Observe loading and error states
        Task { @MainActor in
            while !Task.isCancelled {
                isLoading = dataSource.isLoading
                error = dataSource.error
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
            }
        }
    }

    // MARK: - Public Methods

    /// Get events of a specific kind
    public func events(ofKind kind: Int) -> [NDKEvent] {
        events.filter { $0.kind == kind }
    }

    /// Get events by a specific author
    public func events(byAuthor pubkey: String) -> [NDKEvent] {
        events.filter { $0.pubkey == pubkey }
    }

    /// Get the most recent event, if any
    public var latestEvent: NDKEvent? {
        events.first
    }

    /// Get the total count of events
    public var eventCount: Int {
        events.count
    }
}
