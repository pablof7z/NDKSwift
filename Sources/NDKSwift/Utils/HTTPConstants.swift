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
}