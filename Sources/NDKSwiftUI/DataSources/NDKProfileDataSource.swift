import Foundation
import NDKSwift
import SwiftUI
import Combine

// MARK: - NDKProfileDataSource

/// Observable data source for user profile metadata (kind:0 events)
///
/// This data source provides reactive access to user profiles with:
/// - Real-time updates as profile changes are published
/// - Automatic caching and network fallback
/// - Progressive loading (shows fallback immediately, updates as data arrives)
/// - Memory efficient subscription sharing
///
/// ## Usage
///
/// ```swift
/// @StateObject private var profileDataSource = NDKProfileDataSource(
///     ndk: ndk,
///     pubkey: "npub1..."
/// )
///
/// var body: some View {
///     VStack {
///         if let profile = profileDataSource.profile {
///             Text(profile.displayName ?? "Unknown")
///         } else {
///             Text("Loading...")
///         }
///     }
/// }
/// ```
@MainActor
public final class NDKProfileDataSource: ObservableObject {

    // MARK: - Published Properties

    /// The user profile, if available
    @Published public private(set) var profile: NDKUserProfile?

    /// Whether the data source is currently loading
    @Published public private(set) var isLoading = false

    /// Any error that occurred during loading
    @Published public private(set) var error: Error?

    // MARK: - Private Properties

    private let ndk: NDK
    private let pubkey: String
    private let dataSource: NDKDataSource<NDKEvent>
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    /// Initialize a profile data source for a specific user
    /// - Parameters:
    ///   - ndk: The NDK instance to use for data fetching
    ///   - pubkey: The public key of the user to fetch profile for
    ///   - maxAge: Maximum age of cached data in seconds (default: 1 hour)
    public init(ndk: NDK, pubkey: String, maxAge: TimeInterval = TimeConstants.hour) {
        self.ndk = ndk
        self.pubkey = pubkey

        // Create data source for profile events (kind:0)
        self.dataSource = ndk.observe(
            filter: NDKFilter(
                authors: [pubkey],
                kinds: [EventKind.metadata]
            ),
            maxAge: maxAge,
            cachePolicy: .cacheWithNetwork
        )

        // Start observing data
        observeProfileData()
    }

    // MARK: - Private Methods

    private func observeProfileData() {
        // Map events to profile
        dataSource.$data
            .compactMap { events in
                // Get the most recent profile event
                events
                    .sorted { $0.createdAt > $1.createdAt }
                    .first
            }
            .compactMap { event in
                // Parse the profile JSON content
                JSONCoding.safeDecode(NDKUserProfile.self, from: event.content.data(using: .utf8) ?? Data())
            }
            .receive(on: DispatchQueue.main)
            .assign(to: &$profile)

        // Map loading state
        dataSource.$isLoading
            .receive(on: DispatchQueue.main)
            .assign(to: &$isLoading)

        // Map error state
        dataSource.$error
            .receive(on: DispatchQueue.main)
            .assign(to: &$error)
    }

    // MARK: - Public Methods

    /// Get a display name for the user, with fallback logic
    public var displayName: String {
        if let displayName = profile?.displayName, !displayName.isEmpty {
            return displayName
        }
        if let name = profile?.name, !name.isEmpty {
            return name
        }
        // Fallback to shortened npub
        let npub = NDKUser(pubkey: pubkey).npub
        return String(npub.prefix(16)) + "..."
    }

    /// Get a profile picture URL, if available
    public var pictureURL: URL? {
        guard let picture = profile?.picture, !picture.isEmpty else { return nil }
        return URL(string: picture)
    }

    /// Get the NIP-05 identifier, if available and valid
    public var nip05: String? {
        profile?.nip05
    }

    /// Get the profile description/about text
    public var about: String? {
        profile?.about
    }
}