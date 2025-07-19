/// HTTP constants for consistent usage across the codebase
public enum HTTPConstants {
    // HTTP Methods
    public static let methodGet = "GET"
    public static let methodPost = "POST"
    public static let methodPut = "PUT"
    public static let methodDelete = "DELETE"
    
    // Common Headers
    public static let headerAccept = "Accept"
    public static let headerContentType = "Content-Type"
    public static let headerAuthorization = "Authorization"
    public static let headerSecWebSocketProtocol = "Sec-WebSocket-Protocol"
    
    // Content Types
    public static let contentTypeApplicationJSON = "application/json"
    public static let contentTypeTextPlain = "text/plain"
    public static let contentTypeNostrJSON = "application/nostr+json"
    
    // WebSocket Protocol
    public static let webSocketProtocolNostr = "nostr"
    
    // Common Timeout Values (in seconds)
    public static let timeoutRelayInfo: TimeInterval = 10
    public static let timeoutRequest: TimeInterval = 30
    public static let timeoutResource: TimeInterval = 300
}

/// Nostr protocol constants for consistent usage across the codebase  
public enum NostrConstants {
    public static let nostrPrefix = "nostr:"
    public static let nostrPrefixLength = 6
    
    // Bech32 prefixes
    public static let npubPrefix = "npub1"
    public static let notePrefix = "note1"
    public static let nprofilePrefix = "nprofile1"
    public static let neventPrefix = "nevent1"
    public static let naddrPrefix = "naddr1"
}