# NDKSwift API Specification

A comprehensive guide to all features and classes available in NDKSwift for building Nostr clients.

## Core Classes

### NDK
The main entry point for interacting with Nostr.

```swift
class NDK {
    // Initialize with optional signer, cache, and tracking configuration
    init(
        signer: NDKSigner? = nil, 
        cacheAdapter: NDKCacheAdapter? = nil,
        signatureVerificationConfig: NDKSignatureVerificationConfig = .default,
        subscriptionTrackingConfig: SubscriptionTrackingConfig = .default
    )
    
    // Relay management
    func addRelay(_ url: String) throws -> NDKRelay
    func connect()
    func disconnect()
    var relayPool: NDKRelayPool { get }
    
    // Publishing
    func publish(_ event: NDKEvent) async throws
    func publish(_ event: NDKEvent, to relayUrls: [String]) async throws
    
    // Subscriptions
    func subscribe(filters: [NDKFilter], options: NDKSubscriptionOptions? = nil) -> NDKSubscription
    
    // Event fetching
    func fetchEvent(_ idOrBech32: String, relays: Set<NDKRelay>? = nil) async throws -> NDKEvent?
    func fetchEvent(_ filter: NDKFilter, relays: Set<NDKRelay>? = nil) async throws -> NDKEvent?
    func fetchEvents(filters: [NDKFilter], relays: Set<NDKRelay>? = nil) async throws -> Set<NDKEvent>
    
    // User operations
    func user(withPubkey pubkey: String) -> NDKUser
    func user(withNpub npub: String) throws -> NDKUser
    
    // Signature verification
    var signatureVerificationConfig: NDKSignatureVerificationConfig?
    
    // Subscription tracking
    let subscriptionTracker: NDKSubscriptionTracker
}
```

### NDKEvent
Represents a Nostr event.

```swift
class NDKEvent {
    // Properties
    var id: String? { get }
    var pubkey: String
    var created_at: Timestamp
    var kind: Int
    var tags: [[String]]
    var content: String
    var sig: String? { get }
    
    // Creation
    init(ndk: NDK? = nil, kind: Int, content: String = "", tags: [[String]] = [], pubkey: String = "")
    
    // Operations
    func sign(signer: NDKSigner) async throws
    func verify() -> Bool
    func tag(forKey key: String) -> [String]?
    func referencedEvents() -> [String]
    func author() -> NDKUser
    
    // Content tagging
    func tagContent(includingHashtags: Bool = true) async throws
    
    // Reactions
    func react(withContent content: String = "+", signer: NDKSigner) async throws -> NDKEvent
    func reactions(ndk: NDK) async throws -> [NDKEvent]
}
```

### NDKFilter
Defines subscription filters.

```swift
struct NDKFilter {
    var ids: Set<String>?
    var authors: Set<String>?
    var kinds: Set<Int>?
    var since: Timestamp?
    var until: Timestamp?
    var limit: Int?
    var tags: [String: Set<String>]?  // e.g., ["e": Set<eventIds>]
    
    init(authors: Set<String>? = nil, kinds: Set<Int>? = nil, limit: Int? = nil)
}
```

### NDKUser
Represents a Nostr user.

```swift
class NDKUser {
    let pubkey: String
    var profile: UserProfile?
    
    // Profile data
    struct UserProfile {
        var name: String?
        var display_name: String?
        var about: String?
        var picture: String?
        var banner: String?
        var nip05: String?
        var lud06: String?
        var lud16: String?
    }
    
    // Operations
    func fetchProfile() async throws
    func npub() -> String
    func events(filter: NDKFilter) async throws -> [NDKEvent]
}
```

## Signers

### NDKSigner Protocol
```swift
protocol NDKSigner {
    var publicKey: String { get }
    func sign(event: NDKEvent) async throws -> String
    func sign(message: String) async throws -> String
}
```

### NDKPrivateKeySigner
Local key-based signing.

```swift
class NDKPrivateKeySigner: NDKSigner {
    init(privateKey: String) throws
    init(nsec: String) throws
    static func generate() throws -> NDKPrivateKeySigner
}
```

### NDKBunkerSigner
Remote signing via NIP-46.

```swift
class NDKBunkerSigner: NDKSigner {
    init(bunkerURI: String, ndk: NDK) async throws
    init(nostrConnectURI: String, ndk: NDK) async throws
    
    func connect() async throws
    func disconnect()
}
```

## Relay Management

