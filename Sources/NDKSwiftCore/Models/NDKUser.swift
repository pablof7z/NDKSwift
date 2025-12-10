import Foundation

/// Actor for thread-safe user state management
actor UserStateActor {
    weak var ndk: NDK?
    var relayList: [NDKRelayInfo] = []
    var nip46Urls: [String]?

    func getNdk() -> NDK? { ndk }
    func setNdk(_ newNdk: NDK?) { ndk = newNdk }

    func getRelayList() -> [NDKRelayInfo] { relayList }
    func setRelayList(_ newList: [NDKRelayInfo]) { relayList = newList }

    func getNip46Urls() -> [String]? { nip46Urls }
    func setNip46Urls(_ urls: [String]?) { nip46Urls = urls }
}

/// Represents a Nostr user
public final class NDKUser: Equatable, Hashable, Sendable {
    /// User's public key
    public let pubkey: PublicKey

    /// Internal state actor that manages all mutable state
    private let stateActor = UserStateActor()

    /// Reference to NDK instance (thread-safe via actor)
    public var ndk: NDK? {
        get async { await stateActor.getNdk() }
    }

    /// Set the NDK instance (thread-safe via actor)
    public func setNdk(_ ndk: NDK?) async {
        await stateActor.setNdk(ndk)
    }


    /// Relay list (NIP-65)
    public var relayList: [NDKRelayInfo] {
        get async { await stateActor.getRelayList() }
    }


    /// NIP-46 relay URLs (for remote signing)
    public var nip46Urls: [String]? {
        get async { await stateActor.getNip46Urls() }
    }


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
           let nip46Relays = cached.nip46Relays {
            await user.stateActor.setNip46Urls(nip46Relays)
        }

        return user
    }

    // MARK: - Profile Management



    /// Fetch user's relay list (NIP-65)
    @discardableResult
    public func fetchRelayList() async throws -> [NDKRelayInfo] {
        let ndk = try GuardHelpers.unwrap(
            await self.ndk,
            error: NDKError.configurationError(ErrorMessageConstants.Messages.ndkInstanceNotSet)
        )

        // Create filter for kind 10002 events
        let filter = NDKFilter(
            authors: [pubkey],
            kinds: [EventKind.relayList]
        )

        // Fetch the relay list event
        let dataSource = NDKSubscription(
            ndk: ndk,
            filter: filter,
            maxAge: TimeConstants.day // 24 hours - relay lists rarely change
        )

        // Collect all relay list events and use the most recent
        let events = await dataSource.collect(timeout: NetworkConstants.timeoutDataCollectionMedium)
        if let event = events.mostRecent {
            // Parse relay tags
            let eventTags = event.tags
            let relays = eventTags
                .extractTags(named: NostrConstants.TagName.reference)
                .compactMap { tag -> NDKRelayInfo? in
                    guard let url = tag[safe: 1] else { return nil }

                    // Check for read/write markers
                    let marker = tag[safe: 2]?.lowercased()
                    let read = marker == nil || marker == "read"
                    let write = marker == nil || marker == "write"

                    return NDKRelayInfo(url: url, read: read, write: write)
                }

            await stateActor.setRelayList(relays)
            return relays
        }

        return []
    }

    // MARK: - Following/Followers

    /// Get users this user follows
    public func follows() async throws -> Set<NDKUser> {
        let ndk = try GuardHelpers.unwrap(
            await self.ndk,
            error: NDKError.configurationError(ErrorMessageConstants.Messages.ndkInstanceNotSet)
        )

        // Create filter for kind 3 events
        let filter = NDKFilter(
            authors: [pubkey],
            kinds: [EventKind.contacts]
        )

        // Fetch the contact list event
        let dataSource = NDKSubscription(
            ndk: ndk,
            filter: filter,
            maxAge: 10 * TimeConstants.minute // 10 minutes - contact lists don't change frequently
        )

        // Collect all contact list events and use the most recent
        let events = await dataSource.collect(timeout: NetworkConstants.timeoutDataCollectionMedium)
        if let event = events.mostRecent {
            // Parse 'p' tags from contact list
            let eventTags = event.tags
            let followedPubkeys = eventTags
                .extractTags(named: NostrConstants.TagName.pubkey)
                .compactMap { $0[safe: 1] }

            // Create NDKUser instances for each followed pubkey
            var users: [NDKUser] = []
            for pubkey in followedPubkeys {
                let user = NDKUser(pubkey: pubkey)
                await user.setNdk(ndk)
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
            // Fallback to placeholder if encoding fails
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

    // MARK: - Equatable & Hashable

    public static func == (lhs: NDKUser, rhs: NDKUser) -> Bool {
        return lhs.pubkey == rhs.pubkey
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(pubkey)
    }

    // MARK: - NIP-05 Verification

    /// Verify this user's NIP-05 identifier
    /// - Parameter maxAge: Maximum age before re-verification is needed (default: 24 hours)
    /// - Returns: True if the NIP-05 is verified and belongs to this user
    public func verifyNIP05(maxAge: TimeInterval = TimeConstants.day) async throws -> Bool {
        let ndk = try GuardHelpers.unwrap(
            await self.ndk,
            error: NDKError.configurationError(ErrorMessageConstants.Messages.ndkInstanceNotSet)
        )

        return try await ndk.verifyNIP05(for: self, maxAge: maxAge)
    }

    // MARK: - Payments

    /// Pay this user using the configured wallet
    /// - Parameters:
    ///   - amount: Amount in satoshis
    ///   - comment: Optional comment for the payment
    ///   - tags: Optional additional tags
    /// - Returns: Payment confirmation
    public func pay(amount: Int64, comment: String? = nil, tags: [[String]]? = nil) async throws -> PaymentConfirmation {
        guard await ndk != nil else {
            throw NDKError.configurationError(ErrorMessageConstants.Messages.ndkInstanceNotSet)
        }

        // Payment routing will be implemented when wallet integration is complete
        throw NDKError.failedTo("route payment", message: "Not yet implemented")
    }

}

