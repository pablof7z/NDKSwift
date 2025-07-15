import Foundation

/// Parsed content structure for NDKContentParser
public struct NDKParsedContent {
    public let original: String
    public let components: [Component]
    public let isMentioningCurrentUser: Bool
    
    public init(original: String, components: [Component], isMentioningCurrentUser: Bool) {
        self.original = original
        self.components = components
        self.isMentioningCurrentUser = isMentioningCurrentUser
    }
    
    /// Component types found in parsed content
    public enum Component {
        case text(String)
        case userMention(pubkey: String, npub: String)
        case eventMention(String)
        case hashtag(String)
        case url(URL)
        case npubMention(String)
        case noteMention(String)
        case neventMention(String)
        case nprofileMention(String)
    }
    
    /// Component type enum for pattern matching
    public enum ComponentType {
        case text
        case userMention(pubkey: String, npub: String)
        case eventMention(String)
        case hashtag(String)
        case url(URL)
        case npubMention(String)
        case noteMention(String)
        case neventMention(String)
        case nprofileMention(String)
    }
}

// Extension to add helper methods for converting pubkeys
public extension String {
    /// Convert a hex pubkey to npub format
    static func toNpub(_ pubkey: String) throws -> String {
        // This is a placeholder - in a real implementation, you'd use proper bech32 encoding
        // For now, just return a shortened version for display
        return "npub1\(pubkey.prefix(8))..."
    }
    
    /// Convert an npub to hex pubkey
    static func fromNpub(_ npub: String) throws -> String? {
        // This is a placeholder - in a real implementation, you'd use proper bech32 decoding
        // For now, return nil to indicate we need proper implementation
        return nil
    }
}