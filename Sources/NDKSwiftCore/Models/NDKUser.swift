import Foundation

/// Represents a Nostr user
public final class NDKUser: Equatable, Hashable {
    /// User's public key
    public let pubkey: PublicKey

    /// Reference to NDK instance (required)
    public let ndk: NDK

    /// Relay list (NIP-65)
    public private(set) var relayList: [NDKRelayInfo] = []

    /// NIP-46 relay URLs (for remote signing)
    public internal(set) var nip46Urls: [String]?

    // MARK: - Initialization

    public init(pubkey: PublicKey, ndk: NDK) {
        self.pubkey = pubkey
        self.ndk = ndk
    }

    /// Create user from npub
    public convenience init?(npub: String, ndk: NDK) {
        do {
            let pubkey = try Bech32.pubkey(from: npub)
            self.init(pubkey: pubkey, ndk: ndk)
        } catch {
            return nil
        }
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

    // MARK: - Profile

    /// Observable profile that streams kind 0 metadata updates
    /// Convenience property that delegates to ndk.profile(for:)
    @MainActor
    public var profile: NDKProfile {
        ndk.profile(for: pubkey)
    }

    // MARK: - Relay List

    /// Fetch user's relay list (NIP-65)
    @discardableResult
    public func fetchRelayList() async throws -> [NDKRelayInfo] {
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

            let users = followedPubkeys.compactMap { ndk.getUser($0) }
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
    /// - Throws: Bech32Error if pubkey cannot be encoded
    public var npub: String {
        get throws {
            try Bech32.npub(from: pubkey)
        }
    }

    /// Get shortened public key for display
    public var shortPubkey: String {
        if pubkey.count > ProtocolConstants.maxPubkeyDisplayLength {
            return StringFormatHelpers.truncateHex(pubkey, prefixLength: StringConstants.DisplayFormatting.hexPrefixLength, suffixLength: StringConstants.DisplayFormatting.hexPrefixLength)
        }
        return pubkey
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
        return try await ndk.verifyNIP05(for: self, maxAge: maxAge)
    }
}
