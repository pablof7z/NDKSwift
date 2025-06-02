# NDKSwift API Reference

## Table of Contents
- [Core Classes](#core-classes)
- [Models](#models)
- [Signers](#signers)
- [Relay Management](#relay-management)
- [Subscriptions](#subscriptions)
- [Caching](#caching)
- [Utilities](#utilities)
- [Wallet System](#wallet-system)
- [Blossom Support](#blossom-support)

## Core Classes

### NDK
The main entry point for all NDKSwift functionality.

```swift
public class NDK {
    // Properties
    public var signer: NDKSigner?
    public var cacheAdapter: NDKCacheAdapter?
    public private(set) var relayPool: NDKRelayPool
    
    // Initialization
    public init(
        relayUrls: [String] = [],
        signer: NDKSigner? = nil,
        cacheAdapter: NDKCacheAdapter? = nil
    )
    
    // Connection Management
    public func connect() async throws
    public func disconnect() async
    
    // Subscription
    public func subscribe(
        filters: [NDKFilter],
        closeOnEOSE: Bool = false
    ) -> NDKSubscription
    
    // Publishing
    public func publish(_ event: NDKEvent) async throws
    
    // User Management
    public func getUser(npub: String) -> NDKUser
    public func getUser(pubkey: String) -> NDKUser
}
```

## Models

### NDKEvent
Represents a Nostr event with all required fields and validation.

```swift
public struct NDKEvent: Codable, Identifiable, Sendable {
    // Properties
    public let id: String
    public let pubkey: String
    public let createdAt: Timestamp
    public let kind: EventKind
    public var tags: [[String]]
    public let content: String
    public let sig: String?
    
    // Initialization
    public init(
        pubkey: String,
        createdAt: Timestamp,
        kind: EventKind,
        tags: [[String]] = [],
        content: String
    )
    
    // Methods
    public mutating func sign(with signer: NDKSigner) async throws
    public func verify() -> Bool
    public func serialize() throws -> String
    
    // Tag Helpers
    public func tagValue(for tagName: String) -> String?
    public func tagValues(for tagName: String) -> [String]
    public mutating func addTag(_ tag: [String])
    public mutating func removeTag(name: String, value: String? = nil)
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
Represents a Nostr user with profile information.

```swift
public class NDKUser: ObservableObject {
    // Properties
    @Published public var profile: UserProfile?
    public let pubkey: String
    public var npub: String { get }
    
    // Initialization
    public init(pubkey: String)
    public init(npub: String) throws
    
    // Profile Management
    public func fetchProfile() async throws
    public func updateProfile(_ profile: UserProfile) async throws
    
    // Nested Types
    public struct UserProfile: Codable {
        public var name: String?
        public var displayName: String?
        public var about: String?
        public var picture: String?
        public var banner: String?
        public var nip05: String?
        public var lud06: String?
        public var lud16: String?
    }
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

### NDKSubscription
Manages event subscriptions with filtering and streaming.

```swift
public class NDKSubscription: ObservableObject {
    // Properties
    public let id: String
    public let filters: [NDKFilter]
    @Published public var events: [NDKEvent] = []
    public var isActive: Bool { get }
    
    // Callbacks
    public func onEvent(_ callback: @escaping (NDKEvent) -> Void)
    public func onEOSE(_ callback: @escaping () -> Void)
    public func onClosed(_ callback: @escaping () -> Void)
    
    // Async Streaming
    public func eventStream() -> AsyncStream<NDKEvent>
    
    // Control
    public func start() async
    public func close() async
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
Utilities for encoding/decoding Nostr identifiers.

```swift
public enum Bech32 {
    // Encoding
    public static func npub(from pubkey: String) throws -> String
    public static func nsec(from privateKey: String) throws -> String
    public static func note(from eventId: String) throws -> String
    public static func nevent(from event: NDKEvent) throws -> String
    public static func nprofile(from user: NDKUser) throws -> String
    
    // Decoding
    public static func pubkey(from npub: String) throws -> String
    public static func privateKey(from nsec: String) throws -> String
    public static func eventId(from note: String) throws -> String
    public static func decode(_ bech32String: String) throws -> (hrp: String, data: Data)
}
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