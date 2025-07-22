import Foundation

/// Extension to simplify tag validation and extraction in Nostr events
public extension Array where Element == [String] {
    /// Extracts all tags with the specified name
    /// - Parameters:
    ///   - tagName: The name of the tag to extract (e.g., "e", "p", "proof")
    ///   - minLength: Minimum required length for the tag (default: 2)
    /// - Returns: Array of tags matching the criteria
    func extractTags(named tagName: String, minLength: Int = 2) -> [[String]] {
        filter { $0.count >= minLength && $0[0] == tagName }
    }
    
    /// Finds the first tag with the specified name
    /// - Parameters:
    ///   - tagName: The name of the tag to find
    ///   - minLength: Minimum required length for the tag (default: 2)
    /// - Returns: The first matching tag, or nil if not found
    func firstTag(named tagName: String, minLength: Int = 2) -> [String]? {
        first { $0.count >= minLength && $0[0] == tagName }
    }
    
    /// Extracts the value (second element) of the first tag with the specified name
    /// - Parameter tagName: The name of the tag
    /// - Returns: The value of the first matching tag, or nil if not found
    func firstTagValue(named tagName: String) -> String? {
        firstTag(named: tagName)?[safe: 1]
    }
    
    /// Extracts all values (second elements) of tags with the specified name
    /// - Parameter tagName: The name of the tag
    /// - Returns: Array of values from matching tags
    func tagValues(named tagName: String) -> [String] {
        extractTags(named: tagName).compactMap { $0[safe: 1] }
    }
    
    /// Checks if a tag with the specified name exists
    /// - Parameter tagName: The name of the tag
    /// - Returns: true if at least one tag with the name exists
    func hasTag(named tagName: String) -> Bool {
        firstTag(named: tagName) != nil
    }
    
    /// Extracts event reference tags ("e" tags)
    var eventTags: [[String]] {
        extractTags(named: NostrTag.event)
    }
    
    /// Extracts pubkey reference tags ("p" tags)
    var pubkeyTags: [[String]] {
        extractTags(named: NostrTag.pubkey)
    }
    
    /// Extracts all event IDs from "e" tags
    var eventIds: [String] {
        tagValues(named: NostrTag.event)
    }
    
    /// Extracts all pubkeys from "p" tags
    var pubkeys: [String] {
        tagValues(named: NostrTag.pubkey)
    }
}


/// Common Nostr tag names
public enum NostrTag {
    public static let event = "e"
    public static let pubkey = "p"
    public static let proof = "proof"
    public static let url = "u"
    public static let kind = "k"
    public static let description = "d"
    public static let relay = "r"
    public static let amount = "amount"
    public static let lnurl = "lnurl"
    public static let name = "name"
    public static let zap = "zap"
    public static let altDescription = "alt"
    public static let contentWarning = "content-warning"
    public static let subject = "subject"
    public static let mention = "mention"
    public static let hashtag = "t"
    public static let reference = "reference"
    public static let delegation = "delegation"
    public static let nonce = "nonce"
    public static let title = "title"
    public static let summary = "summary"
    public static let publishedAt = "published_at"
    public static let client = "client"
    public static let labels = "l"
    public static let labelNamespace = "L"
    public static let mint = "mint"
    public static let privkey = "privkey"
    public static let nuts = "nuts"
    public static let network = "n"
    public static let contact = "contact"
    public static let unit = "unit"
    public static let a = "a"
}