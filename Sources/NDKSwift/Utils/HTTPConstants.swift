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
    
    // Content Types
    public static let contentTypeApplicationJSON = "application/json"
    public static let contentTypeTextPlain = "text/plain"
}

/// Nostr protocol constants for consistent usage across the codebase  
public enum NostrConstants {
    public static let nostrPrefix = "nostr:"
    public static let nostrPrefixLength = 6
}