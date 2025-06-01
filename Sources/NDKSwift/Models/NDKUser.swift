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
        // TODO: Implement npub decoding
        return nil
    }
    
    /// Create user from NIP-05 identifier
    public static func fromNip05(_ nip05: String, ndk: NDK) async throws -> NDKUser? {
        // TODO: Implement NIP-05 lookup
        return nil
    }
    
    // MARK: - Profile Management
    
    /// Fetch user's profile
    @discardableResult
    public func fetchProfile() async throws -> NDKUserProfile? {
        guard let ndk = ndk else {
            throw NDKError.custom("NDK instance not set")
        }
        
        // Create filter for kind 0 events
        let filter = NDKFilter(
            authors: [pubkey],
            kinds: [EventKind.metadata],
            limit: 1
        )
        
        // TODO: Implement subscription and fetch
        // For now, return nil
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
            throw NDKError.custom("NDK instance not set")
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
            throw NDKError.custom("NDK instance not set")
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
        // TODO: Implement bech32 encoding
        return "npub1..."
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
        
        init?(intValue: Int) {
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