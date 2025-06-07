# NDKSwift API Reference

## Table of Contents
- [Core Classes](#core-classes)
- [Models](#models)
- [Signers](#signers)
- [Relay Management](#relay-management)
- [Subscriptions](#subscriptions)
- [Subscription Management](#subscription-management)
- [Subscription Tracking](#subscription-tracking)
- [Caching](#caching)
- [Utilities](#utilities)
- [Wallet System](#wallet-system)
- [Blossom Support](#blossom-support)

## Core Classes

### NDK
The main entry point for all NDKSwift functionality.

```swift
public final class NDK {
    // Properties
    public var signer: NDKSigner?
    public var cacheAdapter: NDKCacheAdapter?
    public var activeUser: NDKUser?
    public var debugMode: Bool
    public var paymentRouter: NDKPaymentRouter?
    public var walletConfig: NDKWalletConfig?
    
    // Relay Management
    public var relays: [NDKRelay] { get }
    public var pool: NDKRelayPool { get }
    
    // Subscription Tracking
    public let subscriptionTracker: NDKSubscriptionTracker
    
    // Initialization
    public init(
        relayUrls: [RelayURL] = [],
        signer: NDKSigner? = nil,
        cacheAdapter: NDKCacheAdapter? = nil,
        signatureVerificationConfig: NDKSignatureVerificationConfig = .default,
        subscriptionTrackingConfig: SubscriptionTrackingConfig = .default
    )
    
    // Connection Management
    public func connect() async
    public func disconnect() async
    public func addRelay(_ url: RelayURL) -> NDKRelay
    public func removeRelay(_ url: RelayURL)
    
    // Subscription with Advanced Management
    public func subscribe(
        filters: [NDKFilter],
        options: NDKSubscriptionOptions = NDKSubscriptionOptions()
    ) -> NDKSubscription
    
    public func fetchEvents(
        filters: [NDKFilter],
        relays: Set<NDKRelay>? = nil
    ) async throws -> Set<NDKEvent>
    
    public func fetchEvent(_ idOrBech32: String, relays: Set<NDKRelay>? = nil) async throws -> NDKEvent?
    public func fetchEvent(_ filter: NDKFilter, relays: Set<NDKRelay>? = nil) async throws -> NDKEvent?
    
    // Publishing
    public func publish(_ event: NDKEvent) async throws -> Set<NDKRelay>
    
    // User Management
    public func getUser(_ pubkey: PublicKey) -> NDKUser
    public func getUser(npub: String) -> NDKUser?
    
    // Subscription Manager
    public func getSubscriptionStats() async -> NDKSubscriptionManager.SubscriptionStats
}
```

## Event Fetching

### Fetching Single Events

The `fetchEvent` method supports multiple identifier formats for maximum flexibility:

```swift
// Fetch by hex event ID (64 character hex string)
let event1 = try await ndk.fetchEvent("5c83da77af1dec6d7289834998ad7aafbd9e2191396d75ec3cc27f5a77226f36")

// Fetch by note ID (NIP-19 bech32 format starting with 'note1')
let event2 = try await ndk.fetchEvent("note1tjpatmavrmkx6u5fsdyc44m647w7uxg3jmt4akpucfl6wuex7umqk7y5ph")

// Fetch by nevent (NIP-19 format that includes relay hints and metadata)
let event3 = try await ndk.fetchEvent("nevent1qqstjpatmavrmkx6u5fsdyc44m647w7uxg3jmt4akpucfl6wuex7umgpz3mhxue69uhhyetvv9ujuerpd46hxtnfduq36amnwvaz7tmjv4kxz7fwd46hg6tw09mkzmrvv46zucm0d5hs0dqul7")

// Fetch replaceable event by naddr (NIP-19 format for parameterized replaceable events)
// naddr includes: author pubkey, kind, and identifier (d tag)
let event4 = try await ndk.fetchEvent("naddr1qq9rzd3exgenjv34xqmr2wfekgenjdp5qy2hwumn8ghj7un9d3shjtnyv9kh2uewd9hj7qpqgegazpzx8n5z5zq7jz6gute3cvsqn0athf5dlctusn8tr74vxsqn428x3")

// Specify specific relays to query
let relays = Set([relay1, relay2])
let event5 = try await ndk.fetchEvent("note1...", relays: relays)

// Fetch using a filter
let filter = NDKFilter(authors: ["pubkey"], kinds: [1], limit: 1)
let event6 = try await ndk.fetchEvent(filter)
```

### Fetching Multiple Events

```swift
// Fetch events matching filters
let filters = [
    NDKFilter(kinds: [1], authors: ["pubkey1", "pubkey2"], limit: 100),
    NDKFilter(kinds: [3], authors: ["pubkey3"])
]
let events = try await ndk.fetchEvents(filters: filters)

// Fetch from specific relays
let events2 = try await ndk.fetchEvents(filters: filters, relays: Set([relay1, relay2]))
```

## Models

### NDKEvent
Represents a Nostr event with all required fields, validation, and NIP-19 encoding support.

```swift
public final class NDKEvent: Codable, Equatable, Hashable {
    // Properties
    public var id: EventID?
    public var pubkey: PublicKey
    public var createdAt: Timestamp
    public var kind: Kind
    public var tags: [Tag]
    public var content: String
    public var sig: Signature?
    
    // References
    public weak var ndk: NDK?
    public private(set) var relay: NDKRelay?
    
    // Initialization
    public init(
        pubkey: PublicKey,
        createdAt: Timestamp = Timestamp(Date().timeIntervalSince1970),
        kind: Kind,
        tags: [Tag] = [],
        content: String = ""
    )
    
    public convenience init(content: String = "", tags: [Tag] = [])
    
    // ID and Signing
    public func generateID() throws -> EventID
    public func validate() throws
    public func sign() async throws
    public func serialize() throws -> String
    
    // Tag Helpers
    public func tags(withName name: String) -> [Tag]
    public func tag(withName name: String) -> Tag?
    public func addTag(_ tag: Tag)
    public func tag(user: NDKUser, marker: String? = nil)
    public func tag(event: NDKEvent, marker: String? = nil, relay: String? = nil)
    public func tagValue(_ name: String) -> String?
    
    // References
    public var referencedEventIds: [EventID] { get }
    public var referencedPubkeys: [PublicKey] { get }
    
    // Event Properties
    public var isReply: Bool { get }
    public var replyEventId: EventID? { get }
    public var isEphemeral: Bool { get }
    public var isReplaceable: Bool { get }
    public var isParameterizedReplaceable: Bool { get }
    public var tagAddress: String { get }
    
    // NIP-19 Encoding
    public func encode(includeRelays: Bool = false) throws -> String
    
    // Event Reactions
    public func react(content: String, publish: Bool = true) async throws -> NDKEvent
}
```

### NDKFilter
Defines subscription filters for querying events.

```swift
public struct NDKFilter: Codable, Sendable {
    // Properties
    public var ids: [String]?
    public var authors: [String]?
    public var kinds: [EventKind]?
    public var since: Timestamp?
    public var until: Timestamp?
    public var limit: Int?
    public var search: String?
    public var tags: [String: [String]]?
    
    // Initialization
    public init(
        ids: [String]? = nil,
        authors: [String]? = nil,
        kinds: [EventKind]? = nil,
        since: Timestamp? = nil,
        until: Timestamp? = nil,
        limit: Int? = nil,
        search: String? = nil,
        tags: [String: [String]]? = nil
    )
    
    // Methods
    public func matches(_ event: NDKEvent) -> Bool
}
```

### NDKUser
Represents a Nostr user with profile information and NIP-19 encoding support.

```swift
public final class NDKUser: Equatable, Hashable {
    // Properties
    public let pubkey: PublicKey
    public weak var ndk: NDK?
    public private(set) var profile: NDKUserProfile?
    public private(set) var relayList: [NDKRelayInfo] = []
    
    // Computed Properties
    public var npub: String { get }  // Bech32 encoded public key
    public var displayName: String? { get }
    public var name: String? { get }
    public var nip05: String? { get }
    public var shortPubkey: String { get }  // Truncated pubkey for display
    
    // Initialization
    public init(pubkey: PublicKey)
    public convenience init?(npub: String)  // Creates user from npub
    
    // Profile Management
    public func fetchProfile() async throws -> NDKUserProfile?
    public func updateProfile(_ profile: NDKUserProfile)
    public func fetchRelayList() async throws -> [NDKRelayInfo]
    
    // Following/Followers
    public func follows() async throws -> Set<NDKUser>
    public func follows(_ user: NDKUser) async throws -> Bool
    
    // Payments
    public func pay(amount: Int64, comment: String? = nil, tags: [[String]]? = nil) async throws -> NDKPaymentConfirmation
    public func getPaymentMethods() async throws -> Set<NDKPaymentMethod>
    
    // Static Methods
    public static func fromNip05(_ nip05: String, ndk: NDK) async throws -> NDKUser?
}

// User profile metadata (kind 0)
public struct NDKUserProfile: Codable {
    public var name: String?
    public var displayName: String?
    public var about: String?
    public var picture: String?
    public var banner: String?
    public var nip05: String?
    public var lud16: String?
    public var lud06: String?
    public var website: String?
    
    public init(name: String? = nil, displayName: String? = nil, about: String? = nil, picture: String? = nil, banner: String? = nil, nip05: String? = nil, lud16: String? = nil, lud06: String? = nil, website: String? = nil)
    
    // Additional fields support
    public func additionalField(_ key: String) -> String?
    public mutating func setAdditionalField(_ key: String, value: String?)
}
```

### NDKRelay
Represents a Nostr relay with connection state and capabilities.

```swift
public class NDKRelay: ObservableObject {
    // Properties
    public let url: String
    @Published public private(set) var connectionState: ConnectionState
    public var activeSubscriptions: Int { get }
    
    // Connection State
    public enum ConnectionState {
        case disconnected
        case connecting
        case connected
        case disconnecting
        case failed(Error)
    }
    
    // Methods
    public func connect() async throws
    public func disconnect() async
    public func send(_ message: NostrMessage) async throws
}
```

## Signers

### NDKSigner Protocol
Base protocol for all signer implementations.

```swift
public protocol NDKSigner: Sendable {
    // Properties
    var publicKey: String { get }
    
    // Methods
    func sign(_ event: inout NDKEvent) async throws
    func encrypt(_ plaintext: String, to recipientPubkey: String) async throws -> String
    func decrypt(_ ciphertext: String, from senderPubkey: String) async throws -> String
}
```

### NDKPrivateKeySigner
Basic signer implementation using a private key.

```swift
public actor NDKPrivateKeySigner: NDKSigner {
    // Initialization
    public init(privateKey: String) throws
    public init(nsec: String) throws
    
    // Static Methods
    public static func generate() -> NDKPrivateKeySigner
}
```

## Relay Management

### NDKRelayPool
Manages multiple relay connections with automatic reconnection.

```swift
public actor NDKRelayPool {
    // Properties
    public var relays: [NDKRelay] { get }
    public var connectedRelays: [NDKRelay] { get }
    
    // Methods
    public func addRelay(url: String) async throws
    public func removeRelay(url: String) async
    public func connectAll() async
    public func disconnectAll() async
    public func publish(_ event: NDKEvent) async throws
}
```

## Subscriptions

## Subscription Management

### NDKSubscriptionManager
Advanced subscription management with intelligent grouping, merging, and coordination.

```swift
public actor NDKSubscriptionManager {
    // Subscription States
    public enum SubscriptionState {
        case pending
        case grouping
        case executing
        case active
        case closed
    }
    
    // Cache Usage Strategies
    public enum CacheUsage {
        case onlyCache      // Cache only, no relays
        case cacheFirst     // Cache then relays if needed
        case parallel       // Cache + relays simultaneously
        case onlyRelay      // Skip cache entirely
    }
    
    // Statistics
    public struct SubscriptionStats {
        public var totalSubscriptions: Int
        public var activeSubscriptions: Int
        public var groupedSubscriptions: Int
        public var requestsSaved: Int
        public var eventsDeduped: Int
        public var averageGroupSize: Double
    }
    
    // Initialization
    public init(ndk: NDK)
    
    // Subscription Management
    public func addSubscription(_ subscription: NDKSubscription)
    public func removeSubscription(_ subscriptionId: String)
    
    // Event Processing
    public func processEvent(_ event: NDKEvent, from relay: NDKRelay)
    public func processEOSE(subscriptionId: String, from relay: NDKRelay)
    
    // Statistics
    public func getStats() -> SubscriptionStats
}
```

**Key Features:**
- **Intelligent Grouping**: Similar subscriptions are automatically grouped to reduce relay load
- **Filter Merging**: Compatible filters are merged for efficient querying
- **Event Deduplication**: Prevents duplicate events across subscriptions using timestamp tracking
- **EOSE Handling**: Smart End-of-Stored-Events handling with dynamic timeouts
- **Cache Integration**: Multiple cache strategies for optimal performance
- **Performance Metrics**: Comprehensive statistics for monitoring and optimization

## Subscription Tracking

### NDKSubscriptionTracker
Comprehensive subscription tracking system for monitoring and debugging subscription behavior across relays.

```swift
public actor NDKSubscriptionTracker {
    // Initialization
    public init(
        trackClosedSubscriptions: Bool = false,
        maxClosedSubscriptions: Int = 100
    )
    
    // Subscription Lifecycle Tracking
    public func trackSubscription(
        _ subscription: NDKSubscription,
        filter: NDKFilter,
        relayUrls: [String]
    )
    
    public func trackSubscriptionSentToRelay(
        subscriptionId: String,
        relayUrl: String,
        appliedFilter: NDKFilter
    )
    
    public func trackEventReceived(
        subscriptionId: String,
        eventId: String,
        relayUrl: String,
        isUnique: Bool
    )
    
    public func trackEoseReceived(
        subscriptionId: String,
        relayUrl: String
    )
    
    public func closeSubscription(_ subscriptionId: String)
    
    // Query Methods
    public func activeSubscriptionCount() -> Int
    public func totalUniqueEventsReceived() -> Int
    public func getSubscriptionDetail(_ subscriptionId: String) -> NDKSubscriptionDetail?
    public func getAllActiveSubscriptions() -> [NDKSubscriptionDetail]
    public func getSubscriptionMetrics(_ subscriptionId: String) -> NDKSubscriptionMetrics?
    public func getRelayMetrics(
        subscriptionId: String,
        relayUrl: String
    ) -> NDKRelaySubscriptionMetrics?
    public func getAllRelayMetrics(
        subscriptionId: String
    ) -> [String: NDKRelaySubscriptionMetrics]?
    public func getClosedSubscriptions() -> [NDKClosedSubscription]
    public func getStatistics() -> NDKSubscriptionStatistics
    
    // Utility Methods
    public func clearClosedSubscriptionHistory()
    public func exportTrackingData() -> [String: Any]
}
```

### NDK.SubscriptionTrackingConfig
Configuration for subscription tracking behavior.

```swift
public struct SubscriptionTrackingConfig {
    public var trackClosedSubscriptions: Bool
    public var maxClosedSubscriptions: Int
    
    public init(
        trackClosedSubscriptions: Bool = false,
        maxClosedSubscriptions: Int = 100
    )
    
    public static let `default` = SubscriptionTrackingConfig()
}
```

### NDKSubscriptionMetrics
Overall metrics for a subscription across all relays.

```swift
public struct NDKSubscriptionMetrics {
    public let subscriptionId: String
    public var totalUniqueEvents: Int
    public var totalEvents: Int
    public var activeRelayCount: Int
    public let startTime: Date
    public var endTime: Date?
    public var duration: TimeInterval? { get }
    public var isActive: Bool { get }
}
```

### NDKRelaySubscriptionMetrics
Tracks subscription details at the relay level.

```swift
public struct NDKRelaySubscriptionMetrics {
    public let relayUrl: String
    public let appliedFilter: NDKFilter
    public var eventsReceived: Int
    public var eoseReceived: Bool
    public let subscriptionTime: Date
    public var eoseTime: Date?
    public var timeToEose: TimeInterval? { get }
}
```

### NDKSubscriptionDetail
Complete details for a subscription including relay-level metrics.

```swift
public struct NDKSubscriptionDetail {
    public let subscriptionId: String
    public let originalFilter: NDKFilter
    public var metrics: NDKSubscriptionMetrics
    public var relayMetrics: [String: NDKRelaySubscriptionMetrics]
    public var relayUrls: [String] { get }
}
```

### NDKClosedSubscription
Represents a completed subscription for historical tracking.

```swift
public struct NDKClosedSubscription {
    public let subscriptionId: String
    public let filter: NDKFilter
    public let relays: [String]
    public let uniqueEventCount: Int
    public let totalEventCount: Int
    public let duration: TimeInterval
    public let startTime: Date
    public let endTime: Date
    public var eventsPerSecond: Double { get }
}
```

### NDKSubscriptionStatistics
Overall statistics for all subscriptions in the NDK instance.

```swift
public struct NDKSubscriptionStatistics {
    public var activeSubscriptions: Int
    public var totalSubscriptions: Int
    public var totalUniqueEvents: Int
    public var totalEvents: Int
    public var closedSubscriptionsTracked: Int
    public var averageEventsPerSubscription: Double { get }
}
```

**Key Features:**
- **Real-time Metrics**: Track active subscriptions, event counts, and relay performance
- **Relay-level Detail**: See exactly which filters were sent to each relay and their event counts
- **Historical Tracking**: Optional closed subscription history for debugging
- **Performance Analysis**: Compare relay performance and identify bottlenecks
- **Export Capability**: Export all tracking data for external analysis
- **Thread-safe**: Actor-based implementation ensures safe concurrent access

**Usage Example:**
```swift
// Enable tracking
let ndk = NDK(
    subscriptionTrackingConfig: NDK.SubscriptionTrackingConfig(
        trackClosedSubscriptions: true,
        maxClosedSubscriptions: 100
    )
)

// Access metrics
let count = await ndk.subscriptionTracker.activeSubscriptionCount()
let detail = await ndk.subscriptionTracker.getSubscriptionDetail(subscription.id)
let stats = await ndk.subscriptionTracker.getStatistics()
```

### NDKSubscription
Manages event subscriptions with filtering, streaming, and advanced options.

```swift
public final class NDKSubscription {
    // Properties
    public let id: String
    public let filters: [NDKFilter]
    public let options: NDKSubscriptionOptions
    public weak var ndk: NDK?
    
    // State
    public var events: [NDKEvent] { get }
    public var isActive: Bool { get }
    public var isClosed: Bool { get }
    
    // Initialization
    public init(
        filters: [NDKFilter],
        options: NDKSubscriptionOptions = NDKSubscriptionOptions(),
        ndk: NDK? = nil
    )
    
    // Callbacks
    public func onEvent(_ callback: @escaping (NDKEvent) -> Void)
    public func onEOSE(_ callback: @escaping () -> Void)
    public func onEOSE(fromRelay relay: NDKRelay, _ callback: @escaping () -> Void)
    public func onClosed(_ callback: @escaping () -> Void)
    public func onError(_ callback: @escaping (Error) -> Void)
    
    // Async Operations
    public func waitForEOSE() async
    
    // Control
    public func start()
    public func close()
    
    // Internal Event Handling
    internal func handleEvent(_ event: NDKEvent, fromRelay relay: NDKRelay?)
    internal func handleEOSE(fromRelay relay: NDKRelay? = nil)
    internal func handleError(_ error: Error)
}

// Subscription configuration options
public struct NDKSubscriptionOptions {
    public var closeOnEose: Bool
    public var cacheStrategy: NDKCacheStrategy
    public var relays: Set<NDKRelay>?
    public var limit: Int?
    
    public init(
        closeOnEose: Bool = false,
        cacheStrategy: NDKCacheStrategy = .cacheFirst,
        relays: Set<NDKRelay>? = nil,
        limit: Int? = nil
    )
}

// Cache strategies for subscriptions
public enum NDKCacheStrategy {
    case cacheOnly      // Only query cache
    case cacheFirst     // Cache first, then relays
    case parallel       // Query cache and relays simultaneously
    case relayOnly      // Skip cache, only query relays
}
```

## Caching

### NDKCacheAdapter Protocol
Base protocol for cache implementations.

```swift
public protocol NDKCacheAdapter: Sendable {
    // Event Operations
    func saveEvent(_ event: NDKEvent) async throws
    func getEvent(id: String) async throws -> NDKEvent?
    func query(subscription: NDKSubscription) async throws -> [NDKEvent]
    
    // Profile Operations
    func saveProfile(_ profile: NDKUser.UserProfile, for pubkey: String) async throws
    func getProfile(for pubkey: String) async throws -> NDKUser.UserProfile?
    
    // Management
    func clear() async throws
}
```

### NDKInMemoryCache
Fast in-memory cache implementation.

```swift
public actor NDKInMemoryCache: NDKCacheAdapter {
    public init()
}
```

### NDKFileCache
Persistent file-based cache implementation.

```swift
public actor NDKFileCache: NDKCacheAdapter {
    // Initialization
    public init(path: String) throws
    
    // Additional Methods
    public func getCacheSize() async -> Int
    public func pruneOldEvents(olderThan: TimeInterval) async throws
}
```

## Utilities

### Bech32
Utilities for encoding/decoding Nostr identifiers according to NIP-19.

```swift
public enum Bech32 {
    // Error Types
    public enum Bech32Error: Error, LocalizedError {
        case invalidCharacter(Character)
        case invalidChecksum
        case invalidLength
        case invalidHRP
        case invalidData
        case invalidPadding
    }
    
    // Core Encoding/Decoding
    public static func encode(hrp: String, data: [UInt8]) throws -> String
    public static func decode(_ bech32: String) throws -> (hrp: String, data: [UInt8])
    
    // Nostr-specific Encoding
    public static func npub(from pubkey: PublicKey) throws -> String
    public static func nsec(from privateKey: PrivateKey) throws -> String
    public static func note(from eventId: EventID) throws -> String
    
    // Advanced Event Encoding
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
    
    // Nostr-specific Decoding
    public static func pubkey(from npub: String) throws -> PublicKey
    public static func privateKey(from nsec: String) throws -> PrivateKey
    public static func eventId(from note: String) throws -> EventID
}
```

**NIP-19 Support:**
- `npub`: Public keys (user identifiers)
- `nsec`: Private keys (for secure storage)
- `note`: Event identifiers
- `nevent`: Events with metadata (relays, author, kind)
- `naddr`: Addressable events (parameterized replaceable events)

**Usage Examples:**
```swift
// Encode public key to npub
let npub = try Bech32.npub(from: "fa984bd7dbb282f07e16e7ae87b26a2a7b9b90b7246a44771f0cf5ae58018f52")
// Result: "npub1l2vyh47mk2p0qlsku7hg0vn29faehy9hy34ygaclpn66ukqp3afqutajft"

// Decode npub back to public key
let pubkey = try Bech32.pubkey(from: npub)
// Result: "fa984bd7dbb282f07e16e7ae87b26a2a7b9b90b7246a44771f0cf5ae58018f52"

// Create user from npub
let user = NDKUser(npub: "npub1l2vyh47mk2p0qlsku7hg0vn29faehy9hy34ygaclpn66ukqp3afqutajft")
print(user?.npub) // Automatically encoded
```

### Crypto
Cryptographic utilities for Nostr operations.

```swift
public enum Crypto {
    // Key Generation
    public static func generatePrivateKey() -> String
    public static func getPublicKey(from privateKey: String) throws -> String
    
    // Signing
    public static func sign(message: String, with privateKey: String) throws -> String
    public static func verify(signature: String, message: String, publicKey: String) -> Bool
    
    // Encryption (NIP-04)
    public static func encrypt(
        _ plaintext: String,
        to recipientPubkey: String,
        with privateKey: String
    ) throws -> String
    
    public static func decrypt(
        _ ciphertext: String,
        from senderPubkey: String,
        with privateKey: String
    ) throws -> String
}
```

## Wallet System

### NDKWallet Protocol
Base protocol for wallet implementations.

```swift
public protocol NDKWallet: Sendable {
    // Properties
    var lud16: String? { get }
    var balance: Int? { get async throws }
    
    // Payment Operations
    func createZapRequest(
        amount: Int,
        comment: String?,
        recipientPubkey: String,
        eventId: String?,
        relays: [String]
    ) async throws -> String
    
    func payInvoice(_ bolt11: String) async throws -> PaymentResult
    
    // Types
    struct PaymentResult {
        public let preimage: String?
        public let feePaid: Int?
        public let error: String?
    }
}
```

### NDKCashuWallet
Cashu-based wallet implementation.

```swift
public actor NDKCashuWallet: NDKWallet {
    // Initialization
    public init(mintUrl: String, proofs: [CashuProof])
    
    // Additional Methods
    public func getMintInfo() async throws -> MintInfo
    public func refreshProofs() async throws
}
```

### NDKPaymentRouter
Routes payments through available wallets.

```swift
public actor NDKPaymentRouter {
    // Properties
    public var wallets: [NDKWallet] { get }
    
    // Methods
    public func addWallet(_ wallet: NDKWallet)
    public func removeWallet(_ wallet: NDKWallet)
    public func routePayment(
        amount: Int,
        to recipient: NDKUser,
        comment: String?
    ) async throws -> NDKWallet.PaymentResult
}
```

## Event Kinds

### NDKImage
Specialized handling for image events (NIP-58).

```swift
public struct NDKImage: Codable {
    // Properties
    public let url: String
    public let blurhash: String?
    public let sha256: String?
    public let dimension: Dimension?
    public let alt: String?
    
    // Types
    public struct Dimension: Codable {
        public let width: Int
        public let height: Int
    }
    
    // Methods
    public static func parseFromContent(_ content: String) -> NDKImage?
    public static func parseFromImeta(_ imetaTags: [[String]]) -> [NDKImage]
}
```

### NDKCashuMintList
Represents a user's Cashu mint list (NIP-60).

```swift
public struct NDKCashuMintList: Codable {
    // Properties
    public let mints: [CashuMint]
    
    // Types
    public struct CashuMint: Codable {
        public let url: String
        public let proofs: [CashuProof]
    }
    
    // Methods
    public static func fromEvent(_ event: NDKEvent) throws -> NDKCashuMintList
    public func toEvent(signer: NDKSigner) async throws -> NDKEvent
}
```

## Constants and Types

### EventKind
Common Nostr event kinds.

```swift
public typealias EventKind = Int

extension EventKind {
    public static let metadata = 0
    public static let textNote = 1
    public static let recommendRelay = 2
    public static let contacts = 3
    public static let encryptedDirectMessage = 4
    public static let deletion = 5
    public static let repost = 6
    public static let reaction = 7
    public static let badgeAward = 8
    public static let channelCreation = 40
    public static let channelMetadata = 41
    public static let channelMessage = 42
    public static let channelHideMessage = 43
    public static let channelMuteUser = 44
    public static let fileMetadata = 1063
    public static let zapRequest = 9734
    public static let zap = 9735
    public static let relayList = 10002
    public static let muteList = 10000
    public static let pinList = 10001
    public static let bookmarkList = 10003
    public static let communitiesList = 10004
    public static let publicChatsList = 10005
    public static let blockedRelaysList = 10006
    public static let searchRelaysList = 10007
    public static let walletInfo = 13194
    public static let nutzap = 9321
    public static let cashuMintList = 37375
}
```

### Timestamp
Type alias for Unix timestamps.

```swift
public typealias Timestamp = Int64

extension Timestamp {
    public static func now() -> Timestamp {
        return Timestamp(Date().timeIntervalSince1970)
    }
    
    public var date: Date {
        return Date(timeIntervalSince1970: TimeInterval(self))
    }
}
```

## Blossom Support

### BlossomClient
Client for interacting with Blossom servers for decentralized file storage.

```swift
public actor BlossomClient {
    // Initialization
    public init(urlSession: URLSession = .shared)
    
    // Server Discovery (BUD-01)
    public func discoverServer(_ serverURL: String) async throws -> BlossomServerDescriptor
    
    // Upload (BUD-02)
    public func upload(
        data: Data,
        mimeType: String? = nil,
        to serverURL: String,
        auth: BlossomAuth
    ) async throws -> BlossomBlob
    
    // List (BUD-03)
    public func list(
        from serverURL: String,
        auth: BlossomAuth,
        since: Date? = nil,
        until: Date? = nil
    ) async throws -> [BlossomBlob]
    
    // Delete (BUD-04)
    public func delete(
        sha256: String,
        from serverURL: String,
        auth: BlossomAuth
    ) async throws
    
    // Download
    public func download(
        sha256: String,
        from serverURL: String
    ) async throws -> Data
    
    // Convenience methods with automatic auth
    public func uploadWithAuth(
        data: Data,
        mimeType: String? = nil,
        to serverURL: String,
        signer: NDKSigner,
        expiration: Date? = nil
    ) async throws -> BlossomBlob
}
```

### BlossomBlob
Represents a file stored on a Blossom server.

```swift
public struct BlossomBlob: Codable, Sendable {
    public let sha256: String
    public let url: String
    public let size: Int64
    public let type: String?
    public let uploaded: Date
}
```

### BlossomAuth
Authorization for Blossom operations.

```swift
public struct BlossomAuth {
    // Create authorization events
    public static func createUploadAuth(
        sha256: String,
        size: Int64,
        mimeType: String? = nil,
        signer: NDKSigner,
        expiration: Date? = nil
    ) async throws -> BlossomAuth
    
    public static func createDeleteAuth(
        sha256: String,
        signer: NDKSigner,
        reason: String? = nil
    ) async throws -> BlossomAuth
    
    public static func createListAuth(
        signer: NDKSigner,
        since: Date? = nil,
        until: Date? = nil
    ) async throws -> BlossomAuth
}
```

### NDK Blossom Extensions

```swift
extension NDK {
    // Get Blossom client
    public var blossomClient: BlossomClient { get }
    
    // Upload to multiple Blossom servers
    public func uploadToBlossom(
        data: Data,
        mimeType: String? = nil,
        servers: [String]? = nil,
        expiration: Date? = nil
    ) async throws -> [BlossomBlob]
}

extension NDKEvent {
    // Create file metadata event (NIP-94)
    public static func createFileMetadata(
        blobs: [BlossomBlob],
        description: String? = nil,
        signer: NDKSigner
    ) async throws -> NDKEvent
    
    // Create image event with Blossom upload
    public static func createImageEvent(
        imageData: Data,
        mimeType: String,
        caption: String? = nil,
        ndk: NDK
    ) async throws -> NDKEvent
    
    // Extract Blossom URLs from file metadata
    public func extractBlossomURLs() -> [(url: String, sha256: String)]
}
```

## Error Types

### NDKError
Common errors thrown by NDKSwift.

```swift
public enum NDKError: LocalizedError {
    case invalidPrivateKey
    case invalidPublicKey
    case invalidBech32
    case signingFailed
    case encryptionFailed
    case decryptionFailed
    case relayConnectionFailed(String)
    case publishFailed(String)
    case cacheError(String)
    case invalidEvent(String)
    case walletError(String)
    
    public var errorDescription: String? { get }
}
```

### BlossomError
Errors specific to Blossom operations.

```swift
public enum BlossomError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case serverError(Int, String?)
    case fileTooLarge
    case unsupportedMimeType
    case blobNotFound
    case uploadFailed(String)
    case networkError(Error)
    case invalidSHA256
    
    public var errorDescription: String? { get }
}
```