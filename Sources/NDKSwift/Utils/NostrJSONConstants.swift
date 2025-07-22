import Foundation

/// Constants for Nostr JSON field names used in event serialization
public struct NostrJSONConstants {
    // Core event fields
    public static let id = "id"
    public static let pubkey = "pubkey"
    public static let createdAt = "created_at"
    public static let kind = "kind"
    public static let tags = "tags"
    public static let content = "content"
    public static let sig = "sig"
    
    // Filter fields
    public static let ids = "ids"
    public static let authors = "authors"
    public static let kinds = "kinds"
    public static let since = "since"
    public static let until = "until"
    public static let limit = "limit"
    public static let search = "search"
    
    // Subscription fields
    public static let subscription = "subscription"
    
    // Profile fields (kind 0)
    public static let name = "name"
    public static let about = "about"
    public static let picture = "picture"
    public static let nip05 = "nip05"
    public static let banner = "banner"
    public static let displayName = "display_name"
    public static let website = "website"
    public static let lud06 = "lud06"
    public static let lud16 = "lud16"
    
    // NIP-05 fields
    public static let names = "names"
    public static let relays = "relays"
    
    // Auth fields
    public static let challenge = "challenge"
    public static let relay = "relay"
    
    // Wallet fields
    public static let balance = "balance"
    public static let mints = "mints"
    public static let p2pk = "p2pk"
}