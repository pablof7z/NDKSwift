# NDKSwift API Reference

Complete API documentation for NDKSwift v0.3.0+

## Table of Contents

- [Core Classes](#core-classes)
  - [NDK](#ndk)
  - [NDKEvent](#ndkevent)
  - [NDKFilter](#ndkfilter)
  - [NDKSubscription](#ndksubscription)
  - [NDKUser](#ndkuser)
  - [NDKRelay](#ndkrelay)
- [Protocols](#protocols)
  - [NDKSigner](#ndksigner)
  - [NDKCache](#ndkcache)
  - [NDKWallet](#ndkwallet)
- [Types and Enums](#types-and-enums)
- [Utilities](#utilities)

## Core Classes

### NDK

The main entry point for all NDKSwift functionality.

#### Initialization

```swift
public init(
    relayUrls: [RelayURL] = [],
    signer: NDKSigner? = nil,
    cache: NDKCache? = nil,
    signatureVerificationConfig: NDKSignatureVerificationConfig = .default,
    subscriptionTrackingConfig: SubscriptionTrackingConfig = .default
)
```

#### Properties

```swift
public var signer: NDKSigner?                    // Active signer for event signing
public var cache: NDKCache?                      // Cache implementation
public var activeUser: NDKUser? { get }          // Current user (from signer)
public var debugMode: Bool                       // Enable debug logging
public var outboxEnabled: Bool                   // Outbox model enabled (default: true)
public var outboxConfig: NDKOutboxConfig         // Outbox configuration
public var outbox: NDKOutboxManager { get }      // Simplified outbox API
public var subscriptionTracker: NDKSubscriptionTracker { get }
public var signatureVerificationConfig: NDKSignatureVerificationConfig { get }
public var optimisticPublishingConfig: NDKOptimisticPublishingConfig // Optimistic publishing configuration
public var relays: [NDKRelay] { get }           // All configured relays
public var pool: NDKRelayPool { get }           // Relay pool manager
```

#### Connection Management

```swift
// Connect to all configured relays
public func connect() async

// Disconnect from all relays
public func disconnect() async

// Add a relay
public func addRelay(_ url: RelayURL) -> NDKRelay

// Remove a relay
public func removeRelay(_ url: RelayURL)
```

#### Event Publishing

```swift
// Publish event (uses outbox model if enabled, optimistic publishing by default)
public func publish(_ event: NDKEvent) async throws -> Set<NDKRelay>

// Publish to specific relays
public func publish(event: NDKEvent, to relayUrls: Set<String>) async throws -> Set<NDKRelay>

// Optimistic publishing configuration
public var optimisticPublishingConfig: NDKOptimisticPublishingConfig
// Configure: enabled, cacheUnpublishedEvents, dispatchToSubscriptions

// Retry publishing unpublished events
public func retryUnpublishedEvents(maxAge: TimeInterval, limit: Int?) async throws -> [(event: NDKEvent, relays: Set<NDKRelay>)]
```

#### Subscriptions

```swift
// Create a subscription (AsyncSequence)
public func subscribe(
    filters: [NDKFilter],
    options: NDKSubscriptionOptions = .init()
) -> NDKSubscription

// One-shot fetch with multiple filters
public func fetchEvents(
    filters: [NDKFilter],
    relays: Set<NDKRelay>? = nil,
    useCache: Bool = true
) async throws -> Set<NDKEvent>

// One-shot fetch with single filter
public func fetchEvents(
    _ filter: NDKFilter,
    relays: Set<NDKRelay>? = nil,
    useCache: Bool = true
) async throws -> Set<NDKEvent>

// Fetch single event by ID or bech32
public func fetchEvent(
    _ idOrBech32: String,
    relays: Set<NDKRelay>? = nil,
    useCache: Bool = true
) async throws -> NDKEvent?

// Fetch first matching event
public func fetchEvent(
    _ filter: NDKFilter,
    relays: Set<NDKRelay>? = nil,
    useCache: Bool = true
) async throws -> NDKEvent?

// Fetch user profile
public func fetchProfile(
    _ pubkey: String,
    relays: Set<NDKRelay>? = nil,
    useCache: Bool = true
) async throws -> NDKUserProfile?
```

#### User Management

```swift
// Get user by public key
public func getUser(_ pubkey: PublicKey) -> NDKUser

// Get user by npub
public func getUser(npub: String) -> NDKUser?
```

#### Interactions (NIP-18, NIP-25, NIP-09)

```swift
// NIP-18: Reposts
// Repost an event
public func repost(_ event: NDKEvent) async throws -> NDKEvent

// Quote repost an event with a comment
public func quoteRepost(_ event: NDKEvent, comment: String) async throws -> NDKEvent

// NIP-25: Reactions
// React to an event
public func react(to event: NDKEvent, with content: String) async throws -> NDKEvent

// Like an event (+ reaction)
public func like(_ event: NDKEvent) async throws -> NDKEvent

// Dislike an event (- reaction)
public func dislike(_ event: NDKEvent) async throws -> NDKEvent

// NIP-09: Event Deletion
// Note: Use event.delete(ndk:reason:signer:) method instead of NDK-level methods
```

#### Statistics

```swift
// Get subscription statistics
public func getSubscriptionStats() async -> NDKSubscriptionManager.SubscriptionStats

// Get signature verification statistics
public func getSignatureVerificationStats() async -> (
    totalVerifications: Int,
    failedVerifications: Int,
    blacklistedRelays: Int
)
```

### NDKEvent

Represents a Nostr event.

#### Initialization

```swift
// Full initializer
public init(
    pubkey: PublicKey = "",
    createdAt: Timestamp = Timestamp(Date().timeIntervalSince1970),
    kind: Kind,
    tags: [Tag] = [],
    content: String = ""
)

// Convenience initializer
public init(content: String, tags: [Tag] = [])
```

#### Properties

```swift
public var id: EventID? { get }                  // Event ID (computed)
public var pubkey: PublicKey                     // Author's public key
public var createdAt: Timestamp                  // Unix timestamp
public var kind: Kind                            // Event kind
public var tags: [Tag]                           // Event tags
public var content: String                       // Event content
public var sig: Signature?                       // Event signature
public weak var ndk: NDK?                        // NDK instance reference
public var relay: NDKRelay?                      // Source relay

// Relay tracking
public var seenOnRelays: Set<String> { get }    // Relays where seen
public var relayPublishStatuses: [String: RelayPublishStatus] { get }
public var successfullyPublishedRelays: Set<String> { get }
public var failedPublishRelays: Set<String> { get }
public var wasPublished: Bool { get }            // Published successfully?

// Reply thread helpers
public var isReply: Bool { get }                 // Has reply tags?
public var replyEventId: String? { get }         // Direct reply to
public var rootEventId: String? { get }          // Thread root
public var mentionedEventIds: [String] { get }   // All mentioned events
public var mentionedPubkeys: [String] { get }    // All mentioned pubkeys
```

#### Methods

```swift
// Generate event ID
public func generateID() throws -> EventID

// Validate event structure
public func validate() throws

// Sign event (uses NDK's signer)
public func sign() async throws

// Serialize to JSON
public func serialize() throws -> String

// Get raw event dictionary
public func rawEvent() -> [String: Any]

// Encode to bech32 (NIP-19)
public func encode(includeRelays: Bool = false) throws -> String

// NIP-18: Reposts
// Create a repost of this event
public func repost(signer: NDKSigner) async throws -> NDKEvent

// Create a quote repost of this event (kind 1 with q tag)
public func quoteRepost(comment: String, signer: NDKSigner) async throws -> NDKEvent

// NIP-25: Reactions
// Create a reaction to this event
public func react(with content: String, signer: NDKSigner) async throws -> NDKEvent

// Create a like reaction (+)
public func like(signer: NDKSigner) async throws -> NDKEvent

// Create a dislike reaction (-)
public func dislike(signer: NDKSigner) async throws -> NDKEvent

// NIP-09: Event Deletion
// Create a deletion request for this event
public func createDeletionRequest(reason: String = "", signer: NDKSigner) async throws -> NDKEvent

// Create a reply
public func createReply(
    content: String,
    mentionAuthor: Bool = true
) -> NDKEvent
```

#### Tag Helpers

```swift
// Get all tags with name
public func tags(withName name: String) -> [Tag]

// Get first tag with name
public func tag(withName name: String) -> Tag?

// Add a tag
public func addTag(_ tag: Tag)

// Tag a user
public func tag(user: NDKUser, marker: String? = nil)

// Tag an event
public func tag(event: NDKEvent, marker: String? = nil, relay: String? = nil)

// Get tag value
public func tagValue(_ name: String) -> String?

// Get referenced events
public func taggedEvents() -> [String]

// Get referenced users
public func taggedUsers() -> [String]

// Set content with auto-tagging
public func setContent(_ newContent: String, generateTags: Bool = true)

// Generate content tags manually
public func generateContentTags()
```

### NDKFilter

Filter for querying events.

#### Initialization

```swift
public init(
    ids: [EventID]? = nil,
    authors: [PublicKey]? = nil,
    kinds: [Kind]? = nil,
    events: [EventID]? = nil,      // #e tags
    pubkeys: [PublicKey]? = nil,   // #p tags
    since: Timestamp? = nil,
    until: Timestamp? = nil,
    limit: Int? = nil,
    tags: [String: Set<String>]? = nil
)
```

#### Properties

All initialization parameters are available as public properties.

#### Methods

```swift
// Check if event matches filter
public func matches(event: NDKEvent) -> Bool

// Add tag filter
public func addTagFilter(_ tagName: String, values: [String])

// Get tag filter values
public func tagFilter(_ tagName: String) -> [String]?
```

### NDKSubscription

AsyncSequence-based subscription for real-time event streaming.

#### Properties

```swift
public let id: String                            // Unique subscription ID
public let filters: [NDKFilter]                  // Applied filters
public let options: NDKSubscriptionOptions       // Subscription options

// State (async properties)
public var isActive: Bool { get async }          // Is subscription active?
public var isClosed: Bool { get async }          // Is subscription closed?
public var eoseReceived: Bool { get async }      // End of stored events received?
```

#### AsyncSequence Conformance

```swift
// Use in async for-await loop
for try await event in subscription {
    // Process each event
}
```

#### Methods

```swift
// Close subscription
public func close() async

// Update relay set
public func updateRelays(_ relays: Set<NDKRelay>) async
```

### NDKSubscriptionOptions

Configuration for subscriptions.

```swift
public struct NDKSubscriptionOptions {
    public var closeOnEose: Bool = false         // Auto-close on EOSE
    public var useCache: Bool = true             // Check cache first
    public var limit: Int?                       // Max events to receive
    public var timeout: TimeInterval?            // Subscription timeout
    public var relays: Set<NDKRelay>?           // Specific relays to use
    public var skipOptimisticEvents: Bool = false // Skip optimistic events (default: false)
}
```

### NDKUser

Represents a Nostr user.

#### Initialization

```swift
// From public key
public init(pubkey: PublicKey)

// From npub
public init?(npub: String)

// From NIP-05 identifier
public static func fromNip05(
    _ nip05: String,
    ndk: NDK
) async throws -> NDKUser
```

#### Properties

```swift
public let pubkey: PublicKey                     // User's public key
public var profile: NDKUserProfile?              // Profile metadata
public var relayList: [NDKRelayInfo]            // User's relay list
public var npub: String { get }                  // Bech32 encoded pubkey

// Computed from profile
public var displayName: String? { get }          // Display name or name
public var name: String? { get }                 // Profile name
public var nip05: String? { get }               // NIP-05 identifier
public var picture: String? { get }              // Profile picture URL
public var banner: String? { get }               // Banner image URL
public var about: String? { get }                // Profile description
public var lud16: String? { get }               // Lightning address
public var lud06: String? { get }               // LNURL

// Helpers
public var shortPubkey: String { get }           // First 8 chars of pubkey
```

#### Methods

```swift
// Fetch user profile
public func fetchProfile(
    forceRefresh: Bool = false
) async throws -> NDKUserProfile?

// Fetch relay list
public func fetchRelayList() async throws -> [NDKRelayInfo]

// Get users this user follows
public func follows() async throws -> Set<NDKUser>

// Check if follows specific user
public func follows(_ user: NDKUser) async throws -> Bool

// Pay user (requires wallet)
public func pay(
    amount: Int64,
    comment: String? = nil,
    tags: [[String]]? = nil
) async throws -> NDKPaymentConfirmation

// Get payment methods
public func getPaymentMethods() async throws -> Set<NDKPaymentMethod>
```

### NDKUserProfile

User profile metadata (kind 0).

```swift
public struct NDKUserProfile: Codable {
    public var name: String?
    public var displayName: String?
    public var about: String?
    public var picture: String?
    public var banner: String?
    public var nip05: String?
    public var lud16: String?                    // Lightning address
    public var lud06: String?                    // LNURL
    public var website: String?
    
    // Additional fields
    public func additionalField(_ key: String) -> Any?
    public mutating func setAdditionalField(_ key: String, value: Any?)
}
```

### NDKRelay

Individual relay connection.

#### Properties

```swift
public let url: RelayURL                         // Relay URL
public var connectionState: ConnectionState { get async }
public var activeSubscriptions: Int { get async }
```

#### Methods

```swift
// Connect to relay
public func connect() async throws

// Disconnect from relay
public func disconnect() async

// Send raw message
public func send(_ message: String) async throws

// Observe connection state changes
public func observeConnectionState(
    _ handler: @escaping (ConnectionState) -> Void
) -> AnyCancellable
```

#### ConnectionState

```swift
public enum ConnectionState {
    case disconnected
    case connecting
    case connected
    case failed(Error)
}
```

## Protocols

### NDKSigner

Protocol for event signing implementations.

```swift
public protocol NDKSigner {
    // Get public key
    var pubkey: PublicKey { get async throws }
    
    // Sign event
    func sign(_ event: NDKEvent) async throws -> Signature
    
    // Sign event in place
    func sign(event: inout NDKEvent) async throws
    
    // Wait until signer is ready
    func blockUntilReady() async throws
    
    // Get user
    func user() async throws -> NDKUser
    
    // Get recommended relays
    func relays(ndk: NDK?) async -> [NDKRelay]
    
    // Encryption support
    func encryptionEnabled() async -> [NDKEncryptionScheme]
    
    // Encrypt message
    func encrypt(
        recipient: NDKUser,
        value: String,
        scheme: NDKEncryptionScheme
    ) async throws -> String
    
    // Decrypt message
    func decrypt(
        sender: NDKUser,
        value: String,
        scheme: NDKEncryptionScheme
    ) async throws -> String
}
```

#### Implementations

**NDKPrivateKeySigner** - Local private key signing:

```swift
// From hex private key
public init(privateKey: String) throws

// From nsec
public init(nsec: String) throws

// Generate new key
public static func generate() throws -> NDKPrivateKeySigner

// Properties
public let privateKey: String
public let publicKey: PublicKey
public var nsec: String { get }
```

**NDKBunkerSigner** - Remote signing (NIP-46):

```swift
public init(
    localKeyPair: KeyPair? = nil,
    remotePubkey: String,
    relayUrls: [String],
    logger: Logger? = nil
)

// Connect to bunker
public func connect(
    localSigner: NDKPrivateKeySigner,
    remotePubkey: String,
    bunkerClient: NDKBunkerClient,
    secret: String? = nil,
    appInfo: AppInfo? = nil
) async throws
```

### NDKCache

Protocol for cache implementations (actor-based).

```swift
public protocol NDKCache: Actor {
    // Event operations
    func saveEvent(_ event: NDKEvent) async throws
    func getEvent(id: String) async -> NDKEvent?
    func queryEvents(_ filter: NDKFilter) async -> [NDKEvent]
    func deleteEvent(id: String) async throws
    
    // Profile operations
    func saveProfile(_ profile: NDKUserProfile, pubkey: String) async throws
    func getProfile(pubkey: String) async -> NDKUserProfile?
    
    // Optimistic publishing support
    func addUnpublishedEvent(_ event: NDKEvent, relays: Set<String>) async throws
    func confirmEvent(eventId: String, onRelay relay: String) async throws
    func getEventConfirmationState(eventId: String) async -> EventConfirmationState?
    func getUnpublishedEvents(maxAge: TimeInterval, limit: Int?) async -> [(event: NDKEvent, targetRelays: Set<String>)]
    
    // Management
    func clear() async throws
}
```

#### Implementations

**SimpleMemoryCache** - In-memory cache:
```swift
public actor SimpleMemoryCache: NDKCache
```

**NDKSQLiteCache** - SQLite persistent cache:
```swift
public actor NDKSQLiteCache: NDKCache {
    public init(databasePath: String? = nil) throws
}
```

### NDKWallet

Protocol for wallet implementations.

```swift
public protocol NDKWallet {
    // Make payment
    func pay(_ request: NDKPaymentRequest) async throws -> NDKPaymentConfirmation
    
    // Get balance
    func getBalance() async throws -> Int64
    
    // Create invoice
    func createInvoice(
        amount: Int64,
        description: String?
    ) async throws -> String
    
    // Check support
    func supports(method: NDKPaymentMethod) -> Bool
}
```

#### NDKNWCWallet

Nostr Wallet Connect implementation:

```swift
// From connection URI
public init(connectionURI: String) throws

// Manual configuration
public init(
    pubkey: String,
    relayUrl: String,
    walletPubkey: String? = nil,
    secret: String? = nil
) throws

// Connection management
public func connect() async throws
public func disconnect() async

// NWC methods
public func getInfo() async throws -> GetInfoResponse
public func makeInvoice(params: MakeInvoiceRequest) async throws -> MakeInvoiceResponse
public func payInvoice(params: PayInvoiceRequest) async throws -> PayInvoiceResponse
public func payKeysend(params: PayKeysendRequest) async throws -> PayKeysendResponse
public func getBalance() async throws -> GetBalanceResponse
public func listTransactions(params: ListTransactionsRequest?) async throws -> ListTransactionsResponse
```

#### NDKCashuWallet

Cashu wallet implementation (NIP-60/61):

```swift
// Initialize wallet
public init(signer: NDKSigner, ndk: NDK)

// Connection
public func connect() async
public func disconnect() async

// Balance and state
public var totalBalance: Int { get async }
public var mints: [String] { get async }

// Mint management
public func addMint(url: String) async throws
public func removeMint(url: String) async throws

// Token operations
public func mintQuote(amount: Int, mintUrl: String? = nil) async throws -> MintQuote
public func mint(quote: MintQuote) async throws -> [Proof]
public func meltQuote(invoice: String, mintUrl: String? = nil) async throws -> MeltQuote
public func melt(quote: MeltQuote) async throws -> MeltResponse

// Cashu transactions
public func send(amount: Int, mintUrl: String? = nil, memo: String? = nil) async throws -> CashuToken
public func receive(token: String) async throws -> ReceiveResponse
public func swap(proofs: [Proof], mintUrl: String) async throws -> [Proof]

// Relay health monitoring (NIP-60 relay tags)
public func getRelayHealth() async -> [RelayHealth]
public func repairRelay(_ targetRelay: NDKRelay, missingEventIds: [String]) async throws
public func getCurrentWalletEvents() async throws -> [NDKEvent]

// RelayHealth structure
public struct RelayHealth: Sendable {
    public let relay: NDKRelay
    public let knownEvents: Int
    public let missingEvents: [String]    // Event IDs missing from this relay
    public let extraEvents: [String]      // Event IDs that shouldn't be on this relay
    public let isHealthy: Bool            // True if no missing/extra events
}

// Nutzaps (NIP-61)
public func nutzap(
    amount: Int,
    comment: String? = nil,
    recipient: NDKUser,
    eventId: String? = nil,
    mintUrl: String? = nil
) async throws -> NDKEvent

// P2PK operations
public func createP2PKLockedToken(
    amount: Int,
    recipientPubkey: String,
    mintUrl: String? = nil
) async throws -> CashuToken
```

## Types and Enums

### Basic Types

```swift
public typealias PublicKey = String              // Hex encoded public key
public typealias PrivateKey = String             // Hex encoded private key
public typealias EventID = String                // Hex encoded event ID
public typealias Signature = String              // Hex encoded signature
public typealias Timestamp = Int64               // Unix timestamp
public typealias Kind = Int                      // Event kind
public typealias Tag = [String]                  // Tag array
public typealias RelayURL = String               // Relay websocket URL
```

### EventKind

Common event kinds.

### NDKError

Error types:

```swift
public enum NDKError: LocalizedError {
    case signerRequired
    case invalidEvent(String)
    case invalidKey(String)
    case signingFailed(String)
    case relayError(String)
    case cacheError(String)
    case networkError(String)
    case encodingError(String)
    case decodingError(String)
    case validationError(String)
    case notFound
    case timeout
    case cancelled
}
```

### RelayPublishStatus

```swift
public enum RelayPublishStatus {
    case pending
    case success
    case failed(Error)
}
```

### Optimistic Publishing Types

#### EventSource

```swift
public enum EventSource: Sendable {
    case optimistic                              // Locally published event
    case relay(RelayProtocol)                   // Event from relay
    case cache                                  // Event from cache
}
```

#### EventConfirmationState

```swift
public enum EventConfirmationState: Equatable, Sendable {
    case optimistic                             // Event published optimistically
    case confirmed(fromRelay: String)           // Event confirmed by relay
    
    public var isConfirmed: Bool { get }        // True if confirmed
}
```

#### NDKOptimisticPublishingConfig

```swift
public struct NDKOptimisticPublishingConfig: Sendable {
    public var enabled: Bool = true                      // Enable optimistic publishing
    public var cacheUnpublishedEvents: Bool = true      // Cache unpublished events
    public var dispatchToSubscriptions: Bool = true     // Dispatch to subscriptions
    
    public static let disabled: NDKOptimisticPublishingConfig // Disabled configuration
}
```

## Utilities

### Bech32

NIP-19 encoding/decoding:

```swift
// Encode to bech32
public static func npub(from pubkey: PublicKey) throws -> String
public static func nsec(from privateKey: PrivateKey) throws -> String
public static func note(from eventId: EventID) throws -> String
public static func nevent(
    eventId: EventID,
    relays: [String]? = nil,
    author: PublicKey? = nil,
    kind: Int? = nil
) throws -> String
public static func naddr(
    identifier: String,
    kind: Int,
    author: PublicKey,
    relays: [String]? = nil
) throws -> String

// Decode from bech32
public static func decode(_ bech32: String) throws -> Bech32Entity

public enum Bech32Entity {
    case npub(String)
    case nsec(String)
    case note(String)
    case nevent(eventId: String, relays: [String], author: String?, kind: Int?)
    case naddr(identifier: String, kind: Int, author: String, relays: [String])
}
```

### Crypto

Cryptographic utilities:

```swift
// Key generation
public static func generateKeyPair() throws -> KeyPair

// Get public key from private
public static func getPublicKey(from privateKey: PrivateKey) throws -> PublicKey

// Event signing
public static func signEvent(
    _ event: NDKEvent,
    with privateKey: PrivateKey
) throws -> Signature

// Signature verification
public static func verifySignature(of event: NDKEvent) -> Bool

// NIP-04 encryption
public static func encrypt(
    _ plaintext: String,
    recipientPubkey: PublicKey,
    senderPrivkey: PrivateKey
) throws -> String

public static func decrypt(
    _ ciphertext: String,
    senderPubkey: PublicKey,
    recipientPrivkey: PrivateKey
) throws -> String

// NIP-44 encryption
public static func nip44Encrypt(
    _ plaintext: String,
    recipientPubkey: PublicKey,
    senderPrivkey: PrivateKey
) throws -> String

public static func nip44Decrypt(
    _ payload: String,
    senderPubkey: PublicKey,
    recipientPrivkey: PrivateKey
) throws -> String
```

### ContentTagger

Auto-generate tags from content:

```swift
public static func generateContentTags(
    from content: String,
    existingTags: [Tag] = []
) -> (content: String, tags: [Tag])
```

### BlossomClient

File storage with Blossom protocol:

```swift
// Discover server capabilities
public func discoverServer(_ serverURL: String) async throws -> BlossomServerDescriptor

// Upload file
public func upload(
    data: Data,
    mimeType: String? = nil,
    to serverURL: String,
    auth: BlossomAuth
) async throws -> BlossomBlob

// Download file
public func download(
    sha256: String,
    from serverURL: String
) async throws -> Data

// Delete file
public func delete(
    sha256: String,
    from serverURL: String,
    auth: BlossomAuth
) async throws

// List files
public func list(
    from serverURL: String,
    auth: BlossomAuth,
    since: Date? = nil,
    until: Date? = nil
) async throws -> [BlossomBlob]
```

## Configuration Types

### NDKSignatureVerificationConfig

```swift
public struct NDKSignatureVerificationConfig {
    public var enabled: Bool = true
    public var blacklistRelaysOnFailure: Bool = true
    public var failureThreshold: Int = 10
    public var samplingRate: Double = 1.0       // 1.0 = verify all
    
    public static let `default` = NDKSignatureVerificationConfig()
    public static let disabled = NDKSignatureVerificationConfig(enabled: false)
}
```

### NDKOutboxConfig

```swift
public struct NDKOutboxConfig {
    public var enabled: Bool = true
    public var relayMinimum: Int = 2            // Min relays per operation
    public var relayMaximum: Int = 5            // Max relays per operation
    public var preferredRelayURLS: Set<String> = []
    
    public static let `default` = NDKOutboxConfig()
}
```

### SubscriptionTrackingConfig

```swift
public struct SubscriptionTrackingConfig {
    public var enabled: Bool = false
    public var dedupingWindow: TimeInterval = 1.0
    public var groupingDelay: TimeInterval = 0.1
    
    public static let `default` = SubscriptionTrackingConfig()
}
```

## Logging and Debugging

### NDKLogger

Configurable logging system for debugging network traffic and NDK operations.

#### Configuration

```swift
// Enable/disable network traffic logging
NDKLogger.shared.logNetworkTraffic = true          // Default: true

// Enable/disable pretty printing of messages
NDKLogger.shared.prettyPrintNetworkMessages = true // Default: true

// Set overall log level
NDKLogger.shared.logLevel = .info                  // Default: .info
// Options: .off, .error, .warning, .info, .debug, .trace

// Enable specific log categories
NDKLogger.shared.enabledCategories = [.network, .relay, .event]
```

#### Log Levels

```swift
public enum NDKLogLevel: Int, Comparable {
    case off = 0      // No logging
    case error = 1    // Only errors
    case warning = 2  // Errors and warnings
    case info = 3     // Informational messages (default)
    case debug = 4    // Debug information
    case trace = 5    // Detailed trace logging
}
```

#### Log Categories

```swift
public enum NDKLogCategory: String {
    case network      // Network traffic (send/receive)
    case relay        // Relay connection events
    case subscription // Subscription lifecycle
    case event        // Event processing
    case cache        // Cache operations
    case auth         // Authentication
    case general      // General logging
}
```

#### Network Traffic Output

When `logNetworkTraffic` is enabled, you'll see formatted output like:

```
📤 SENDING TO relay.damus.io:
   TYPE: REQ
   SUBSCRIPTION: sub_12345
   FILTERS: 1
     FILTER 1:
       KINDS: [1]
       AUTHORS: 2 pubkeys
       LIMIT: 10
   RAW: ["REQ","sub_12345",{"kinds":[1],"authors":["..."],"limit":10}]

📥 RECEIVED FROM relay.damus.io:
   TYPE: EVENT
   SUBSCRIPTION: sub_12345
   EVENT ID: 4a5e8f...
   KIND: 1
   AUTHOR: 3bf0c6...
   CONTENT: Hello Nostr!
   RAW: ["EVENT","sub_12345",{"id":"4a5e8f...","pubkey":"3bf0c6...","created_at":1234567890,"kind":1,"tags":[],"content":"Hello Nostr!","sig":"..."}]
```

#### Custom Logging

```swift
// Log custom messages
NDKLogger.shared.log(.debug, category: .general, "Custom debug message")
NDKLogger.shared.log(.error, category: .network, "Connection failed: \(error)")
```

See [NetworkLoggingDemo.swift](../Examples/NetworkLoggingDemo.swift) for a complete example.

## Best Practices

1. **Always use async/await** - All network operations are asynchronous
2. **Handle errors appropriately** - Network operations can fail
3. **Use AsyncSequence for subscriptions** - Modern pattern for event streaming
4. **Enable caching for better performance** - Reduces network requests
5. **Set appropriate relay limits** - Don't overwhelm relays with requests
6. **Verify signatures when needed** - But consider performance impact
7. **Use outbox model** - Better relay selection and routing (enabled by default)
8. **Close subscriptions when done** - Prevents resource leaks
9. **Configure logging appropriately** - Use `.debug` or `.trace` for development, `.error` for production

## Migration from Callbacks

If migrating from older callback-based code:

```swift
// Old pattern (deprecated)
subscription.onEvent { event in
    // Handle event
}
subscription.start()

// New pattern (recommended)
for await event in subscription {
    // Handle event
}
```

The new AsyncSequence pattern is cleaner, automatically manages lifecycle, and integrates better with Swift's async/await ecosystem.