import Foundation

/// Represents a Nostr user with reactive profile updates
@Observable
public final class NDKUser: Equatable, Hashable {
    /// User's public key
    public let pubkey: PublicKey

    /// User's profile metadata - automatically updates when new kind 0 events arrive
    public private(set) var profile: NDKUserMetadata?

    /// Relay list (NIP-65)
    public private(set) var relayList: [NDKRelayInfo] = []

    /// NIP-46 relay URLs (for remote signing)
    public private(set) var nip46Urls: [String]?

    /// Reference to NDK instance
    public weak var ndk: NDK? {
        didSet {
            if ndk != nil {
                startProfileObservation()
            }
        }
    }

    /// Active profile subscription task
    private var profileTask: Task<Void, Never>?

    // MARK: - Initialization

    public init(pubkey: PublicKey) {
        self.pubkey = pubkey
    }

    /// Create user from npub
    public convenience init?(npub: String) {
        do {
            let pubkey = try Bech32.pubkey(from: npub)
            self.init(pubkey: pubkey)
        } catch {
            return nil
        }
    }

    deinit {
        profileTask?.cancel()
    }

    /// Create user from NIP-05 identifier
    public static func fromNip05(_ nip05: String, ndk: NDK, forceVerify: Bool = false) async throws -> NDKUser {
        guard let user = try await ndk.nip05Manager.resolveUser(
            identifier: nip05,
            forceVerify: forceVerify
        ) else {
            throw NDKError.invalidInput(message: "NIP-05 verification failed for \(nip05)")
        }

        // Restore NIP-46 URLs if available
        if let cached = await ndk.cache.getNIP05Entry(nip05.lowercased()),
           let nip46Relays = cached.nip46Relays
        {
            user.nip46Urls = nip46Relays
        }

        return user
    }

    // MARK: - Profile Observation

    private func startProfileObservation() {
        profileTask?.cancel()
        guard let ndk else { return }

        profileTask = Task { [weak self] in
            guard let self else { return }

            let filter = NDKFilter(
                authors: [self.pubkey],
                kinds: [EventKind.metadata]
            )

            let subscription = ndk.subscribe(
                filter: filter,
                cachePolicy: .cacheWithNetwork
            )

            for await event in subscription.events {
                guard !Task.isCancelled else { break }
                let metadata = NDKUserMetadata(event: event, ndk: ndk)

                // Only update if this is newer than current profile
                if self.profile == nil || metadata.updatedAt > self.profile!.updatedAt {
                    self.profile = metadata
                }
            }
        }
    }

    // MARK: - Relay List

    /// Fetch user's relay list (NIP-65)
    @discardableResult
    public func fetchRelayList() async throws -> [NDKRelayInfo] {
        guard let ndk else {
            throw NDKError.configurationError(ErrorMessageConstants.Messages.ndkInstanceNotSet)
        }

        let filter = NDKFilter(
            authors: [pubkey],
            kinds: [EventKind.relayList]
        )

        let dataSource = NDKSubscription(
            ndk: ndk,
            filter: filter,
            maxAge: TimeConstants.day
        )

        let events = await dataSource.collect(timeout: NetworkConstants.timeoutDataCollectionMedium)
        if let event = events.mostRecent {
            let eventTags = event.tags
            let relays = eventTags
                .extractTags(named: NostrConstants.TagName.reference)
                .compactMap { tag -> NDKRelayInfo? in
                    guard let url = tag[safe: 1] else { return nil }

                    let marker = tag[safe: 2]?.lowercased()
                    let read = marker == nil || marker == "read"
                    let write = marker == nil || marker == "write"

                    return NDKRelayInfo(url: url, read: read, write: write)
                }

            self.relayList = relays
            return relays
        }

        return []
    }

    // MARK: - Following/Followers

    /// Get users this user follows
    public func follows() async throws -> Set<NDKUser> {
        guard let ndk else {
            throw NDKError.configurationError(ErrorMessageConstants.Messages.ndkInstanceNotSet)
        }

        let filter = NDKFilter(
            authors: [pubkey],
            kinds: [EventKind.contacts]
        )

        let dataSource = NDKSubscription(
            ndk: ndk,
            filter: filter,
            maxAge: 10 * TimeConstants.minute
        )

        let events = await dataSource.collect(timeout: NetworkConstants.timeoutDataCollectionMedium)
        if let event = events.mostRecent {
            let eventTags = event.tags
            let followedPubkeys = eventTags
                .extractTags(named: NostrConstants.TagName.pubkey)
                .compactMap { $0[safe: 1] }

            var users: [NDKUser] = []
            for pubkey in followedPubkeys {
                let user = NDKUser(pubkey: pubkey)
                user.ndk = ndk
                users.append(user)
            }

            return Set(users)
        }

        return []
    }

    /// Check if this user follows another user
    public func follows(_ user: NDKUser) async throws -> Bool {
        let followList = try await follows()
        return followList.contains(user)
    }

    // MARK: - Utilities

    /// Get npub representation
    public var npub: String {
        do {
            return try Bech32.npub(from: pubkey)
        } catch {
            return "npub1..."
        }
    }

    /// Get shortened public key for display
    public var shortPubkey: String {
        if pubkey.count > ProtocolConstants.maxPubkeyDisplayLength {
            return StringFormatHelpers.truncateHex(pubkey, prefixLength: StringConstants.DisplayFormatting.hexPrefixLength, suffixLength: StringConstants.DisplayFormatting.hexPrefixLength)
        }
        return pubkey
    }

    /// Best available display name (from profile or fallback to npub)
    public var displayName: String {
        profile?.bestDisplayName ?? String(npub.prefix(16)) + "..."
    }

    /// Profile picture URL
    public var pictureURL: URL? {
        profile?.picture.flatMap(URL.init(string:))
    }

    // MARK: - Equatable & Hashable

    public static func == (lhs: NDKUser, rhs: NDKUser) -> Bool {
        return lhs.pubkey == rhs.pubkey
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(pubkey)
    }

    // MARK: - NIP-05 Verification

    /// Verify this user's NIP-05 identifier
    public func verifyNIP05(maxAge: TimeInterval = TimeConstants.day) async throws -> Bool {
        guard let ndk else {
            throw NDKError.configurationError(ErrorMessageConstants.Messages.ndkInstanceNotSet)
        }

        return try await ndk.verifyNIP05(for: self, maxAge: maxAge)
    }

    // MARK: - Payments

    /// Pay this user using the configured wallet
    public func pay(amount _: Int64, comment _: String? = nil, tags _: [[String]]? = nil) async throws -> PaymentConfirmation {
        guard ndk != nil else {
            throw NDKError.configurationError(ErrorMessageConstants.Messages.ndkInstanceNotSet)
        }

        throw NDKError.failedTo("route payment", message: "Not yet implemented")
    }
}
