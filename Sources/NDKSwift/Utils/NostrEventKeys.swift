import Foundation

/// Constants for Nostr event JSON keys to avoid magic strings
public enum NostrEventKeys {
    
    // MARK: - Core Event Fields
    
    /// Event ID field
    public static let id = "id"
    
    /// Public key of the event author
    public static let pubkey = "pubkey"
    
    /// Unix timestamp when the event was created
    public static let createdAt = "created_at"
    
    /// Event kind number
    public static let kind = "kind"
    
    /// Array of tags
    public static let tags = "tags"
    
    /// Event content
    public static let content = "content"
    
    /// Event signature
    public static let sig = "sig"
    
    // MARK: - Relay Message Fields
    
    /// Subscription ID in relay messages
    public static let subscriptionId = "subscription_id"
    
    // MARK: - Filter Fields
    
    /// Array of event IDs to filter by
    public static let ids = "ids"
    
    /// Array of author public keys to filter by
    public static let authors = "authors"
    
    /// Array of event kinds to filter by
    public static let kinds = "kinds"
    
    /// Timestamp to filter events since
    public static let since = "since"
    
    /// Timestamp to filter events until
    public static let until = "until"
    
    /// Maximum number of events to return
    public static let limit = "limit"
    
    // MARK: - Tag Prefixes
    
    /// Event tag prefix
    public static let eventTag = "e"
    
    /// Pubkey tag prefix
    public static let pubkeyTag = "p"
    
    /// Reference tag prefix (deprecated)
    public static let referenceTag = "r"
    
    /// Hashtag prefix
    public static let hashtagTag = "t"
    
    /// Amount tag prefix
    public static let amountTag = "amount"
    
    /// Relay tag prefix
    public static let relayTag = "relay"
    
    /// Subject tag prefix
    public static let subjectTag = "subject"
    
    /// Description tag prefix
    public static let descriptionTag = "d"
    
    /// Alt tag prefix
    public static let altTag = "alt"
    
    /// Expiration tag prefix
    public static let expirationTag = "expiration"
    
    /// Image tag prefix
    public static let imageTag = "image"
    
    /// Summary tag prefix
    public static let summaryTag = "summary"
    
    /// Title tag prefix
    public static let titleTag = "title"
    
    /// URL tag prefix
    public static let urlTag = "url"
    
    /// Zap tag prefixes
    public static let zapTag = "zap"
    public static let boltTag = "bolt11"
    public static let preimageTag = "preimage"
    
    // MARK: - NIP-05 Fields
    
    /// Names field in NIP-05 response
    public static let names = "names"
    
    /// Relays field in NIP-05 response  
    public static let relays = "relays"
    
    // MARK: - Profile Metadata Fields
    
    /// Display name in profile metadata
    public static let name = "name"
    
    /// About/bio in profile metadata
    public static let about = "about"
    
    /// Picture URL in profile metadata
    public static let picture = "picture"
    
    /// Banner URL in profile metadata
    public static let banner = "banner"
    
    /// NIP-05 identifier in profile metadata
    public static let nip05 = "nip05"
    
    /// Lightning address in profile metadata
    public static let lud06 = "lud06"
    public static let lud16 = "lud16"
    
    /// Website URL in profile metadata
    public static let website = "website"
}