import Foundation
import NDKSwiftCore
import Observation

/// Observable state for managing repost interactions on an event
///
/// Tracks repost count, whether the current user has reposted, and provides
/// methods to toggle repost state or create quote reposts.
///
/// ## Usage
///
/// ```swift
/// struct PostRow: View {
///     @State private var repostState: RepostState
///
///     init(ndk: NDK, event: NDKEvent) {
///         _repostState = State(initialValue: RepostState(ndk: ndk, event: event))
///     }
///
///     var body: some View {
///         Button {
///             Task { try? await repostState.toggle() }
///         } label: {
///             HStack {
///                 Image(systemName: "arrow.2.squarepath")
///                 if repostState.count > 0 {
///                     Text("\(repostState.count)")
///                 }
///             }
///             .foregroundStyle(repostState.hasReposted ? .green : .secondary)
///         }
///         .task { await repostState.start() }
///     }
/// }
/// ```
@available(iOS 17.0, macOS 14.0, *)
@Observable
@MainActor
public final class RepostState {
    // MARK: - Public Properties

    /// Number of unique users who have reposted or quoted this event
    public private(set) var count: Int = 0

    /// Whether the current user has reposted this event
    public private(set) var hasReposted: Bool = false

    /// Pubkeys of users who have reposted (for showing avatars, etc.)
    public private(set) var pubkeys: [String] = []

    // MARK: - Private Properties

    private let ndk: NDK
    private let event: NDKEvent
    private var userRepostEvent: NDKEvent?
    @ObservationIgnored nonisolated(unsafe) private var observationTask: Task<Void, Never>?

    // MARK: - Initialization

    /// Create a new RepostState for tracking reposts on an event
    /// - Parameters:
    ///   - ndk: The NDK instance
    ///   - event: The event to track reposts for
    public init(ndk: NDK, event: NDKEvent) {
        self.ndk = ndk
        self.event = event
    }

    deinit {
        observationTask?.cancel()
    }

    // MARK: - Public Methods

    /// Start observing repost events for this event
    public func start() async {
        observationTask?.cancel()
        observationTask = Task { [weak self] in
            await self?.observeReposts()
        }
    }

    /// Stop observing reposts
    public func stop() {
        observationTask?.cancel()
        observationTask = nil
    }

    /// Toggle repost state - creates a repost if not reposted, deletes if already reposted
    public func toggle() async throws {
        guard ndk.signer != nil else {
            throw RepostError.noSigner
        }

        if hasReposted, let userRepostEvent {
            // Delete existing repost
            try await userRepostEvent.delete(signer: ndk.signer!, ndk: ndk)
            self.userRepostEvent = nil
            hasReposted = false
            // Count will update when subscription receives the deletion
        } else {
            // Create new repost
            let repostEvent = try await ndk.repost(event)
            userRepostEvent = repostEvent
            hasReposted = true
            // Count will update when subscription receives the new event
        }
    }

    /// Create a quote repost with the given content
    /// - Parameter content: The quote content
    /// - Returns: The created quote event
    @discardableResult
    public func quote(content: String) async throws -> NDKEvent {
        guard ndk.signer != nil else {
            throw RepostError.noSigner
        }

        let quoteEvent = try await ndk.quoteRepost(event, comment: content)
        // If user hadn't reposted before, this counts as their repost now
        if !hasReposted {
            userRepostEvent = quoteEvent
            hasReposted = true
        }
        return quoteEvent
    }

    // MARK: - Private Methods

    private func observeReposts() async {
        // Subscribe to:
        // - Kind 6 (repost) and Kind 16 (generic repost) with e-tag pointing to our event
        // - Kind 1 (text note) with q-tag pointing to our event (quote reposts)
        let repostFilter = NDKFilter(
            kinds: [EventKind.repost, EventKind.genericRepost],
            tags: ["e": Set([event.id])]
        )

        let quoteFilter = NDKFilter(
            kinds: [EventKind.textNote],
            tags: ["q": Set([event.id])]
        )

        // Create subscriptions for both filters
        let repostSubscription = ndk.subscribe(
            filter: repostFilter,
            maxAge: 0,
            cachePolicy: .cacheWithNetwork,
            closeOnEose: false
        )

        let quoteSubscription = ndk.subscribe(
            filter: quoteFilter,
            maxAge: 0,
            cachePolicy: .cacheWithNetwork,
            closeOnEose: false
        )

        // Track all repost events by ID to handle updates
        var allReposts: [String: NDKEvent] = [:]

        // Process both subscriptions concurrently
        await withTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in
                for await batch in repostSubscription.events {
                    guard let self else { return }
                    for event in batch {
                        allReposts[event.id] = event
                    }
                    await self.updateState(from: Array(allReposts.values))
                }
            }

            group.addTask { [weak self] in
                for await batch in quoteSubscription.events {
                    guard let self else { return }
                    for event in batch {
                        allReposts[event.id] = event
                    }
                    await self.updateState(from: Array(allReposts.values))
                }
            }
        }
    }

    private func updateState(from events: [NDKEvent]) async {
        let userPubkey = try? await ndk.signer?.pubkey

        // Count unique pubkeys
        var uniquePubkeys = Set<String>()
        var foundUserRepost: NDKEvent?

        for event in events {
            uniquePubkeys.insert(event.pubkey)

            if let userPubkey, event.pubkey == userPubkey {
                foundUserRepost = event
            }
        }

        count = uniquePubkeys.count
        pubkeys = Array(uniquePubkeys)
        hasReposted = foundUserRepost != nil
        userRepostEvent = foundUserRepost
    }
}

// MARK: - Errors

@available(iOS 17.0, macOS 14.0, *)
public enum RepostError: Error, LocalizedError {
    case noSigner

    public var errorDescription: String? {
        switch self {
        case .noSigner:
            return "No signer available. User must be logged in to repost."
        }
    }
}
