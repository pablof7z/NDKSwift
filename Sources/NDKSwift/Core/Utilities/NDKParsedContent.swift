import Foundation

/// Parsed content structure for NDKContentParser
/// 
/// This struct represents the result of parsing Nostr event content, breaking it down
/// into its constituent components like text, mentions, hashtags, and URLs.
/// 
/// Example usage:
/// ```swift
/// let parser = NDKContentParser(currentUserPubkey: "abc123...")
/// let parsed = parser.parse(content: "Hello @npub1234... check out #bitcoin at https://example.com")
/// 
/// for component in parsed.components {
///     switch component {
///     case .text(let str):
///         print("Text: \(str)")
///     case .userMention(let pubkey, let npub):
///         print("User mention: \(npub)")
///     case .hashtag(let tag):
///         print("Hashtag: #\(tag)")
///     case .url(let url):
///         print("URL: \(url)")
///     default:
///         break
///     }
/// }
/// ```
public struct NDKParsedContent {
    /// The original unparsed content string
    public let original: String
    
    /// Array of parsed components in the order they appear in the content
    public let components: [Component]
    
    /// Whether the content mentions the current user (based on pubkey provided to parser)
    public let isMentioningCurrentUser: Bool

    public init(original: String, components: [Component], isMentioningCurrentUser: Bool) {
        self.original = original
        self.components = components
        self.isMentioningCurrentUser = isMentioningCurrentUser
    }

    /// Component types found in parsed content
    /// 
    /// Each case represents a different type of content element that can be
    /// identified and extracted from Nostr event content.
    public enum Component {
        /// Plain text content
        case text(String)
        
        /// User mention with both pubkey and npub format
        /// - Parameters:
        ///   - pubkey: The hex-encoded public key
        ///   - npub: The bech32-encoded public key (npub format)
        case userMention(pubkey: String, npub: String)
        
        /// Event mention (event ID in hex format)
        case eventMention(String)
        
        /// Hashtag without the # prefix
        case hashtag(String)
        
        /// URL found in the content
        case url(URL)
        
        /// Direct npub mention (bech32-encoded public key)
        case npubMention(String)
        
        /// Note ID mention (note1... format)
        case noteMention(String)
        
        /// Nevent mention (nevent1... format)
        case neventMention(String)
        
        /// Nprofile mention (nprofile1... format)
        case nprofileMention(String)
    }

    /// Component type enum for pattern matching
    /// 
    /// This enum mirrors the Component enum but is useful for pattern matching
    /// when you need to check component types without extracting associated values.
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