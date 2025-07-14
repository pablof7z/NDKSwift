# NDKSwift Examples

Practical code examples for common Nostr use cases with NDKSwift.

## Table of Contents

- [Basic Operations](#basic-operations)
- [Social Features](#social-features)
- [Messaging](#messaging)
- [Content Management](#content-management)
- [Wallet Integration](#wallet-integration)
- [File Storage](#file-storage)
- [Advanced Patterns](#advanced-patterns)

## Basic Operations

### Creating a Nostr Client

```swift
import NDKSwift

class NostrClient {
    let ndk: NDK
    
    init() {
        // Initialize with popular relays
        ndk = NDK(relayUrls: [
            "wss://relay.damus.io",
            "wss://relay.primal.net",
            "wss://relay.nostr.band",
            "wss://relay.snort.social"
        ])
        
        // Optional: Enable caching
        if let cache = try? NDKSQLiteCache() {
            ndk.cache = cache
        }
    }
    
    func connect() async {
        await ndk.connect()
        print("Connected to \(ndk.pool.connectedRelays().count) relays")
    }
}
```

### User Authentication

```swift
// Generate new identity
func createNewIdentity() throws -> NDKPrivateKeySigner {
    let signer = try NDKPrivateKeySigner.generate()
    print("Public key: \(signer.publicKey)")
    print("Private key (save securely!): \(signer.nsec)")
    return signer
}

// Login with existing key
func login(with nsec: String) throws {
    let signer = try NDKPrivateKeySigner(nsec: nsec)
    ndk.signer = signer
    
    // Get user info
    let user = try await signer.user()
    print("Logged in as: \(user.npub)")
}
```

## Social Features

### Following Users

```swift
func followUser(_ userPubkey: String) async throws {
    // Get current follow list
    guard let currentUser = ndk.activeUser else { return }
    let following = try await currentUser.follows()
    
    // Add new user
    var tags: [Tag] = following.map { ["p", $0.pubkey] }
    tags.append(["p", userPubkey])
    
    // Publish updated contact list
    let contactList = NDKEvent(
        kind: EventKind.contactList,
        tags: tags,
        content: ""
    )
    
    try await ndk.publish(contactList)
}
```

### Timeline Feed

```swift
func createTimelineFeed() async throws {
    guard let currentUser = ndk.activeUser else { return }
    
    // Get users we follow
    let following = try await currentUser.follows()
    let pubkeys = following.map { $0.pubkey }
    
    // Subscribe to their posts
    let subscription = ndk.subscribe(filters: [
        NDKFilter(
            authors: pubkeys,
            kinds: [1, 6], // Text notes and reposts
            limit: 50
        )
    ])
    
    // Display feed
    for await event in subscription {
        if event.kind == 1 {
            displayPost(event)
        } else if event.kind == 6 {
            displayRepost(event)
        }
    }
}

func displayPost(_ event: NDKEvent) {
    let author = ndk.getUser(event.pubkey)
    print("\(author?.displayName ?? "Unknown"): \(event.content)")
}
```

### User Profile Display

```swift
struct UserProfileView {
    let ndk: NDK
    
    func loadProfile(for pubkey: String) async throws -> UserProfile {
        let user = ndk.getUser(pubkey)
        let profile = try await user.fetchProfile()
        
        // Get additional stats
        let followers = try await getFollowerCount(pubkey)
        let following = try await user.follows().count
        
        return UserProfile(
            user: user,
            profile: profile,
            followerCount: followers,
            followingCount: following
        )
    }
    
    func getFollowerCount(_ pubkey: String) async throws -> Int {
        let events = try await ndk.fetchEvents(
            NDKFilter(
                kinds: [3],
                tags: ["p": Set([pubkey])]
            )
        )
        return events.count
    }
}
```

## Messaging

### Direct Messages (NIP-04)

```swift
func sendDirectMessage(to recipientPubkey: String, message: String) async throws {
    guard let signer = ndk.signer else { throw NDKError.signerRequired }
    
    // Encrypt message
    let recipient = ndk.getUser(recipientPubkey)
    let encrypted = try await signer.encrypt(
        recipient: recipient,
        value: message,
        scheme: .nip04
    )
    
    // Create DM event
    let dm = NDKEvent(
        kind: EventKind.encryptedDirectMessage,
        tags: [["p", recipientPubkey]],
        content: encrypted
    )
    
    try await ndk.publish(dm)
}

func receiveDirectMessages() async throws {
    guard let signer = ndk.signer else { return }
    let myPubkey = try await signer.pubkey
    
    let subscription = ndk.subscribe(filters: [
        NDKFilter(
            kinds: [4],
            tags: ["p": Set([myPubkey])]
        )
    ])
    
    for await event in subscription {
        let sender = ndk.getUser(event.pubkey)
        let decrypted = try await signer.decrypt(
            sender: sender,
            value: event.content,
            scheme: .nip04
        )
        print("DM from \(sender.displayName ?? "Unknown"): \(decrypted)")
    }
}
```

### Secure Chat (NIP-44)

```swift
class SecureChat {
    let ndk: NDK
    
    func sendSecureMessage(to recipient: String, message: String) async throws {
        guard let signer = ndk.signer else { throw NDKError.signerRequired }
        
        // Use NIP-44 encryption (more secure)
        let recipientUser = ndk.getUser(recipient)
        let encrypted = try await signer.encrypt(
            recipient: recipientUser,
            value: message,
            scheme: .nip44
        )
        
        // Wrap in gift wrap for metadata privacy
        let giftWrap = NDKEvent(
            kind: EventKind.giftWrap,
            tags: [["p", recipient]],
            content: encrypted
        )
        
        try await ndk.publish(giftWrap)
    }
}
```

## Content Management

### Long-form Articles (NIP-23)

```swift
func publishArticle(title: String, content: String, summary: String) async throws {
    let tags: [Tag] = [
        ["title", title],
        ["summary", summary],
        ["published_at", "\(Int(Date().timeIntervalSince1970))"],
        ["t", "blog"],
        ["t", "article"]
    ]
    
    let article = NDKEvent(
        kind: EventKind.article,
        tags: tags,
        content: content // Markdown supported
    )
    
    try await ndk.publish(article)
}

func fetchArticles(by author: String) async throws -> [Article] {
    let events = try await ndk.fetchEvents(
        NDKFilter(
            authors: [author],
            kinds: [EventKind.article]
        )
    )
    
    return events.compactMap { event in
        guard let title = event.tagValue("title") else { return nil }
        return Article(
            id: event.id ?? "",
            title: title,
            content: event.content,
            summary: event.tagValue("summary") ?? "",
            publishedAt: event.createdAt
        )
    }
}
```

### Reactions and Comments

```swift
// Add reaction
func reactToPost(_ event: NDKEvent, with emoji: String = "👍") async throws {
    let reaction = try await event.react(content: emoji, publish: true)
    print("Reacted with \(emoji)")
}

// Post comment/reply
func replyToPost(_ event: NDKEvent, comment: String) async throws {
    let reply = event.createReply(content: comment, mentionAuthor: true)
    try await ndk.publish(reply)
}

// Get reactions for a post
func getReactions(for eventId: String) async throws -> [String: Int] {
    let reactions = try await ndk.fetchEvents(
        NDKFilter(
            kinds: [7],
            tags: ["e": Set([eventId])]
        )
    )
    
    // Count by emoji
    var counts: [String: Int] = [:]
    for reaction in reactions {
        let emoji = reaction.content.isEmpty ? "👍" : reaction.content
        counts[emoji, default: 0] += 1
    }
    return counts
}
```

## Wallet Integration

### Lightning Payments with NWC

```swift
class WalletManager {
    let ndk: NDK
    var wallet: NDKNWCWallet?
    
    func connectWallet(connectionURI: String) async throws {
        wallet = try NDKNWCWallet(connectionURI: connectionURI)
        await wallet?.connect()
        
        // Check wallet info
        if let info = try await wallet?.getInfo() {
            print("Connected to: \(info.alias)")
            print("Methods: \(info.methods)")
        }
    }
    
    func checkBalance() async throws -> Int64 {
        guard let wallet = wallet else { throw WalletError.notConnected }
        let balance = try await wallet.getBalance()
        return balance.balance
    }
    
    func sendPayment(invoice: String, amount: Int64) async throws {
        guard let wallet = wallet else { throw WalletError.notConnected }
        
        let request = PayInvoiceRequest(invoice: invoice)
        let response = try await wallet.payInvoice(params: request)
        
        print("Payment sent! Preimage: \(response.preimage)")
    }
}
```

### Zaps (Lightning Tips)

```swift
func sendZap(to user: NDKUser, amount: Int64, comment: String? = nil) async throws {
    // User's wallet will handle the payment
    let payment = try await user.pay(
        amount: amount,
        comment: comment,
        tags: [["emoji", "⚡"]]
    )
    
    print("Zapped \(amount) sats! Invoice: \(payment.invoice)")
}

// Monitor incoming zaps
func monitorZaps(for eventId: String) async {
    let subscription = ndk.subscribe(filters: [
        NDKFilter(
            kinds: [EventKind.zap],
            tags: ["e": Set([eventId])]
        )
    ])
    
    for await zap in subscription {
        if let amount = extractZapAmount(from: zap) {
            print("⚡ Received \(amount) sats!")
        }
    }
}
```

## File Storage

### Blossom Integration

```swift
class FileStorage {
    let blossomClient = BlossomClient()
    let ndk: NDK
    
    func uploadImage(_ imageData: Data) async throws -> String {
        // Create auth event
        let authEvent = NDKEvent(
            kind: EventKind.blossomUpload,
            tags: [
                ["t", "upload"],
                ["expiration", "\(Int(Date().timeIntervalSince1970) + 3600)"]
            ],
            content: "Upload authorization"
        )
        
        try await authEvent.sign()
        
        let auth = BlossomAuth(event: authEvent)
        
        // Upload to multiple servers for redundancy
        let servers = [
            "https://blossom.primal.net",
            "https://blossom.nos.social"
        ]
        
        var uploadedUrls: [String] = []
        
        for server in servers {
            do {
                let blob = try await blossomClient.upload(
                    data: imageData,
                    mimeType: "image/jpeg",
                    to: server,
                    auth: auth
                )
                uploadedUrls.append("\(server)/\(blob.sha256)")
            } catch {
                print("Failed to upload to \(server): \(error)")
            }
        }
        
        return uploadedUrls.first ?? ""
    }
    
    func shareImage(url: String, caption: String) async throws {
        let imagePost = NDKEvent(
            kind: 1,
            tags: [
                ["imeta", "url \(url)", "m image/jpeg"]
            ],
            content: "\(caption)\n\n\(url)"
        )
        
        try await ndk.publish(imagePost)
    }
}
```

## Advanced Patterns

### Relay Management

```swift
class RelayManager {
    let ndk: NDK
    
    func optimizeRelays(for user: NDKUser) async throws {
        // Get user's preferred relays
        let relayList = try await user.fetchRelayList()
        
        // Disconnect from current relays
        await ndk.disconnect()
        
        // Connect to user's relays
        for relayInfo in relayList {
            if relayInfo.read || relayInfo.write {
                ndk.addRelay(relayInfo.url)
            }
        }
        
        await ndk.connect()
    }
    
    func publishToSpecificRelays(event: NDKEvent, relayUrls: [String]) async throws {
        let relays = Set(relayUrls)
        let published = try await ndk.publish(event: event, to: relays)
        
        print("Published to \(published.count)/\(relays.count) relays")
        
        // Check which failed
        let failedUrls = relays.subtracting(published.map { $0.url })
        for url in failedUrls {
            print("Failed to publish to: \(url)")
        }
    }
}
```

### Subscription Grouping

```swift
class SubscriptionManager {
    let ndk: NDK
    var subscriptions: [String: NDKSubscription] = [:]
    
    func createGroupedSubscription(for interests: [String]) {
        // Create filters for different interests
        var filters: [NDKFilter] = []
        
        for interest in interests {
            var filter = NDKFilter(kinds: [1, 30023])
            filter.addTagFilter("t", values: [interest.lowercased()])
            filters.append(filter)
        }
        
        // Single subscription for all interests
        let subscription = ndk.subscribe(
            filters: filters,
            options: NDKSubscriptionOptions(
                closeOnEose: false,
                limit: 100
            )
        )
        
        subscriptions["interests"] = subscription
        
        Task {
            for await event in subscription {
                handleInterestEvent(event)
            }
        }
    }
    
    func cleanup() async {
        for (_, subscription) in subscriptions {
            await subscription.close()
        }
        subscriptions.removeAll()
    }
}
```

### Custom Event Kinds

```swift
// Define custom event kind for your app
extension EventKind {
    static let customAppData = 30078
}

struct AppSettings: Codable {
    var theme: String
    var notifications: Bool
    var language: String
}

func saveAppSettings(_ settings: AppSettings) async throws {
    let settingsData = try JSONEncoder().encode(settings)
    
    let event = NDKEvent(
        kind: EventKind.customAppData,
        tags: [
            ["d", "settings"], // 'd' tag makes it replaceable
            ["client", "MyNostrApp"]
        ],
        content: String(data: settingsData, encoding: .utf8) ?? ""
    )
    
    try await ndk.publish(event)
}

func loadAppSettings() async throws -> AppSettings? {
    guard let user = ndk.activeUser else { return nil }
    
    let events = try await ndk.fetchEvents(
        NDKFilter(
            authors: [user.pubkey],
            kinds: [EventKind.customAppData],
            tags: ["d": Set(["settings"])]
        )
    )
    
    guard let latest = events.first,
          let data = latest.content.data(using: .utf8) else {
        return nil
    }
    
    return try JSONDecoder().decode(AppSettings.self, from: data)
}
```

### Performance Optimization

```swift
class OptimizedClient {
    let ndk: NDK
    
    init() {
        // Configure for performance
        let config = NDKSignatureVerificationConfig(
            enabled: true,
            samplingRate: 0.1  // Verify 10% of signatures
        )
        
        ndk = NDK(
            relayUrls: ["wss://relay.damus.io"],
            signatureVerificationConfig: config
        )
        
        // Enable subscription tracking for deduplication
        ndk.subscriptionTracker.config.enabled = true
    }
    
    func batchFetch(eventIds: [String]) async throws -> [NDKEvent] {
        // Batch fetch events efficiently
        let batchSize = 50
        var allEvents: [NDKEvent] = []
        
        for chunk in eventIds.chunked(into: batchSize) {
            let events = try await ndk.fetchEvents(
                NDKFilter(ids: chunk)
            )
            allEvents.append(contentsOf: events)
        }
        
        return allEvents
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
```

## Cashu Wallet Integration (NIP-60/61)

```swift
class CashuWalletManager {
    let ndk: NDK
    var wallet: NDKCashuWallet?
    
    init(ndk: NDK) {
        self.ndk = ndk
    }
    
    func setupWallet(signer: NDKSigner) async throws {
        // Initialize Cashu wallet
        wallet = NDKCashuWallet(signer: signer, ndk: ndk)
        await wallet?.connect()
        
        // Configure mints
        let mints = [
            "https://mint.minibits.cash/Bitcoin",
            "https://mint.coinos.io"
        ]
        
        for mintUrl in mints {
            try await wallet?.addMint(url: mintUrl)
        }
    }
    
    func checkBalance() async -> Int {
        await wallet?.totalBalance ?? 0
    }
    
    func sendNutzap(
        to recipient: NDKUser,
        amount: Int,
        comment: String,
        eventId: String? = nil
    ) async throws {
        guard let wallet = wallet else { throw WalletError.notInitialized }
        
        // Send nutzap (NIP-61)
        let nutzap = try await wallet.nutzap(
            amount: amount,
            comment: comment,
            recipient: recipient,
            eventId: eventId
        )
        
        print("Sent nutzap: \(nutzap.id)")
    }
    
    func mintTokens(amount: Int) async throws {
        guard let wallet = wallet else { throw WalletError.notInitialized }
        
        // Get mint quote
        let quote = try await wallet.mintQuote(amount: amount)
        print("Pay this invoice: \(quote.request)")
        
        // After payment is confirmed...
        let tokens = try await wallet.mint(quote: quote)
        print("Minted \(tokens.count) tokens")
    }
    
    func receiveToken(_ tokenString: String) async throws {
        guard let wallet = wallet else { throw WalletError.notInitialized }
        
        // Receive Cashu token
        let received = try await wallet.receive(token: tokenString)
        print("Received \(received.amount) sats")
    }
}
```

## Running the Examples

Many of these examples are available as runnable demos in the [Examples directory](../Examples/):

```bash
# Simple demo
swift run --package-path Examples SimpleDemo

# NWC wallet demo
swift run --package-path Examples NWCDemo

# Blossom file storage
swift run --package-path Examples BlossomDemo
```

For more detailed API documentation, see the [API Reference](API_REFERENCE.md).