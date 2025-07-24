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
    public static let headerUserAgent = "User-Agent"
    
    // Content Types
    public static let contentTypeApplicationJSON = "application/json"
    public static let contentTypeTextPlain = "text/plain"
    public static let contentTypeNostrJSON = "application/nostr+json"
    
    // WebSocket Protocol
    public static let webSocketProtocolNostr = "nostr"
    
    // User Agent
    public static let userAgentNDKSwift = "NDKSwift"
}

/// HTTP status codes used throughout NDKSwift
public enum HTTPStatusCode {
    // Success responses (2xx)
    public static let ok = 200
    public static let created = 201
    public static let noContent = 204
    
    // Client error responses (4xx)
    public static let badRequest = 400
    public static let unauthorized = 401
    public static let forbidden = 403
    public static let notFound = 404
    public static let requestTimeout = 408
    public static let payloadTooLarge = 413
    public static let unsupportedMediaType = 415
    public static let tooManyRequests = 429
    
    // Server error responses (5xx)
    public static let internalServerError = 500
    public static let badGateway = 502
    public static let serviceUnavailable = 503
    public static let gatewayTimeout = 504
}

/// Well-known URL paths used in Nostr
public enum WellKnownPath {
    /// NIP-05 verification endpoint
    public static let nostrJson = "/.well-known/nostr.json"
    
    /// Lightning URL Pay endpoint
    public static let lnurlp = "/.well-known/lnurlp/"
}