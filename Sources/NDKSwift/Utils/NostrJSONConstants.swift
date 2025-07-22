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
    
    // Profile fields (kind 0) - using NostrTagConstants for consistency
    public static let name = NostrTagConstants.ProfileField.name
    public static let about = NostrTagConstants.ProfileField.about
    public static let picture = NostrTagConstants.ProfileField.picture
    public static let nip05 = NostrTagConstants.ProfileField.nip05
    public static let banner = NostrTagConstants.ProfileField.banner
    public static let displayName = NostrTagConstants.ProfileField.displayName
    public static let website = NostrTagConstants.ProfileField.website
    public static let lud06 = NostrTagConstants.ProfileField.lud06
    public static let lud16 = NostrTagConstants.ProfileField.lud16
    
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