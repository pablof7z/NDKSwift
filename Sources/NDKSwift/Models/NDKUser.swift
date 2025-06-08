import Foundation

/// Represents a Nostr user
public final class NDKUser: Equatable, Hashable {
    /// User's public key
    public let pubkey: PublicKey

    /// Reference to NDK instance
    public weak var ndk: NDK?

    /// User's profile metadata
    public private(set) var profile: NDKUserProfile?

    /// Relay list (NIP-65)
    public private(set) var relayList: [NDKRelayInfo] = []

    /// User's NIP-05 identifier
    public var nip05: String? {
        return profile?.nip05
    }

    /// NIP-46 relay URLs (for remote signing)
    public var nip46Urls: [String]?

    /// Display name (from profile)
    public var displayName: String? {
        return profile?.displayName ?? profile?.name
    }

    /// Profile name
    public var name: String? {
        return profile?.name
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
    public static func fromNip05(_ nip05: String, ndk: NDK) async throws -> NDKUser {
        // Parse NIP-05 identifier (user@domain)
        let parts = nip05.split(separator: "@")
        guard parts.count == 2 else {
            throw NDKError.validation("invalid_nip05", "Invalid NIP-05 format")
        }

        let name = String(parts[0])
        let domain = String(parts[1])

        // Build the well-known URL
        let urlString = "https://\(domain)/.well-known/nostr.json?name=\(name)"
        guard let url = URL(string: urlString) else {
            throw NDKError.validation("invalid_nip05_url", "Invalid NIP-05 URL")
        }

        // Fetch the data
        let (data, _): (Data, URLResponse)
        do {
            (data, _) = try await URLSession.shared.data(from: url)
        } catch {
            throw NDKError.network("nip05_fetch_failed", "Failed to fetch NIP-05 data", 
                                   context: ["url": urlString, "domain": domain], 
                                   underlying: error)
        }

        // Parse JSON response
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let names = json["names"] as? [String: String],
              let pubkey = names[name]
        else {
            throw NDKError.validation("nip05_verification_failed", "NIP-05 verification failed",
                                      context: ["name": name, "domain": domain])
        }

        let user = NDKUser(pubkey: pubkey)
        user.ndk = ndk

        // Check for NIP-46 relays
        if let nip46 = json["nip46"] as? [String: Any],
           let relays = nip46[pubkey] as? [String]
        {
            user.nip46Urls = relays
        }

        return user
    }

    // MARK: - Profile Management

    /// Fetch user's profile
    /// - Parameter forceRefresh: If true, bypasses cache and fetches fresh data from relays
    /// - Returns: The user's profile, or nil if not found
    @discardableResult
    public func fetchProfile(forceRefresh: Bool = false) async throws -> NDKUserProfile? {
        guard let ndk = ndk else {
            throw NDKError.runtime("ndk_not_set", "NDK instance not set")
        }

        // Check cache first unless force refresh is requested
        if !forceRefresh {
            if let cached = await ndk.cacheAdapter?.fetchProfile(pubkey: pubkey) {
                self.profile = cached
                return cached
            }
        }

        // Create filter for kind 0 events
        let filter = NDKFilter(
            authors: [pubkey],
            kinds: [EventKind.metadata],
            limit: 1
        )

        // Fetch the profile event
        if let event = try await ndk.fetchEvent(filter) {
            // Parse the profile from the event content
            guard let profileData = event.content.data(using: .utf8),
                  let profile = try? JSONDecoder().decode(NDKUserProfile.self, from: profileData) else {
                throw NDKError.validation("invalid_profile_data", "Invalid profile data")
            }
            
            // Update our local profile
            self.profile = profile
            
            // Save to cache
            await ndk.cacheAdapter?.saveProfile(pubkey: pubkey, profile: profile)
            
            return profile
        }
        
        return nil
    }

    /// Update profile with new metadata
    public func updateProfile(_ profile: NDKUserProfile) {
        self.profile = profile
    }

    /// Fetch user's relay list (NIP-65)
    @discardableResult
    public func fetchRelayList() async throws -> [NDKRelayInfo] {
        guard let ndk = ndk else {
            throw NDKError.runtime("ndk_not_set", "NDK instance not set")
        }

        // Create filter for kind 10002 events
        let filter = NDKFilter(
            authors: [pubkey],
            kinds: [EventKind.relayList],
            limit: 1
        )

        // TODO: Implement subscription and fetch
        // For now, return empty array
        return []
    }

    // MARK: - Following/Followers

    /// Get users this user follows
    public func follows() async throws -> Set<NDKUser> {
        guard let ndk = ndk else {
            throw NDKError.runtime("ndk_not_set", "NDK instance not set")
        }

        // Create filter for kind 3 events
        let filter = NDKFilter(
            authors: [pubkey],
            kinds: [EventKind.contacts],
            limit: 1
        )

        // TODO: Implement subscription and fetch
        // Parse 'p' tags from contact list
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
        if pubkey.count > 16 {
            return String(pubkey.prefix(8)) + "..." + String(pubkey.suffix(8))
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

    // MARK: - Payments

    /// Pay this user using the configured wallet
    /// - Parameters:
    ///   - amount: Amount in satoshis
    ///   - comment: Optional comment for the payment
    ///   - tags: Optional additional tags
    /// - Returns: Payment confirmation
    public func pay(amount: Int64, comment: String? = nil, tags: [[String]]? = nil) async throws -> NDKPaymentConfirmation {
        guard let ndk = ndk else {
            throw NDKError.runtime("ndk_not_set", "NDK instance not set")
        }

        guard let paymentRouter = ndk.paymentRouter else {
            throw NDKError.configuration("wallet_not_configured", "Wallet not configured")
        }

        let request = NDKPaymentRequest(
            recipient: self,
            amount: amount,
            comment: comment,
            tags: tags
        )

        return try await paymentRouter.pay(request)
    }

    /// Get available payment methods for this user
    /// - Returns: Set of payment methods this user supports
    public func getPaymentMethods() async throws -> Set<NDKPaymentMethod> {
        guard let ndk = ndk else {
            throw NDKError.runtime("ndk_not_set", "NDK instance not set")
        }

        var methods = Set<NDKPaymentMethod>()

        // Check for Lightning support (NIP-57)
        if let profile = try? await fetchProfile() {
            if profile.lud06 != nil || profile.lud16 != nil {
                methods.insert(.lightning)
            }
        }

        // Check for Cashu mint list (NIP-61)
        let mintListFilter = NDKFilter(
            authors: [pubkey],
            kinds: [EventKind.cashuMintList]
        )

        if let mintListEvent = try? await ndk.fetchEvent(mintListFilter) {
            // Check if user has valid mints
            let mintTags = mintListEvent.tags.filter { $0.first == "mint" }
            if !mintTags.isEmpty {
                methods.insert(.nutzap)
            }
        }

        // TODO: Check for NWC support when implemented

        return methods
    }
}

/// User profile metadata (kind 0)
public struct NDKUserProfile: Codable {
    public var name: String?
    public var displayName: String?
    public var about: String?
    public var picture: String?
    public var banner: String?
    public var nip05: String?
    public var lud16: String?
    public var lud06: String?
    public var website: String?

    // Additional fields
    private var additionalFields: [String: String] = [:]

    public init(
        name: String? = nil,
        displayName: String? = nil,
        about: String? = nil,
        picture: String? = nil,
        banner: String? = nil,
        nip05: String? = nil,
        lud16: String? = nil,
        lud06: String? = nil,
        website: String? = nil
    ) {
        self.name = name
        self.displayName = displayName
        self.about = about
        self.picture = picture
        self.banner = banner
        self.nip05 = nip05
        self.lud16 = lud16
        self.lud06 = lud06
        self.website = website
    }

    // MARK: - Codable

    private struct DynamicCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue _: Int) {
            return nil
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)

        self.name = try container.decodeIfPresent(String.self, forKey: DynamicCodingKey(stringValue: "name")!)
        self.displayName = try container.decodeIfPresent(String.self, forKey: DynamicCodingKey(stringValue: "display_name")!)
        self.about = try container.decodeIfPresent(String.self, forKey: DynamicCodingKey(stringValue: "about")!)
        self.picture = try container.decodeIfPresent(String.self, forKey: DynamicCodingKey(stringValue: "picture")!)
        self.banner = try container.decodeIfPresent(String.self, forKey: DynamicCodingKey(stringValue: "banner")!)
        self.nip05 = try container.decodeIfPresent(String.self, forKey: DynamicCodingKey(stringValue: "nip05")!)
        self.lud16 = try container.decodeIfPresent(String.self, forKey: DynamicCodingKey(stringValue: "lud16")!)
        self.lud06 = try container.decodeIfPresent(String.self, forKey: DynamicCodingKey(stringValue: "lud06")!)
        self.website = try container.decodeIfPresent(String.self, forKey: DynamicCodingKey(stringValue: "website")!)

        // Store any additional fields
        let knownKeys = ["name", "display_name", "about", "picture", "banner", "nip05", "lud16", "lud06", "website"]
        for key in container.allKeys {
            if !knownKeys.contains(key.stringValue) {
                if let value = try container.decodeIfPresent(String.self, forKey: key) {
                    additionalFields[key.stringValue] = value
                }
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)

        try container.encodeIfPresent(name, forKey: DynamicCodingKey(stringValue: "name")!)
        try container.encodeIfPresent(displayName, forKey: DynamicCodingKey(stringValue: "display_name")!)
        try container.encodeIfPresent(about, forKey: DynamicCodingKey(stringValue: "about")!)
        try container.encodeIfPresent(picture, forKey: DynamicCodingKey(stringValue: "picture")!)
        try container.encodeIfPresent(banner, forKey: DynamicCodingKey(stringValue: "banner")!)
        try container.encodeIfPresent(nip05, forKey: DynamicCodingKey(stringValue: "nip05")!)
        try container.encodeIfPresent(lud16, forKey: DynamicCodingKey(stringValue: "lud16")!)
        try container.encodeIfPresent(lud06, forKey: DynamicCodingKey(stringValue: "lud06")!)
        try container.encodeIfPresent(website, forKey: DynamicCodingKey(stringValue: "website")!)

        // Encode additional fields
        for (key, value) in additionalFields {
            try container.encode(value, forKey: DynamicCodingKey(stringValue: key)!)
        }
    }

    /// Get additional field value
    public func additionalField(_ key: String) -> String? {
        return additionalFields[key]
    }

    /// Set additional field value
    public mutating func setAdditionalField(_ key: String, value: String?) {
        additionalFields[key] = value
    }
}
