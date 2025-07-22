/// Constants for Nostr JSON field names used in event serialization
public enum NostrJSONConstants {
    
    // MARK: - Core Event Fields
    
    /// Standard Nostr event JSON field names
    public enum EventField {
        /// Event ID field
        public static let id = "id"
        
        /// Public key field
        public static let pubkey = "pubkey"
        
        /// Creation timestamp field
        public static let createdAt = "created_at"
        
        /// Event kind field
        public static let kind = "kind"
        
        /// Tags array field
        public static let tags = "tags"
        
        /// Content field
        public static let content = "content"
        
        /// Signature field
        public static let sig = "sig"
    }
    
    // MARK: - Filter Fields
    
    /// Filter JSON field names used in REQ messages
    public enum FilterField {
        /// Event IDs filter
        public static let ids = "ids"
        
        /// Authors filter (pubkeys)
        public static let authors = "authors"
        
        /// Kinds filter
        public static let kinds = "kinds"
        
        /// Since timestamp filter
        public static let since = "since"
        
        /// Until timestamp filter
        public static let until = "until"
        
        /// Limit filter
        public static let limit = "limit"
        
        /// Generic tag filter prefix (#)
        public static let tagPrefix = "#"
    }
    
    // MARK: - Relay Information Fields (NIP-11)
    
    /// Relay information document field names
    public enum RelayInfoField {
        /// Relay name
        public static let name = "name"
        
        /// Relay description
        public static let description = "description"
        
        /// Relay public key
        public static let pubkey = "pubkey"
        
        /// Relay contact
        public static let contact = "contact"
        
        /// Supported NIPs
        public static let supportedNips = "supported_nips"
        
        /// Relay software
        public static let software = "software"
        
        /// Relay version
        public static let version = "version"
        
        /// Relay limitations
        public static let limitation = "limitation"
        
        /// Relay retention policies
        public static let retention = "retention"
        
        /// Relay countries
        public static let relayCountries = "relay_countries"
        
        /// Language tags
        public static let languageTags = "language_tags"
        
        /// Relay tags
        public static let tags = "tags"
        
        /// Posting policy
        public static let postingPolicy = "posting_policy"
        
        /// Payments URL
        public static let paymentsUrl = "payments_url"
        
        /// Relay fees
        public static let fees = "fees"
        
        /// Relay icon
        public static let icon = "icon"
    }
    
    // MARK: - Message Types
    
    /// WebSocket message type identifiers
    public enum MessageType {
        /// Event message
        public static let event = "EVENT"
        
        /// Request message
        public static let req = "REQ"
        
        /// Close message
        public static let close = "CLOSE"
        
        /// Notice message
        public static let notice = "NOTICE"
        
        /// End of stored events message
        public static let eose = "EOSE"
        
        /// OK message (NIP-20)
        public static let ok = "OK"
        
        /// Count message (NIP-45)
        public static let count = "COUNT"
        
        /// Auth message (NIP-42)
        public static let auth = "AUTH"
    }
}