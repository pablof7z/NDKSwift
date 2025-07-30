import Foundation

/// Wrapper for user metadata events (kind 0)
/// Provides convenient access to profile fields without re-parsing JSON
public class NDKUserMetadata {
    /// The public key of the user
    public let pubkey: String
    
    /// The event ID this metadata came from
    public let eventId: String
    
    /// When this metadata was last updated
    public let updatedAt: Timestamp
    
    /// Reference to NDK instance
    public weak var ndk: NDK?
    
    /// Cached parsed metadata dictionary
    private var parsedMetadata: [String: Any]?
    
    /// Initialize with an event (parses JSON)
    /// - Parameters:
    ///   - event: The kind 0 event containing user metadata
    ///   - ndk: Optional NDK instance reference
    public init(event: NDKEvent, ndk: NDK? = nil) {
        self.pubkey = event.pubkey
        self.eventId = event.id
        self.updatedAt = event.createdAt
        self.ndk = ndk
        
        // Parse the metadata immediately
        if let data = event.content.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            self.parsedMetadata = parsed
        }
    }
    
    /// Initialize with pre-parsed data (from cache)
    /// - Parameters:
    ///   - pubkey: The public key of the user
    ///   - parsedMetadata: Pre-parsed metadata dictionary
    ///   - updatedAt: When this metadata was last updated
    ///   - eventId: The event ID this metadata came from
    ///   - ndk: Optional NDK instance reference
    public init(pubkey: String, parsedMetadata: [String: Any], updatedAt: Timestamp, eventId: String, ndk: NDK? = nil) {
        self.pubkey = pubkey
        self.parsedMetadata = parsedMetadata
        self.updatedAt = updatedAt
        self.eventId = eventId
        self.ndk = ndk
    }
    
    // MARK: - Profile Fields
    
    /// User's display name
    public var name: String? {
        return parsedMetadata?["name"] as? String
    }
    
    /// User's username/handle
    public var displayName: String? {
        return parsedMetadata?["display_name"] as? String
    }
    
    /// User's bio/about text
    public var about: String? {
        return parsedMetadata?["about"] as? String
    }
    
    /// User's profile picture URL
    public var picture: String? {
        return parsedMetadata?["picture"] as? String
    }
    
    /// User's banner image URL
    public var banner: String? {
        return parsedMetadata?["banner"] as? String
    }
    
    /// User's website URL
    public var website: String? {
        return parsedMetadata?["website"] as? String
    }
    
    /// User's NIP-05 identifier
    public var nip05: String? {
        return parsedMetadata?["nip05"] as? String
    }
    
    /// User's Lightning address
    public var lud16: String? {
        return parsedMetadata?["lud16"] as? String
    }
    
    /// User's Lightning URL
    public var lud06: String? {
        return parsedMetadata?["lud06"] as? String
    }
    
    /// Get any custom field from metadata
    public func getField(_ key: String) -> Any? {
        return parsedMetadata?[key]
    }
    
    /// Get the raw metadata dictionary
    public var metadata: [String: Any]? {
        return parsedMetadata
    }
    
    /// Best available name for display (prioritizes displayName, then name, then truncated npub)
    public var bestDisplayName: String {
        if let displayName = displayName, !displayName.isEmpty {
            return displayName
        }
        if let name = name, !name.isEmpty {
            return name
        }
        // Fallback to npub
        return NDKUser(pubkey: pubkey).npub.prefix(16) + "..."
    }
}

// MARK: - Convenience Factory Methods

extension NDKUserMetadata {
    /// Create metadata from JSON string
    public static func from(json: String, pubkey: String, ndk: NDK? = nil) -> NDKUserMetadata? {
        let event = NDKEvent(
            kind: EventKind.metadata,
            content: json,
            tags: [],
            pubkey: pubkey,
            createdAt: Timestamp.now
        )
        return NDKUserMetadata(event: event, ndk: ndk)
    }
}