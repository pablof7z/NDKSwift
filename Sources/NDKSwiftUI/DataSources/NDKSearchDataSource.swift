import Foundation
import NDKSwiftCore
import Observation
import SwiftUI

// MARK: - NDKSearchDataSource

/// Observable data source for nostrdb text search
///
/// This data source provides reactive search results from nostrdb's local full-text search:
/// - Searches cached events in local nostrdb database
/// - Updates on every query change
/// - Returns up to specified limit of results
///
/// ## Usage
///
/// ```swift
/// @State private var searchDataSource = NDKSearchDataSource(ndk: ndk)
///
/// // Search updates automatically when query changes
/// searchDataSource.search(query: "bitcoin")
/// ```
@Observable
@MainActor
public final class NDKSearchDataSource {
    // MARK: - Published Properties

    /// Array of events matching the search query
    public private(set) var events: [NDKEvent] = []

    /// Whether the search is currently executing
    public private(set) var isLoading = false

    /// Any error that occurred during search
    public private(set) var error: Error?

    /// Current search query
    public private(set) var query: String = ""

    // MARK: - Private Properties

    private let ndk: NDK
    private let limit: Int
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    // MARK: - Initialization

    /// Initialize a search data source
    /// - Parameters:
    ///   - ndk: The NDK instance
    ///   - limit: Maximum number of results to return (default: 100)
    public init(ndk: NDK, limit: Int = 100) {
        self.ndk = ndk
        self.limit = limit
    }

    deinit {
        searchTask?.cancel()
    }

    // MARK: - Public Methods

    /// Execute a search query
    /// - Parameter query: The search query string
    public func search(query: String) {
        self.query = query

        // Cancel any existing search
        searchTask?.cancel()

        // Clear results if query is empty
        guard !query.isEmpty else {
            events = []
            isLoading = false
            error = nil
            return
        }

        // Execute search OFF main thread
        searchTask = Task {
            // Set loading state on main thread
            await MainActor.run {
                isLoading = true
                error = nil
            }

            // Perform search (off main thread - won't block UI)
            let cache = ndk.cache
            let results = await cache.textSearch(query, limit: limit)

            // Update results on main thread only if not cancelled
            await MainActor.run {
                guard !Task.isCancelled else { return }
                events = results
                isLoading = false
            }
        }
    }

    /// Clear search results and query
    public func clear() {
        searchTask?.cancel()
        query = ""
        events = []
        isLoading = false
        error = nil
    }
}
