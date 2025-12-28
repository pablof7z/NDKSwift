import Foundation
import NDKSwiftCore
import NDKSwiftNostrDB
import Observation
import SwiftUI

// MARK: - NDKUnifiedSearchDataSource

/// Unified search data source supporting multiple search modes
///
/// This data source intelligently routes search queries based on input type:
/// - Plain text: Searches both events and profiles in local cache
/// - `@prefix`: Profile-only search
/// - `#hashtag`: Defers search until submit, then queries relays
/// - `npub1...`, `nprofile1...`: Triggers navigation to profile
/// - `note1...`, `nevent1...`: Triggers navigation to event
/// - `user@domain.com`: Resolves NIP-05 and triggers navigation
///
/// ## Usage
///
/// ```swift
/// @State private var searchDataSource: NDKUnifiedSearchDataSource?
///
/// // Initialize
/// searchDataSource = NDKUnifiedSearchDataSource(ndk: ndk)
///
/// // Search updates automatically based on input classification
/// await searchDataSource?.search(query: "bitcoin")
///
/// // For hashtag search, call submit when user presses return
/// await searchDataSource?.submitHashtagSearch()
///
/// // Handle navigation signals
/// if let pubkey = searchDataSource?.navigateToProfile {
///     // Navigate to profile
///     searchDataSource?.acknowledgeNavigation()
/// }
/// ```
@Observable
@MainActor
public final class NDKUnifiedSearchDataSource {
    // MARK: - Result Properties

    /// Array of events matching the search query
    public private(set) var events: [NDKEvent] = []

    /// Array of profile pubkeys matching the search query
    public private(set) var profilePubkeys: [String] = []

    /// Whether a hashtag search has been submitted (to distinguish "not searched yet" from "no results")
    public private(set) var hasSubmittedHashtagSearch = false

    /// Whether NIP-05 resolution is in progress
    public private(set) var isResolvingNIP05 = false

    /// Any error that occurred during search
    public private(set) var error: Error?

    /// Current search query (raw input)
    public private(set) var query: String = ""

    /// Classified input type for the current query
    public private(set) var inputType: NDKSearchInputType = .empty

    /// Whether nostrdb cache is available
    public private(set) var isNostrDBAvailable: Bool = false

    // MARK: - Navigation Signals

    /// Pubkey to navigate to (for npub, nprofile, nip-05 resolution)
    public private(set) var navigateToProfile: String?

    /// Relay hints for profile navigation
    public private(set) var navigateToProfileRelays: [String]?

    /// Event ID to navigate to (for note, nevent)
    public private(set) var navigateToEvent: String?

    /// Relay hints for event navigation
    public private(set) var navigateToEventRelays: [String]?

    /// Author pubkey for event navigation (if available from nevent)
    public private(set) var navigateToEventAuthor: String?

    // MARK: - Private Properties

    private let ndk: NDK
    private let limit: Int
    private let debounceInterval: TimeInterval

    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var hashtagStreamTask: Task<Void, Never>?

    // MARK: - Initialization

    /// Initialize a unified search data source
    /// - Parameters:
    ///   - ndk: The NDK instance (preferably with nostrdb cache for best performance)
    ///   - limit: Maximum number of results to return (default: 50)
    ///   - debounceInterval: Debounce interval for text searches (default: 0.15 seconds)
    public init(ndk: NDK, limit: Int = 50, debounceInterval: TimeInterval = 0.15) {
        self.ndk = ndk
        self.limit = limit
        self.debounceInterval = debounceInterval
        self.isNostrDBAvailable = ndk.cache is NDKNostrDBCache
    }

    deinit {
        searchTask?.cancel()
        debounceTask?.cancel()
        hashtagStreamTask?.cancel()
    }

    // MARK: - Public Methods

    /// Process a search query - classifies input and routes appropriately
    ///
    /// This method analyzes the input and performs the appropriate action:
    /// - For text/profile searches: Searches local cache with debouncing
    /// - For hashtag: Just updates inputType (call `submitHashtagSearch` to execute)
    /// - For bech32 identifiers: Decodes and sets navigation signal
    /// - For NIP-05: Resolves and sets navigation signal
    ///
    /// - Parameter query: The raw user input string
    public func search(query: String) {
        self.query = query
        let classified = NDKSearchInput.classify(query)
        self.inputType = classified

        // Cancel any pending operations
        debounceTask?.cancel()
        searchTask?.cancel()

        // Clear navigation state
        clearNavigationState()

        switch classified {
        case .empty:
            clearResults()

        case .text(let searchQuery):
            // Debounce text search
            debounceAndSearch(searchQuery, profileOnly: false)

        case .profileOnly(let searchQuery):
            // Debounce profile-only search
            if searchQuery.isEmpty {
                clearResults()
            } else {
                debounceAndSearch(searchQuery, profileOnly: true)
            }

        case .hashtag:
            // Don't search yet - wait for submit
            clearResults()

        case .npub(let pubkey):
            // Direct navigation
            navigateToProfile = pubkey
            clearResults()

        case .nprofile(let pubkey, let relays):
            // Direct navigation with relay hints
            navigateToProfile = pubkey
            navigateToProfileRelays = relays.isEmpty ? nil : relays
            clearResults()

        case .note(let eventId):
            // Direct navigation
            navigateToEvent = eventId
            clearResults()

        case .nevent(let eventId, let relays, let author):
            // Direct navigation with hints
            navigateToEvent = eventId
            navigateToEventRelays = relays.isEmpty ? nil : relays
            navigateToEventAuthor = author
            clearResults()

        case .nip05(let identifier):
            // Resolve NIP-05
            resolveNIP05(identifier)
        }
    }

