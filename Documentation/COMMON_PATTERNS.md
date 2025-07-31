# Common NDKSwift Usage Patterns

This guide provides practical examples and best practices for common tasks in NDKSwift applications.

## Table of Contents

1. [Connection Management](#connection-management)
2. [Event Publishing Patterns](#event-publishing-patterns)
3. [Subscription Patterns](#subscription-patterns)
4. [Encrypted Messaging](#encrypted-messaging)
5. [Zap Integration](#zap-integration)
6. [File Storage with Blossom](#file-storage-with-blossom)
7. [Relay Management](#relay-management)
8. [Error Handling](#error-handling)
9. [Performance Optimization](#performance-optimization)
10. [SwiftUI Integration](#swiftui-integration)

## Connection Management

### Auto-Reconnecting Setup

```swift
// Create NDK with auto-reconnecting relay pool
let ndk = NDK(
    relayUrls: [
        RelayConstants.damus,        // "wss://relay.damus.io"
        RelayConstants.primal,       // "wss://relay.primal.net"
        RelayConstants.nosLol        // "wss://nos.lol"
    ],
    cache: NDKSQLiteCache(dbName: "myapp.db")  // Persistent cache
)

// Monitor connection status
Task {
    for await status in ndk.connectionStatus {
        switch status {
        case .connected(let relayCount):
            print("Connected to \(relayCount) relays")
        case .connecting:
            print("Connecting...")
        case .disconnected:
            print("Disconnected")
        }
    }
}

// Connect with timeout
try await withTimeout(seconds: 10) {
    await ndk.connect()
}
```

### Handling Connection Failures

```swift
// Gracefully handle relay failures
do {
    await ndk.connect()
} catch {
    // Continue with available relays
    print("Some relays failed: \(error)")
    
    // Check which relays are connected
    let connectedRelays = await ndk.pool.connectedRelays()
    if connectedRelays.isEmpty {
        // Handle offline mode
        print("No relays available - using cache only")
    }
}
```

## Event Publishing Patterns

### Publishing with Confirmation

```swift
// Publish with confirmation from multiple relays
let event = try await ndk.publishEvent { builder in
    builder
        .content("Hello Nostr!")
        .kind(EventKind.textNote)
        .tag(["t", "nostr"])
}

// Wait for confirmation from at least 2 relays
let confirmations = try await event.waitForConfirmation(
    minRelays: 2,
    timeout: 5.0
)

print("Event confirmed by \(confirmations.count) relays")
```

### Batch Publishing

```swift
// Publish multiple events efficiently
let events = try await ndk.batchPublish { batch in
    // Create multiple events
    batch.add { builder in
        builder.content("First post").kind(EventKind.textNote)
    }
    
    batch.add { builder in
        builder.content("Second post").kind(EventKind.textNote)
    }
    
    batch.add { builder in
        builder.content("Third post").kind(EventKind.textNote)
    }
}

print("Published \(events.count) events")
```

### Reply Threading

```swift
// Create a properly threaded reply
func replyToEvent(_ originalEvent: NDKEvent, content: String) async throws -> NDKEvent {
    // Build reply with proper tags
    let reply = try await ndk.publishEvent { builder in
        builder
            .content(content)
            .kind(EventKind.textNote)
            .tagEvent(originalEvent)  // Adds 'e' tag
            .tagUser(originalEvent.pubkey)  // Adds 'p' tag
            .addMarker("reply")  // NIP-10 marker
        
        // Thread root detection
        if let rootTag = originalEvent.tags.first(where: { $0.isRootEvent }) {
            builder.tag(rootTag)  // Preserve root
        } else {
            builder.tagRootEvent(originalEvent)  // This is the root
        }
    }
    
    return reply
}
```

## Subscription Patterns

### Efficient Profile Loading

```swift
// Load multiple profiles efficiently
func loadProfiles(pubkeys: [String]) async -> [String: NDKUserProfile] {
    var profiles: [String: NDKUserProfile] = [:]
    
    // Create chunked requests for efficiency
    for chunk in pubkeys.chunked(into: 50) {
        let profileSource = ndk.subscribe(
            filter: NDKFilter(
                kinds: [EventKind.metadata],
                authors: chunk
            ),
            maxAge: 3600,  // 1 hour cache
            cachePolicy: .cacheWithNetwork
        )
        
        // Collect with timeout
        let events = await profileSource.collect(timeout: 5.0)
        
        for event in events {
            if let profile = try? event.decodeMetadata() {
                profiles[event.pubkey] = profile
            }
        }
    }
    
    return profiles
}
```

### Live Activity Feed

```swift
// Create a live-updating activity feed
class ActivityFeed: ObservableObject {
    @Published var activities: [NDKEvent] = []
    private var dataSource: NDKSubscription<NDKEvent>?
    
    func startWatching(for pubkey: String) {
        // Watch for mentions and reactions
        let filter = NDKFilter(kinds: [1, 7])
        filter.addTagFilter("p", values: [pubkey])
        
        dataSource = ndk.subscribe(
            filter: filter,
            maxAge: 0,  // Real-time only
            cachePolicy: .cacheWithNetwork
        )
        
        Task {
            guard let source = dataSource else { return }
            
            for await event in source.events {
                await MainActor.run {
                    // Insert at beginning for newest first
                    activities.insert(event, at: 0)
                    
                    // Limit feed size
                    if activities.count > 100 {
                        activities.removeLast()
                    }
                }
            }
        }
    }
    
    func stop() {
        dataSource?.cancel()
    }
}
```

### Paginated Loading

```swift
// Load events with pagination
func loadEventsPaginated(
    filter: NDKFilter,
    pageSize: Int = 20
) -> AsyncStream<[NDKEvent]> {
    AsyncStream { continuation in
        Task {
            var until: Timestamp?
            
            while true {
                var pageFilter = filter
                pageFilter.limit = pageSize
                if let until = until {
                    pageFilter.until = until
                }
                
                let source = ndk.subscribe(
                    filter: pageFilter,
                    maxAge: 300,  // 5 minute cache
                    cachePolicy: .cacheWithNetwork
                )
                
                let events = await source.collect(timeout: 5.0)
                
                if events.isEmpty {
                    continuation.finish()
                    break
                }
                
                continuation.yield(events)
                
                // Set until for next page
                until = events.map { $0.createdAt }.min()
            }
        }
    }
}
```

## Encrypted Messaging

### NIP-17 Private Messages

```swift
// Send an encrypted private message (NIP-17)
func sendPrivateMessage(to recipientPubkey: String, message: String) async throws {
    guard let signer = ndk.signer else { throw NDKError.notConfigured("No signer") }
    
    // Create the private message
    let privateMessage = try await NDKPrivateMessage.create(
        content: message,
        recipientPubkey: recipientPubkey,
        signer: signer,
        ndk: ndk
    )
    
    // Publish the gift-wrapped message
    let publishedRelays = try await ndk.publish(privateMessage.giftWrap)
    print("Private message sent to \(publishedRelays.count) relays")
}

// Receive private messages
func watchPrivateMessages() {
    guard let signer = ndk.signer else { return }
    
    Task {
        let myPubkey = try await signer.pubkey
        
        // Watch for gift wraps addressed to me
        // Note: This is a placeholder - implement based on your app's needs
        let giftWrapFilter = NDKFilter(kinds: [1059], tags: ["p": Set([myPubkey])])
        let messageSource = ndk.subscribe(filter: giftWrapFilter)
        
        for await event in messageSource.events {
            // Decrypt and process the gift wrap event
            // Implementation depends on your encryption approach
            print("Received gift wrap at: \(event.createdAt.date)")
        }
    }
}
```

### Legacy NIP-04 DMs

```swift
// Send NIP-04 encrypted DM (legacy, use NIP-17 for new apps)
func sendLegacyDM(to recipientPubkey: String, message: String) async throws {
    guard let signer = ndk.signer else { throw NDKError.notConfigured("No signer") }
    
    let encryptedContent = try await signer.encrypt(
        message,
        recipientPubkey: recipientPubkey,
        algorithm: .nip04
    )
    
    let dmEvent = try await ndk.publishEvent { builder in
        builder
            .content(encryptedContent)
            .kind(EventKind.encryptedDirectMessage)
            .tagUser(recipientPubkey)
    }
}
```

## Zap Integration

### Sending Zaps

```swift
// Send a zap using the modern zap manager API
func sendZap(to event: NDKEvent, amount: Int64, comment: String? = nil) async throws {
    // The zap manager handles all the complexity internally
    let result = try await event.zap(
        with: ndk,
        amountSats: amount,
        comment: comment
    )
    
    // Handle the result based on the zap type
    switch result {
    case .lightning(let invoice):
        // Present Lightning invoice for payment
        print("Pay Lightning invoice: \(invoice)")
    case .nutzap(let nutzapResult):
        // Nutzap completed automatically
        print("Nutzap sent successfully: \(nutzapResult.eventId)")
    case .qrCode(let paymentRequest):
        // Show QR code to user for payment
        presentQRCode(for: paymentRequest)
    }
}

// Monitor zaps on your content
func watchZaps(for pubkey: String) {
    let zapSource = ndk.subscribe(
        filter: NDKFilter(
            kinds: [EventKind.zap],
            tags: ["p": Set([pubkey])]
        ),
        maxAge: 0  // Real-time
    )
    
    Task {
        for await zapEvent in zapSource.events {
            if let zapReceipt = try? NDKZapReceipt(event: zapEvent) {
                print("⚡ Received \(zapReceipt.amount) sats from \(zapReceipt.senderPubkey ?? "anon")")
                if let comment = zapReceipt.comment {
                    print("Comment: \(comment)")
                }
            }
        }
    }
}
```

## File Storage with Blossom

### Upload Files

```swift
// Upload image to Blossom servers
func uploadImage(_ imageData: Data) async throws -> String {
    guard let signer = ndk.signer else { throw NDKError.notConfigured("No signer") }
    
    // Upload to multiple servers for redundancy
    let servers = [
        "https://blossom.primal.net",
        "https://blossom.nostr.hu"
    ]
    
    let blob = try await ndk.uploadToBlossom(
        data: imageData,
        mimeType: "image/jpeg",
        servers: servers,
        signer: signer
    )
    
    // Create file metadata event
    let fileEvent = try await ndk.publishEvent { builder in
        builder
            .content(blob.url)
            .kind(EventKind.fileMetadata)
            .tag(["url", blob.url])
            .tag(["m", blob.mimeType ?? "image/jpeg"])
            .tag(["x", blob.sha256])
            .tag(["size", String(blob.size)])
    }
    
    return blob.url
}
```

### Create Image Post

```swift
// Create a post with an image
func createImagePost(imageData: Data, caption: String) async throws {
    // Upload image first
    let imageUrl = try await uploadImage(imageData)
    
    // Create imeta tags for the image
    let imeta = ImetaTag(
        url: imageUrl,
        mimeType: "image/jpeg",
        sha256: imageData.sha256Hex(),
        size: imageData.count
    )
    
    // Publish note with image
    let post = try await ndk.publishEvent { builder in
        builder
            .content("\(caption)\n\n\(imageUrl)")
            .kind(EventKind.textNote)
            .addImetaTag(imeta)
    }
}
```

## Relay Management

### Dynamic Relay Selection

```swift
// Use outbox model for optimal relay selection
let outboxNDK = NDK(
    relayUrls: [], // Start with no relays
    outboxModel: .enabled(
        defaultRelays: [
            "wss://relay.damus.io",
            "wss://relay.primal.net"
        ]
    )
)

// NDK will automatically:
// 1. Fetch relay lists from users you interact with
// 2. Connect to their preferred relays when fetching their events
// 3. Publish to relays where your followers read from

// Monitor relay changes
Task {
    for await update in outboxNDK.relayPoolUpdates {
        print("Relay pool updated: \(update.addedRelays) added, \(update.removedRelays) removed")
    }
}
```

### Relay Health Monitoring

```swift
// Monitor relay performance
class RelayHealthMonitor {
    func startMonitoring(_ ndk: NDK) {
        Task {
            for await metrics in ndk.pool.relayMetrics {
                for (relay, health) in metrics {
                    print("\(relay):")
                    print("  Latency: \(health.averageLatency)ms")
                    print("  Success rate: \(health.successRate)%")
                    print("  Events/sec: \(health.eventsPerSecond)")
                    
                    // Disconnect from unhealthy relays
                    if health.successRate < 50 {
                        await ndk.removeRelay(relay)
                        print("  ❌ Removed unhealthy relay")
                    }
                }
            }
        }
    }
}
```

## Error Handling

### Comprehensive Error Handling

```swift
// Robust error handling pattern
func publishWithRetry(_ content: String, maxRetries: Int = 3) async throws -> NDKEvent {
    var lastError: Error?
    
    for attempt in 1...maxRetries {
        do {
            let event = try await ndk.publishEvent { builder in
                builder.content(content).kind(EventKind.textNote)
            }
            
            // Wait for confirmation from majority of relays
            let confirmations = try await event.waitForConfirmation(
                minRelays: ndk.pool.connectedRelays().count / 2,
                timeout: 5.0
            )
            
            if confirmations.isEmpty {
                throw NDKError.publishFailed(relay: "majority", message: "No confirmations")
            }
            
            return event
            
        } catch let error as NDKError {
            lastError = error
            
            switch error {
            case .timeout:
                print("Timeout on attempt \(attempt), retrying...")
                continue
                
            case .connectionLost, .connectionFailed:
                // Try to reconnect
                print("Connection issue, reconnecting...")
                try await ndk.reconnect()
                continue
                
            case .rateLimited(let message):
                print("Rate limited: \(message)")
                // Wait before retry
                try await Task.sleep(nanoseconds: UInt64(attempt * 1_000_000_000))
                continue
                
            default:
                throw error  // Don't retry other errors
            }
        }
    }
    
    throw lastError ?? NDKError.unknown("Failed after \(maxRetries) attempts")
}
```

## Performance Optimization

### Efficient Event Processing

```swift
// Process large event streams efficiently
func processLargeEventStream() async {
    let source = ndk.subscribe(
        filter: NDKFilter(kinds: [1], limit: 1000),
        maxAge: 3600
    )
    
    // Use actors for thread-safe processing
    let processor = EventProcessor()
    
    // Process events as they arrive
    for await event in source.events {
        await processor.processEvent(event)
        
        // Optional: break after certain count
        if await processor.getProcessedCount() >= 1000 {
            break
        }
    }
}

actor EventProcessor {
    private var processedCount = 0
    
    func processEvent(_ event: NDKEvent) async {
        // Thread-safe event processing
        processedCount += 1
        
        if processedCount % 100 == 0 {
            print("Processed \(processedCount) events total")
        }
    }
    
    func getProcessedCount() -> Int {
        return processedCount
    }
}
```

### Memory-Efficient Subscriptions

```swift
// Stream events without holding all in memory
func streamLargeDataset() {
    let source = ndk.subscribe(
        filter: NDKFilter(kinds: [1]),
        maxAge: 0  // No cache for streaming
    )
    
    Task {
        // Use AsyncSequence for memory efficiency
        for await event in source.events {
            // Process one at a time
            processEvent(event)
            
            // Can break when needed
            if shouldStop() {
                source.cancel()
                break
            }
        }
    }
}
```

## SwiftUI Integration

### Observable Event Store

```swift
// Create an observable store for SwiftUI
@MainActor
class EventStore: ObservableObject {
    @Published var events: [NDKEvent] = []
    @Published var isLoading = false
    @Published var error: Error?
    
    private let ndk: NDK
    private var dataSource: NDKSubscription<NDKEvent>?
    
    init(ndk: NDK) {
        self.ndk = ndk
    }
    
    func loadEvents(filter: NDKFilter) {
        isLoading = true
        error = nil
        
        dataSource = ndk.subscribe(
            filter: filter,
            maxAge: 300,
            cachePolicy: .cacheWithNetwork
        )
        
        Task {
            do {
                // Show cached immediately
                let cached = await dataSource!.getCached()
                if !cached.isEmpty {
                    self.events = cached
                    self.isLoading = false
                }
                
                // Then update with fresh data
                for await event in dataSource!.events {
                    if !events.contains(where: { $0.id == event.id }) {
                        events.append(event)
                        events.sort { $0.createdAt > $1.createdAt }
                    }
                }
            } catch {
                self.error = error
                self.isLoading = false
            }
        }
    }
    
    func refresh() {
        dataSource?.invalidateCache()
        loadEvents(filter: dataSource?.filter ?? NDKFilter())
    }
}

// Use in SwiftUI View
struct EventListView: View {
    @StateObject private var store: EventStore
    
    init(ndk: NDK, filter: NDKFilter) {
        _store = StateObject(wrappedValue: EventStore(ndk: ndk))
    }
    
    var body: some View {
        List(store.events) { event in
            EventRow(event: event)
        }
        .refreshable {
            store.refresh()
        }
        .overlay {
            if store.isLoading && store.events.isEmpty {
                ProgressView()
            }
        }
        .alert("Error", isPresented: .constant(store.error != nil)) {
            Button("OK") { store.error = nil }
        } message: {
            Text(store.error?.localizedDescription ?? "")
        }
    }
}
```

### Reactive User Profiles

```swift
// Auto-updating user profile view
struct UserProfileView: View {
    let pubkey: String
    @State private var profile: NDKUserProfile?
    @State private var dataSource: NDKSubscription<NDKUserProfile>?
    
    var body: some View {
        VStack {
            if let profile = profile {
                AsyncImage(url: URL(string: profile.picture ?? ""))
                    .frame(width: 100, height: 100)
                    .clipShape(Circle())
                
                Text(profile.displayName ?? profile.name ?? "Anonymous")
                    .font(.title)
                
                Text(profile.about ?? "")
                    .font(.body)
            } else {
                ProgressView()
            }
        }
        .task {
            // Create reactive profile source
            dataSource = ndk.subscribe(
                filter: NDKFilter(kinds: [0], authors: [pubkey]),
                maxAge: 3600,
                transform: { event in
                    try? event.decodeMetadata()
                }
            )
            
            // Update UI when profile changes
            for await updatedProfile in dataSource!.values {
                profile = updatedProfile
            }
        }
    }
}
```

## URL Handling

### Working with Relay URLs

```swift
// Use URLUtils for safe URL creation
let relayUrl = "relay.example.com"
if let url = URLUtils.safeURL(relayUrl) {
    // Valid URL
} else {
    // Invalid URL
}

// Or use validateURL for throwing version
do {
    let url = try URLUtils.validateURL(relayUrl)
    // Use URL
} catch {
    // Handle invalid URL error
}

// Ensure WebSocket scheme is present
let cleanUrl = RelayConstants.WebSocketScheme.ensureWebSocketScheme("relay.example.com")
// Returns: "wss://relay.example.com"

// Check if URL has WebSocket scheme
if RelayConstants.WebSocketScheme.isWebSocketURL(urlString) {
    // URL has ws:// or wss:// scheme
}

// Use built-in relay constants
let popularRelays = [
    RelayConstants.damus,
    RelayConstants.nostrBand,
    RelayConstants.primal
]

// Or use pre-configured sets
let relays = RelayConstants.defaultRelays  // Common relay set
let extendedRelays = RelayConstants.extendedRelays  // Broader reach
```

### String Extensions for Common Operations

```swift
// Trim whitespace and newlines
let cleaned = userInput.trimmed

// Check if string has content after trimming
if userInput.hasContent {
    // String has non-whitespace content
}

// Normalize string (trim + lowercase)
let normalized = relayUrl.normalized

// Check WebSocket URL directly on string
if urlString.isWebSocketURL {
    // String is a WebSocket URL
}

// Normalize relay URLs  
let normalizedRelay = "RELAY.EXAMPLE.COM".normalizedRelayURL
// Returns: "wss://relay.example.com"
```

## Best Practices

### 1. Always Handle Offline Mode
```swift
let events = await ndk.subscribe(filter: filter, cachePolicy: .cacheWithNetwork).collect()
if events.isEmpty && !ndk.isConnected {
    // Show offline message
}
```

### 2. Use Appropriate Cache Ages
- Profiles: 1 hour (`maxAge: 3600`)
- Recent posts: 5 minutes (`maxAge: 300`)
- Historical data: 1 day (`maxAge: 86400`)
- Real-time: Always fresh (`maxAge: 0`)

### 3. Cancel Subscriptions
```swift
let dataSource = ndk.subscribe(filter: filter)
// Use it...
dataSource.cancel() // Clean up when done
```

### 4. Batch Operations
Instead of multiple individual requests, batch when possible:
```swift
// Good
let profiles = await loadProfiles(pubkeys: Array(pubkeySet))

// Avoid
for pubkey in pubkeySet {
    let profile = await loadProfile(pubkey: pubkey)
}
```

### 5. Error Recovery
Always implement graceful degradation:
```swift
do {
    try await riskyOperation()
} catch {
    // Fall back to cache
    // Show user-friendly error
    // Log for debugging
}
```