### NDKRelayPool
```swift
actor NDKRelayPool {
    var relays: [String: NDKRelay] { get }
    
    func addRelay(_ relay: NDKRelay)
    func removeRelay(url: String)
    func connectAll()
    func disconnectAll()
    func publish(_ event: NDKEvent, to relayUrls: [String]? = nil) async throws
}
```

### NDKRelay
```swift
class NDKRelay {
    let url: String
    var connectionState: ConnectionState { get }
    
    enum ConnectionState {
        case disconnected, connecting, connected, failed(Error)
    }
}
```

## Subscriptions

### NDKSubscription
```swift
class NDKSubscription {
    let filters: [NDKFilter]
    var onEvent: ((NDKEvent) -> Void)?
    var onEose: (() -> Void)?
    
    func start()
    func stop()
    var isActive: Bool { get }
}
```

### NDKSubscriptionOptions
```swift
struct NDKSubscriptionOptions {
    var closeOnEose: Bool = false
    var cacheUsage: CacheUsage = .readWrite
    var groupable: Bool = true
    var subId: String?
}
```

## Caching

### NDKCacheAdapter Protocol
```swift
protocol NDKCacheAdapter {
    func saveEvent(_ event: NDKEvent) async throws
    func loadEvents(filter: NDKFilter) async throws -> [NDKEvent]
    func deleteEvent(id: String) async throws
    func saveUserProfile(_ profile: UserProfile, pubkey: String) async throws
    func loadUserProfile(pubkey: String) async throws -> UserProfile?
}
```

### Built-in Implementations
- `NDKInMemoryCache` - Temporary in-memory storage
- `NDKFileCache` - Persistent JSON-based storage

## Outbox Model (NIP-65)

### NDKOutbox
Advanced relay selection and publishing.

```swift
struct NDKOutboxConfig {
    var enableOutboxModel: Bool = false
    var defaultWriteRelays: Set<String> = []
    var defaultReadRelays: Set<String> = []
    var maxRelaysPerAuthor: Int = 3
}

// Publishing with outbox
let config = OutboxPublishConfig(
    recipientPubkeys: ["pubkey1", "pubkey2"],
    includeAuthorRelays: true,
    includeRecipientRelays: true,
    minRelayCount: 2,
    maxRelayCount: 5
)
await ndk.publish(event, config: config)
```

## Specialized Event Types

### NDKImage
Image events with metadata.

```swift
class NDKImage: NDKEvent {
    var url: String { get set }
    var blurhash: String?
    var dimension: String?
    var alt: String?
}
```

### NDKList
Generic list events (NIP-51).

```swift
class NDKList: NDKEvent {
    var name: String?
    var description: String?
    
    func items() -> [ListItem]
    func addItem(_ item: ListItem)
    func removeItem(_ item: ListItem)
}
```

### NDKContactList
User contact lists.

```swift
class NDKContactList: NDKEvent {
    func contacts() -> Set<String>
    func addContact(_ pubkey: String)
    func removeContact(_ pubkey: String)
}
```

### NDKRelayList
User relay preferences (NIP-65).

```swift
class NDKRelayList: NDKEvent {
    func relays() -> [RelayInfo]
    func writeRelays() -> [String]
    func readRelays() -> [String]
}
```

## Wallet Integration

### NDKWallet Protocol
```swift
protocol NDKWallet {
    var walletId: String { get }
    func balance() async throws -> Int
    func createInvoice(amount: Int, description: String?) async throws -> String
    func payInvoice(_ invoice: String) async throws -> NDKPaymentConfirmation
}
```

### NDKPaymentRouter
Routes payments to appropriate wallets.

```swift
class NDKPaymentRouter {
    func registerWallet(_ wallet: NDKWallet, forPrefix: String)
    func routePayment(_ request: NDKPaymentRequest) async throws -> NDKPaymentConfirmation
}
```

## Blossom Support

### BlossomClient
Decentralized file storage.

```swift
actor BlossomClient {
    init(servers: [String], signer: NDKSigner)
    
    // Upload files
    func upload(data: Data, mimeType: String?, servers: [String]? = nil) async throws -> [BlossomUpload]
    
    // Download files
    func download(sha256: String, servers: [String]? = nil) async throws -> (Data, String?)
    
    // List uploads
    func list(servers: [String]? = nil) async throws -> [[String: Any]]
}
```

## Utilities

### Bech32 (NIP-19)
```swift
struct Bech32 {
    static func decode(_ bech32String: String) throws -> (String, String)
    static func encode(prefix: String, hex: String) throws -> String
    
    // Convenience methods
    static func nsec(from privateKey: String) throws -> String
    static func npub(from publicKey: String) throws -> String
    static func note(from eventId: String) throws -> String
}
```