    /// Submit hashtag search (called when user presses return/submit)
    ///
    /// For hashtag searches, this triggers the actual relay query.
    /// Call this when the user explicitly submits the search.
    public func submitHashtagSearch() async {
        guard case .hashtag(let tag) = inputType else { return }

        // Cancel any existing hashtag stream
        hashtagStreamTask?.cancel()

        error = nil
        events = []
        hasSubmittedHashtagSearch = true

        startHashtagStream(tag)
    }

    /// Clear all results and reset state
    public func clear() {
        debounceTask?.cancel()
        searchTask?.cancel()
        hashtagStreamTask?.cancel()
        query = ""
        inputType = .empty
        clearResults()
        clearNavigationState()
    }

    /// Acknowledge navigation (reset navigation state after handling)
    ///
    /// Call this after you've handled a navigation signal to reset the state.
    public func acknowledgeNavigation() {
        clearNavigationState()
    }

    // MARK: - Private Methods

    private func clearResults() {
        events = []
        profilePubkeys = []
        hasSubmittedHashtagSearch = false
        isResolvingNIP05 = false
        error = nil
    }

    private func clearNavigationState() {
        navigateToProfile = nil
        navigateToProfileRelays = nil
        navigateToEvent = nil
        navigateToEventRelays = nil
        navigateToEventAuthor = nil
    }

    private func debounceAndSearch(_ searchQuery: String, profileOnly: Bool) {
        debounceTask?.cancel()

        debounceTask = Task {
            // Debounce
            try? await Task.sleep(nanoseconds: UInt64(debounceInterval * 1_000_000_000))

            guard !Task.isCancelled else { return }

            await performSearch(searchQuery, profileOnly: profileOnly)
        }
    }

    private func performSearch(_ searchQuery: String, profileOnly: Bool) async {
        error = nil

        do {
            guard let cache = ndk.cache as? NDKNostrDBCache else {
                throw UnifiedSearchError.cacheNotAvailable
            }

            // Search profiles
            let pubkeys = await cache.searchProfiles(searchQuery, limit: limit)

            guard !Task.isCancelled else { return }

            profilePubkeys = pubkeys

            // Search events (unless profile-only mode)
            if !profileOnly {
                let eventResults = await cache.textSearch(searchQuery, limit: limit)

                guard !Task.isCancelled else { return }

                events = eventResults
            } else {
                events = []
            }

        } catch {
            guard !Task.isCancelled else { return }
            self.error = error
            profilePubkeys = []
            events = []
        }
    }

    private func resolveNIP05(_ identifier: String) {
        isResolvingNIP05 = true
        error = nil

        searchTask = Task {
            do {
                // Use NIP05Manager to resolve
                let pubkey = try await ndk.nip05Manager.resolvePubkey(identifier: identifier)

                guard !Task.isCancelled else { return }

                if let pubkey = pubkey {
                    navigateToProfile = pubkey
                } else {
                    error = UnifiedSearchError.nip05NotFound(identifier)
                }

                isResolvingNIP05 = false

            } catch {
                guard !Task.isCancelled else { return }
                self.error = error
                isResolvingNIP05 = false
            }
        }
    }

    private func startHashtagStream(_ tag: String) {
        // Create filter for hashtag (uses "t" tag)
        let filter = NDKFilter(
            kinds: [1], // Notes
            limit: limit,
            tags: ["t": Set([tag.lowercased()])]
        )

        // Get search relays from user defaults or use defaults
        let searchRelays = getSearchRelays()

        // Subscribe - keep open for live updates
        let subscription = ndk.subscribe(
            filter: filter,
            cachePolicy: .networkOnly,
            relays: searchRelays
        )

        // Stream events continuously until cancelled
        hashtagStreamTask = Task { @MainActor [weak self] in
            guard let self else { return }

            for await batch in subscription.events {
                guard !Task.isCancelled else { break }

                self.events.append(contentsOf: batch)
                self.events.sort { $0.createdAt > $1.createdAt }
            }
        }
    }

    private func getSearchRelays() -> Set<String> {
        // Read from user's configured search relays (set in Settings > Relay Manager > Search Relays)
        let relays = UserDefaults.standard.stringArray(forKey: "chirp_search_relays") ?? [
            "wss://relay.nostr.band"
        ]
        return Set(relays)
    }
}

// MARK: - UnifiedSearchError

/// Errors specific to unified search operations
public enum UnifiedSearchError: Error, LocalizedError {
    case cacheNotAvailable
    case nip05NotFound(String)
    case hashtagSearchFailed(String)

    public var errorDescription: String? {
        switch self {
        case .cacheNotAvailable:
            return "Search requires a cache to be configured"
        case .nip05NotFound(let identifier):
            return "Could not resolve '\(identifier)'"
        case .hashtagSearchFailed(let tag):
            return "Failed to search for #\(tag)"
        }
    }
}
