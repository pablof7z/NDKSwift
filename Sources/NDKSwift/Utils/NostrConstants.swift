/// Consolidated Nostr protocol constants for consistent usage across the codebase  
public enum NostrConstants {
    
    // MARK: - Protocol Prefixes
    
    public static let nostrPrefix = "nostr:"
    public static let nostrPrefixLength = 6
    
    // MARK: - Bech32 Prefixes
    
    public static let npubPrefix = "npub1"
    public static let notePrefix = "note1"
    public static let nprofilePrefix = "nprofile1"
    public static let neventPrefix = "nevent1"
    public static let naddrPrefix = "naddr1"
    
    // MARK: - JSON Field Names
    
    /// Core event fields used in event serialization
    public enum JSONField {
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
        
        // Cashu proof fields
        public static let amount = "amount"
        public static let secret = "secret"
        public static let C = "C"
        public static let proofs = "proofs"
        public static let proof = "proof"
        public static let mint = "mint"
        public static let unit = "unit"
        
        // Additional wallet event fields
        public static let direction = "direction"
        public static let state = "state"
    }
    
    // MARK: - Tag Names
    
    /// Tag names as defined in various NIPs
    public enum TagName {
        /// Public key tag ("p") - references a pubkey
        public static let pubkey = "p"
        
        /// Event ID tag ("e") - references an event
        public static let event = "e"
        
        /// Parameterized replaceable event tag ("a") - references a replaceable event
        public static let address = "a"
        
        /// Reference tag ("r") - references external resources
        public static let reference = "r"
        
        /// Hashtag ("t") - topic tags
        public static let hashtag = "t"
        
        /// Identifier tag ("d") - for replaceable events
        public static let identifier = "d"
        
        /// Kind tag ("k") - filters by event kind
        public static let kind = "k"
        
        /// Proxy tag ("proxy") - for delegated events
        public static let proxy = "proxy"
        
        /// Amount tag ("amount") - for payment-related events
        public static let amount = "amount"
        
        /// Title tag ("title") - for lists and other titled content
        public static let title = "title"
        
        /// Name tag ("name") - general naming
        public static let name = "name"
        
        /// Description tag ("description") - for detailed descriptions
        public static let description = "description"
        
        /// Image tag ("image") - for image URLs
        public static let image = "image"
        
        /// Bolt11 tag ("bolt11") - for Lightning invoices
        public static let bolt11 = "bolt11"
        
        /// Preimage tag ("preimage") - for Lightning payment preimages
        public static let preimage = "preimage"
        
        /// Challenge tag ("challenge") - for authentication challenges
        public static let challenge = "challenge"
        
        /// Relay tag ("relay") - for relay hints
        public static let relay = "relay"
        
        /// LNURL tag ("lnurl") - for Lightning URL
        public static let lnurl = "lnurl"
        
        /// Proof tag ("proof") - for proof of work or payment
        public static let proof = "proof"
        
        /// Mint tag ("mint") - for Cashu mint URLs
        public static let mint = "mint"
        
        /// Unit tag ("unit") - for currency units
        public static let unit = "unit"
        
        /// P2PK tag ("p2pk") - for peer-to-peer key
        public static let p2pk = "p2pk"
        
        /// URL tag ("u") - for URL references
        public static let url = "u"
        
        // MARK: - Uppercase Tags (used in comments and split zaps)
        
        /// Uppercase pubkey tag ("P") - used for split zaps and comment threads
        public static let uppercasePubkey = "P"
        
        /// Uppercase event tag ("E") - used in comment threads
        public static let uppercaseEvent = "E"
        
        /// Uppercase address tag ("A") - used in comment threads
        public static let uppercaseAddress = "A"
        
        /// Uppercase identifier tag ("I") - used in comment threads
        public static let uppercaseIdentifier = "I"
        
        /// Uppercase kind tag ("K") - used in comment threads
        public static let uppercaseKind = "K"
    }
    
    // MARK: - Tag Markers
    
    /// Marker values used in "e" and "p" tags
    public enum Marker {
        /// Reply marker - indicates this event is replying to the referenced event
        public static let reply = "reply"
        
        /// Root marker - indicates the root event of a thread
        public static let root = "root"
        
        /// Mention marker - indicates a mention without reply context
        public static let mention = "mention"
        
        /// Redeemed marker - for payment/token redemption
        public static let redeemed = "redeemed"
        
        /// Created marker - for creation timestamps
        public static let created = "created"
        
        /// Destroyed marker - for destruction/deletion timestamps
        public static let destroyed = "destroyed"
    }
    
    // MARK: - Profile Metadata Fields
    
    /// Standard fields in kind 0 (profile metadata) events
    public enum ProfileField {
        /// Display name
        public static let name = "name"
        
        /// Alternative display name field
        public static let displayName = "display_name"
        
        /// About/bio text
        public static let about = "about"
        
        /// Profile picture URL
        public static let picture = "picture"
        
        /// Banner/header image URL
        public static let banner = "banner"
        
        /// NIP-05 identifier
        public static let nip05 = "nip05"
        
        /// Lightning address (LNURL format)
        public static let lud16 = "lud16"
        
        /// Lightning URL
        public static let lud06 = "lud06"
        
        /// Website URL
        public static let website = "website"
    }
    
    // MARK: - Blossom-specific Values
    
    /// Tag values specific to Blossom file storage
    public enum BlossomTag {
        /// Authorization type: upload
        public static let upload = "upload"
        
        /// Authorization type: delete
        public static let delete = "delete"
        
        /// Authorization type: list
        public static let list = "list"
        
        /// Hash tag name
        public static let hash = "x"
        
        /// Size metadata field
        public static let size = "size"
        
        /// MIME type metadata field
        public static let type = "type"
        
        /// Expiration metadata field
        public static let expiration = "expiration"
    }
}