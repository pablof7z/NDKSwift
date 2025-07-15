import Foundation

/// Actor for thread-safe user state management
actor UserStateActor {
    var profile: NDKUserProfile?
    var relayList: [NDKRelayInfo] = []
    var nip46Urls: [String]?
    
    func getProfile() -> NDKUserProfile? { profile }
    func setProfile(_ newProfile: NDKUserProfile?) { profile = newProfile }
    
    func getRelayList() -> [NDKRelayInfo] { relayList }
    func setRelayList(_ newList: [NDKRelayInfo]) { relayList = newList }
    
    func getNip46Urls() -> [String]? { nip46Urls }
    func setNip46Urls(_ urls: [String]?) { nip46Urls = urls }
}

/// Represents a Nostr user
public final class NDKUser: Equatable, Hashable, Sendable {
    /// User's public key
    public let pubkey: PublicKey

    /// Reference to NDK instance
    public nonisolated(unsafe) weak var ndk: NDK?
    
    /// Internal state actor that manages all mutable state
    private let stateActor = UserStateActor()

    /// User's profile metadata
    public var profile: NDKUserProfile? {
        get async { await stateActor.getProfile() }
    }

    /// Relay list (NIP-65)
    public var relayList: [NDKRelayInfo] {
        get async { await stateActor.getRelayList() }
    }

    /// User's NIP-05 identifier
    public var nip05: String? {
        get async { await stateActor.getProfile()?.nip05 }
    }

    /// NIP-46 relay URLs (for remote signing)
    public var nip46Urls: [String]? {
        get async { await stateActor.getNip46Urls() }
    }

    /// Display name (from profile)
    public var displayName: String? {
        get async {
            let userProfile = await stateActor.getProfile()
            return userProfile?.displayName ?? userProfile?.name
        }
    }

    /// Profile name
    public var name: String? {
        get async { await stateActor.getProfile()?.name }
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
            throw NDKError.invalidInput(message: "Invalid NIP-05 format")
        }

        let name = String(parts[0])
        let domain = String(parts[1])

        // Build the well-known URL
        let urlString = "https://\(domain)/.well-known/nostr.json?name=\(name)"
        guard let url = URL(string: urlString) else {
            throw NDKError.invalidURL("Invalid NIP-05 URL: \(urlString)")
        }

        // Fetch the data
        let (data, _): (Data, URLResponse)
        do {
            (data, _) = try await URLSession.shared.data(from: url)
        } catch {
            throw NDKError.connectionFailed(relay: domain, message: "Failed to fetch NIP-05 data from \(urlString)", underlying: error)
        }

        // Parse JSON response
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let names = json["names"] as? [String: String],
              let pubkey = names[name]
        else {
            throw NDKError.invalidInput(message: "NIP-05 verification failed for \(name)@\(domain)")
        }

        let user = NDKUser(pubkey: pubkey)
        user.ndk = ndk

        // Check for NIP-46 relays
        if let nip46 = json["nip46"] as? [String: Any],
           let relays = nip46[pubkey] as? [String] {
            await user.stateActor.setNip46Urls(relays)
        }

        return user
    }

    // MARK: - Profile Management
    
    /// Update the user's profile
    internal func updateProfile(_ profile: NDKUserProfile) async {
        await stateActor.setProfile(profile)
    }
    
    /// Process a metadata event to update the user's profile
    /// Used internally when fetching profiles from events
    public func processMetadataEvent(_ event: NDKEvent) {
        Task {
            let eventContent = event.content
            if let profileData = eventContent.data(using: .utf8),
               let profile = try? JSONDecoder().decode(NDKUserProfile.self, from: profileData) {
                await updateProfile(profile)
                
                // Save to cache if available
                if let ndk = ndk {
                    try? await ndk.cache.saveProfile(profile, pubkey: pubkey)
                }
            }
        }
    }

    /// Fetch user's relay list (NIP-65)
    @discardableResult
    public func fetchRelayList() async throws -> [NDKRelayInfo] {
        guard let ndk = ndk else {
            throw NDKError.notConfigured("NDK instance not set")
        }

        // Create filter for kind 10002 events
        let filter = NDKFilter(
            authors: [pubkey],
            kinds: [EventKind.relayList],
            limit: 1
        )

        // Fetch the relay list event
        if let event = try await ndk.fetchEvent(filter) {
            // Parse relay tags
            let eventTags = event.tags
            let relays = eventTags
                .filter { $0.first == "r" }
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
        guard let ndk = ndk else {
            throw NDKError.notConfigured("NDK instance not set")
        }

        // Create filter for kind 3 events
        let filter = NDKFilter(
            authors: [pubkey],
            kinds: [EventKind.contacts],
            limit: 1
        )

        // Fetch the contact list event
        if let event = try await ndk.fetchEvent(filter) {
            // Parse 'p' tags from contact list
            let eventTags = event.tags
            let followedPubkeys = eventTags
                .filter { $0.first == "p" }
                .compactMap { $0[safe: 1] }
            
            // Create NDKUser instances for each followed pubkey
            let users = followedPubkeys.map { pubkey in
                let user = NDKUser(pubkey: pubkey)
                user.ndk = ndk
                return user
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
    public func pay(amount: Int64, comment: String? = nil, tags: [[String]]? = nil) async throws -> PaymentConfirmation {
        guard ndk != nil else {
            throw NDKError.notConfigured("NDK instance not set")
        }

        // Payment routing will be implemented when wallet integration is complete
        throw NDKError.notConfigured("Payment routing not yet implemented")
    }

    /// Get available payment methods for this user
    /// - Returns: Set of payment methods this user supports
    public func getPaymentMethods() async throws -> Set<NDKPaymentMethod> {
        guard let ndk = ndk else {
            throw NDKError.notConfigured("NDK instance not set")
        }

        var methods = Set<NDKPaymentMethod>()

        // IMPORTANT: Always batch multiple kinds in a single filter!
        // NEVER make sequential requests for different event kinds - that's network inefficient
        // NDKFilter accepts arrays specifically to enable batching
        let filter = NDKFilter(
            authors: [pubkey],
            kinds: [EventKind.metadata, EventKind.nutzapPreferences]  // Fetch BOTH in one request
        )
        
        let events = try await ndk.fetchEvents([filter])
        
        for event in events {
            switch event.kind {
            case EventKind.metadata:
                // Check for Lightning support (lud06/lud16)
                if let profileData = try? JSONDecoder().decode(NDKUserProfile.self, from: event.content.data(using: String.Encoding.utf8) ?? Data()) {
                    if profileData.lud06 != nil || profileData.lud16 != nil {
                        methods.insert(.lightning)
                    }
                }
            case EventKind.nutzapPreferences:
                // User has nutzap preference announcement
                methods.insert(.nutzap)
            default:
                break
            }
        }

        return methods
    }
}

/// User profile metadata (kind 0)
public struct NDKUserProfile: Codable, Sendable {
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
