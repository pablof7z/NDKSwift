import Foundation

/// Represents a parsed segment of Nostr content
public enum ContentSegment: Equatable, Sendable {
    /// Plain text content
    case text(String)
    
    /// Reference to a Nostr user
    case mention(NDKUser)
    
    /// Reference to a Nostr event
    case event(NDKEvent)
    
    /// Reference to a hashtag
    case hashtag(String)
    
    /// Reference to a URL
    case url(URL)
}

/// Represents parsed Nostr content with identified entities
public struct ParsedContent: Equatable, Sendable {
    /// The original content string
    public let original: String
    
    /// The parsed segments in order
    public let segments: [ContentSegment]
    
    /// All tags generated from the content
    public let tags: [Tag]
    
    public init(original: String, segments: [ContentSegment], tags: [Tag]) {
        self.original = original
        self.segments = segments
        self.tags = tags
    }
}

/// Options for content parsing
public struct ParseContentOptions: Sendable {
    /// Whether to fetch user profiles for mentions
    public let fetchUserProfiles: Bool
    
    /// Whether to fetch referenced events
    public let fetchReferencedEvents: Bool
    
    /// Whether to include hashtag segments
    public let includeHashtags: Bool
    
    /// Whether to include URL segments
    public let includeURLs: Bool
    
    /// Maximum number of relays to query for each entity
    public let maxRelaysPerEntity: Int
    
    /// Timeout for fetching entities
    public let fetchTimeout: TimeInterval
    
    public init(
        fetchUserProfiles: Bool = true,
        fetchReferencedEvents: Bool = true,
        includeHashtags: Bool = true,
        includeURLs: Bool = true,
        maxRelaysPerEntity: Int = 3,
        fetchTimeout: TimeInterval = 5.0
    ) {
        self.fetchUserProfiles = fetchUserProfiles
        self.fetchReferencedEvents = fetchReferencedEvents
        self.includeHashtags = includeHashtags
        self.includeURLs = includeURLs
        self.maxRelaysPerEntity = maxRelaysPerEntity
        self.fetchTimeout = fetchTimeout
    }
}