### ContentTagger
Automatic content tagging.

```swift
class ContentTagger {
    static func extractHashtags(from content: String) -> [String]
    static func findNostrEntities(in content: String) -> [(type: String, value: String, range: NSRange)]
    static func tagContent(_ content: String, includingHashtags: Bool = true) -> [[String]]
}
```

### Crypto
Cryptographic utilities.

```swift
struct Crypto {
    static func sha256(data: Data) -> Data
    static func randomBytes(count: Int) -> Data
    static func generateKeyPair() throws -> (privateKey: String, publicKey: String)
}
```

## Error Handling

### NDKError
```swift
enum NDKError: Error {
    case invalidKey(String)
    case signingFailed(String)
    case relayError(String)
    case networkError(Error)
    case cacheError(Error)
    case invalidFormat(String)
}
```

## Basic Usage Example

```swift
// Initialize NDK
let signer = try NDKPrivateKeySigner.generate()
let ndk = NDK(signer: signer, cacheAdapter: NDKFileCache())

// Connect to relays
try ndk.addRelay("wss://relay.damus.io")
try ndk.addRelay("wss://nos.lol")
ndk.connect()

// Create and publish an event
let event = NDKEvent(ndk: ndk, kind: 1, content: "Hello Nostr!")
try await event.sign(signer: signer)
try await ndk.publish(event)

// Subscribe to events
let filter = NDKFilter(kinds: [1], limit: 10)
let subscription = ndk.subscribe(filters: [filter])
subscription.onEvent = { event in
    print("Received: \(event.content)")
}
subscription.start()

// Fetch user profile
let user = ndk.user(withPubkey: "pubkey...")
try await user.fetchProfile()
print("User name: \(user.profile?.name ?? "Unknown")")
```

## Advanced Features

### Subscription Tracking
Monitor and debug subscription behavior across relays.

```swift
// Enable tracking with history
let ndk = NDK(
    subscriptionTrackingConfig: NDK.SubscriptionTrackingConfig(
        trackClosedSubscriptions: true,
        maxClosedSubscriptions: 100
    )
)

// Query metrics
let activeCount = await ndk.subscriptionTracker.activeSubscriptionCount()
let uniqueEvents = await ndk.subscriptionTracker.totalUniqueEventsReceived()

// Get detailed subscription information
if let detail = await ndk.subscriptionTracker.getSubscriptionDetail(subscription.id) {
    print("Unique events: \(detail.metrics.totalUniqueEvents)")
    print("Active relays: \(detail.metrics.activeRelayCount)")
    
    // Check relay-specific performance
    for (relayUrl, metrics) in detail.relayMetrics {
        print("\(relayUrl): \(metrics.eventsReceived) events")
    }
}

// Get global statistics
let stats = await ndk.subscriptionTracker.getStatistics()
print("Active subscriptions: \(stats.activeSubscriptions)")
print("Average events per subscription: \(stats.averageEventsPerSubscription)")

// Export all tracking data
let data = await ndk.subscriptionTracker.exportTrackingData()
```

### Signature Verification Sampling
```swift
ndk.signatureVerificationConfig = NDKSignatureVerificationConfig(
    enabled: true,
    samplingRate: 0.1,  // Verify 10% of events
    alwaysVerifyKinds: [0, 3]  // Always verify profiles and contact lists
)
```

### Outbox Model Publishing
```swift
// Enable outbox model
ndk.outboxConfig = NDKOutboxConfig(
    enableOutboxModel: true,
    defaultWriteRelays: ["wss://relay1.com", "wss://relay2.com"]
)

// Publish to specific recipients' relays
let config = OutboxPublishConfig(recipientPubkeys: ["pubkey1", "pubkey2"])
try await ndk.publish(event, config: config)
```

### Content Tagging
```swift
// Automatically tag mentions and hashtags
let event = NDKEvent(ndk: ndk, kind: 1, content: "Hello @npub1... #nostr")
try await event.tagContent()
// Tags are automatically added for mentions and hashtags
```

### File Upload with Blossom
```swift
let blossom = BlossomClient(servers: ["https://blossom.server"], signer: signer)
let imageData = Data(...)
let uploads = try await blossom.upload(data: imageData, mimeType: "image/jpeg")

// Create image event with Blossom URL
let imageEvent = NDKImage(url: uploads.first!.url)
imageEvent.blurhash = "LKN]Rv%2Tw=w]~RBVZRi};RPxuwH"
try await ndk.publish(imageEvent)
```