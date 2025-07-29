import Foundation
import NDKSwift
import SwiftUI
import Combine

// MARK: - NDKContactsDataSource

/// Observable data source for contact lists and their associated profiles
///
/// This data source manages:
/// - User's contact list (kind:3 events)
/// - Profile metadata for all contacts
/// - Real-time updates as contacts change
/// - Efficient bulk profile loading
///
/// ## Usage
///
/// ```swift
/// @StateObject private var contactsDataSource = NDKContactsDataSource(
///     ndk: ndk,
///     userPubkey: currentUser.pubkey
/// )
///
/// var body: some View {
///     List(contactsDataSource.contacts, id: \.pubkey) { contact in
///         ContactRow(contact: contact)
///     }
/// }
/// ```
@MainActor
public final class NDKContactsDataSource: ObservableObject, @preconcurrency NDKDataSourceProtocol {

    // MARK: - Published Properties

    /// Array of contact public keys
    @Published public private(set) var contactPubkeys: Set<String> = []

    /// Profile metadata for contacts
    @Published public private(set) var contactProfiles: [String: NDKUserProfile] = [:]

    /// Whether the data source is currently loading
    @Published public private(set) var isLoading = false

    /// Any error that occurred during loading
    @Published public private(set) var error: Error?

    // MARK: - Private Properties

    private let ndk: NDK
    private let userPubkey: String
    private let contactListDataSource: NDKDataSource<NDKEvent>
    private var profilesDataSource: NDKDataSource<NDKEvent>?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    /// Initialize a contacts data source for a specific user
    /// - Parameters:
    ///   - ndk: The NDK instance to use for data fetching
    ///   - userPubkey: The public key of the user whose contacts to fetch
    ///   - maxAge: Maximum age of cached data in seconds (default: 1 hour)
    public init(ndk: NDK, userPubkey: String, maxAge: TimeInterval = TimeConstants.hour) {
        self.ndk = ndk
        self.userPubkey = userPubkey

        // Create data source for contact list events (kind:3)
        self.contactListDataSource = ndk.observe(
            filter: NDKFilter(
                authors: [userPubkey],
                kinds: [EventKind.contacts]
            ),
            maxAge: maxAge,
            cachePolicy: .cacheWithNetwork
        )

        // Start observing contact list
        observeContactList()
    }

    // MARK: - Private Methods

    private func observeContactList() {
        // Parse contact list from events
        contactListDataSource.$data
            .compactMap { events in
                // Get the most recent contact list event
                events.sorted { $0.createdAt > $1.createdAt }.first
            }
            .map { [weak self] event in
                self?.parseContactPubkeys(from: event) ?? Set<String>()
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pubkeys in
                self?.contactPubkeys = pubkeys
                self?.loadContactProfiles(for: pubkeys)
            }
            .store(in: &cancellables)

        // Map loading state
        contactListDataSource.$isLoading
            .receive(on: DispatchQueue.main)
            .assign(to: &$isLoading)

        // Map error state
        contactListDataSource.$error
            .receive(on: DispatchQueue.main)
            .assign(to: &$error)
    }

    private func parseContactPubkeys(from event: NDKEvent) -> Set<String> {
        var pubkeys = Set<String>()

        for tag in event.tags {
            // Look for 'p' tags containing public keys
            if tag.count >= 2 && tag[0] == "p" {
                pubkeys.insert(tag[1])
            }
        }

        return pubkeys
    }

    private func loadContactProfiles(for pubkeys: Set<String>) {
        guard !pubkeys.isEmpty else { return }

        // Create data source for contact profiles (kind:0)
        profilesDataSource = ndk.observe(
            filter: NDKFilter(
                authors: Array(pubkeys),
                kinds: [EventKind.metadata]
            ),
            maxAge: TimeConstants.hour, // Cache profiles for 1 hour
            cachePolicy: .cacheWithNetwork
        )

        // Parse profiles from events
        profilesDataSource?.$data
            .map { [weak self] events in
                self?.parseContactProfiles(from: events) ?? [:]
            }
            .receive(on: DispatchQueue.main)
            .assign(to: &$contactProfiles)
    }

    private func parseContactProfiles(from events: [NDKEvent]) -> [String: NDKUserProfile] {
        var profiles: [String: NDKUserProfile] = [:]

        // Group events by author and get the most recent profile for each
        let eventsByAuthor = Dictionary(grouping: events) { $0.pubkey }

        for (pubkey, authorEvents) in eventsByAuthor {
            if let latestEvent = authorEvents.sorted(by: { $0.createdAt > $1.createdAt }).first,
               let profile = JSONCoding.safeDecode(NDKUserProfile.self, from: latestEvent.content.data(using: .utf8) ?? Data()) {
                profiles[pubkey] = profile
            }
        }

        return profiles
    }

    // MARK: - Public Methods

    /// Get a profile for a specific contact
    public func profile(for pubkey: String) -> NDKUserProfile? {
        contactProfiles[pubkey]
    }

    /// Check if a user is in the contact list
    public func isFollowing(_ pubkey: String) -> Bool {
        contactPubkeys.contains(pubkey)
    }

    /// Get all contacts with their profiles
    public var contacts: [(pubkey: String, profile: NDKUserProfile?)] {
        contactPubkeys.map { pubkey in
            (pubkey: pubkey, profile: contactProfiles[pubkey])
        }
    }

    /// Get the number of contacts
    public var contactCount: Int {
        contactPubkeys.count
    }
}
