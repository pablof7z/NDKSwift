# Advanced NDKSwift Usage Guide

This guide covers advanced patterns, best practices, and real-world examples for building sophisticated Nostr applications with NDKSwift.

## Table of Contents
1. [Advanced Relay Management](#advanced-relay-management)
2. [Subscription Optimization](#subscription-optimization)
3. [Cache Strategies](#cache-strategies)
4. [Custom Event Types](#custom-event-types)
5. [Payment Integration](#payment-integration)
6. [Performance Optimization](#performance-optimization)
7. [Security Best Practices](#security-best-practices)
8. [Testing Strategies](#testing-strategies)

## Advanced Relay Management

### Dynamic Relay Selection

Implement intelligent relay selection based on user preferences and relay performance:

```swift
class RelayManager {
    private var relayStats: [String: RelayStats] = [:]
    
    struct RelayStats {
        var successRate: Double
        var averageLatency: TimeInterval
        var lastError: Date?
        var supportedNIPs: Set<Int>
    }
    
    func selectOptimalRelays(for event: NDKEvent, count: Int = 3) -> [String] {
        let requiredNIPs = getRequiredNIPs(for: event)
        
        return relayStats
            .filter { stats in
                // Filter by required NIPs support
                requiredNIPs.isSubset(of: stats.value.supportedNIPs)
            }
            .sorted { a, b in
                // Sort by success rate and latency
                let scoreA = a.value.successRate / (1 + a.value.averageLatency)
                let scoreB = b.value.successRate / (1 + b.value.averageLatency)
                return scoreA > scoreB
            }
            .prefix(count)
            .map { $0.key }
    }
    
    private func getRequiredNIPs(for event: NDKEvent) -> Set<Int> {
        switch event.kind {
        case 4: return [4] // Encrypted DMs
        case 9734...9735: return [57] // Zaps
        case 30000...39999: return [33] // Parameterized replaceable
        default: return []
        }
    }
}
```

### Relay Pool with Fallback

Create a robust relay pool with automatic fallback:

```swift
actor RobustRelayPool {
    private let primaryRelays: [String]
    private let fallbackRelays: [String]
    private var activeConnections: [String: NDKRelay] = [:]
    private let maxRetries = 3
    
    func publish(_ event: NDKEvent) async throws {
        var lastError: Error?
        
        // Try primary relays first
        for relay in primaryRelays {
            do {
                try await publishToRelay(event, relay: relay)
                return // Success
            } catch {
                lastError = error
                print("Primary relay \(relay) failed: \(error)")
            }
        }
        
        // Fallback to secondary relays
        for relay in fallbackRelays {
            do {
                try await publishToRelay(event, relay: relay)
                return // Success
            } catch {
                lastError = error
                print("Fallback relay \(relay) failed: \(error)")
            }
        }
        
        throw lastError ?? NDKError.publishFailed("All relays failed")
    }
}
```

### Outbox Model Implementation

Implement NIP-65 compliant outbox model:

```swift
class OutboxModel {
    private let ndk: NDK
    
    func publishWithOutbox(_ event: NDKEvent) async throws {
        // Get author's relay list
        let relayListFilter = NDKFilter(
            authors: [event.pubkey],
            kinds: [10002], // Relay list
            limit: 1
        )
        
        let authorRelays = await fetchRelayList(filter: relayListFilter)
        
        // Publish to author's write relays
        let writeRelays = authorRelays.filter { $0.isWriteRelay }
        try await publishToRelays(event, relays: writeRelays)
    }
    
    func fetchEventsWithOutbox(filter: NDKFilter) async throws -> [NDKEvent] {
        // Get relay lists for all authors in filter
        let relayListFilters = filter.authors?.map { author in
            NDKFilter(authors: [author], kinds: [10002], limit: 1)
        } ?? []
        
        // Collect all read relays
        var readRelays = Set<String>()
        for filter in relayListFilters {
            let relays = await fetchRelayList(filter: filter)
                .filter { $0.isReadRelay }
                .map { $0.url }
            readRelays.formUnion(relays)
        }
        
        // Query from appropriate relays
        return await queryRelays(filter: filter, relays: Array(readRelays))
    }
}
```

## Subscription Optimization

### Subscription Batching

Optimize network usage by batching similar subscriptions:

```swift
actor SubscriptionBatcher {
    private var pendingFilters: [NDKFilter] = []
    private var batchTimer: Timer?
    private let batchInterval: TimeInterval = 0.1 // 100ms
    
    func addFilter(_ filter: NDKFilter) async -> NDKSubscription {
        pendingFilters.append(filter)
        
        if batchTimer == nil {
            scheduleBatch()
        }
        
        // Return a placeholder subscription that will be populated
        return NDKSubscription(filters: [filter])
    }
    
    private func scheduleBatch() {
        batchTimer = Timer.scheduledTimer(withTimeInterval: batchInterval, repeats: false) { _ in
            Task {
                await self.processBatch()
            }
        }
    }
    
    private func processBatch() async {
        let filters = pendingFilters
        pendingFilters.removeAll()
        batchTimer = nil
        
        // Merge similar filters
        let mergedFilters = mergeFilters(filters)
        
        // Create actual subscription
        let subscription = ndk.subscribe(filters: mergedFilters)
        
        // Distribute events to original subscriptions
        subscription.onEvent { event in
            for filter in filters where filter.matches(event) {
                // Route to appropriate handler
            }
        }
    }
    
    private func mergeFilters(_ filters: [NDKFilter]) -> [NDKFilter] {
        // Group by similar characteristics
        let grouped = Dictionary(grouping: filters) { filter in
            // Group by kinds and time range
            "\(filter.kinds ?? [])-\(filter.since ?? 0)-\(filter.until ?? 0)"
        }
        
        return grouped.map { (key, group) in
            // Merge authors and other fields
            var merged = group[0]
            merged.authors = group.flatMap { $0.authors ?? [] }
            merged.ids = group.flatMap { $0.ids ?? [] }
            return merged
        }
    }
}
```

### Lazy Loading with Pagination

Implement efficient pagination for large datasets:

```swift
class PaginatedFeed: ObservableObject {
    @Published var events: [NDKEvent] = []
    private var oldestTimestamp: Timestamp?
    private let pageSize = 20
    private var isLoading = false
    
    func loadNextPage() async {
        guard !isLoading else { return }
        isLoading = true
        
        var filter = NDKFilter(
            kinds: [1],
            limit: pageSize
        )
        
        // Use until timestamp for pagination
        if let oldestTimestamp = oldestTimestamp {
            filter.until = oldestTimestamp - 1
        }
        
        let subscription = ndk.subscribe(
            filters: [filter],
            closeOnEOSE: true
        )
        
        var newEvents: [NDKEvent] = []
        
        for await event in subscription.eventStream() {
            newEvents.append(event)
            
            // Update oldest timestamp
            if oldestTimestamp == nil || event.createdAt < oldestTimestamp! {
                oldestTimestamp = event.createdAt
            }
        }
        
        // Append and sort
        events.append(contentsOf: newEvents)
        events.sort { $0.createdAt > $1.createdAt }
        
        isLoading = false
    }
}
```

## Cache Strategies

### Hierarchical Cache

Implement a multi-level cache for optimal performance:

```swift
actor HierarchicalCache: NDKCacheAdapter {
    private let memoryCache: NDKInMemoryCache
    private let diskCache: NDKFileCache
    private let maxMemoryEvents = 1000
    
    init(diskPath: String) throws {
        self.memoryCache = NDKInMemoryCache()
        self.diskCache = try NDKFileCache(path: diskPath)
    }
    
    func saveEvent(_ event: NDKEvent) async throws {
        // Save to both caches
        try await memoryCache.saveEvent(event)
        try await diskCache.saveEvent(event)
        
        // Implement LRU eviction for memory cache
        await evictOldestIfNeeded()
    }
    
    func getEvent(id: String) async throws -> NDKEvent? {
        // Check memory first
        if let event = try await memoryCache.getEvent(id: id) {
            return event
        }
        
        // Fall back to disk
        if let event = try await diskCache.getEvent(id: id) {
            // Promote to memory cache
            try await memoryCache.saveEvent(event)
            return event
        }
        
        return nil
    }
    
    private func evictOldestIfNeeded() async {
        // Implement LRU eviction logic
    }
}
```

### Smart Cache Invalidation

Implement intelligent cache invalidation for replaceable events:

```swift
extension NDKFileCache {
    func handleReplaceableEvent(_ event: NDKEvent) async throws {
        let replaceableKinds: Set<EventKind> = [0, 3, 10000...10099]
        
        guard replaceableKinds.contains(event.kind) else {
            try await saveEvent(event)
            return
        }
        
        // Find and remove older versions
        let filter = NDKFilter(
            authors: [event.pubkey],
            kinds: [event.kind]
        )
        
        let existingEvents = try await query(
            subscription: NDKSubscription(filters: [filter])
        )
        
        // Remove older events
        for existing in existingEvents where existing.createdAt < event.createdAt {
            try await removeEvent(id: existing.id)
        }
        
        // Save new event
        try await saveEvent(event)
    }
}
```

## Custom Event Types

### Define Custom Event Kinds

Create type-safe custom event kinds:

```swift
// Custom event kind for a decentralized blog
struct BlogPost {
    static let kind: EventKind = 30023 // Long-form content
    
    let title: String
    let summary: String
    let content: String
    let publishedAt: Date
    let tags: [String]
    let imageUrl: String?
    
    func toEvent(author: NDKSigner) async throws -> NDKEvent {
        var tags: [[String]] = [
            ["d", UUID().uuidString], // Unique identifier
            ["title", title],
            ["summary", summary],
            ["published_at", String(Int(publishedAt.timeIntervalSince1970))]
        ]
        
        // Add content tags
        for tag in self.tags {
            tags.append(["t", tag])
        }
        
        if let imageUrl = imageUrl {
            tags.append(["image", imageUrl])
        }
        
        var event = NDKEvent(
            pubkey: author.publicKey,
            createdAt: .now(),
            kind: BlogPost.kind,
            tags: tags,
            content: content
        )
        
        try await event.sign(with: author)
        return event
    }
    
    static func from(event: NDKEvent) -> BlogPost? {
        guard event.kind == kind else { return nil }
        
        return BlogPost(
            title: event.tagValue(for: "title") ?? "",
            summary: event.tagValue(for: "summary") ?? "",
            content: event.content,
            publishedAt: Date(timeIntervalSince1970: Double(
                event.tagValue(for: "published_at") ?? "0"
            ) ?? 0),
            tags: event.tagValues(for: "t"),
            imageUrl: event.tagValue(for: "image")
        )
    }
}
```

### Event Validation

Implement comprehensive event validation:

```swift
protocol EventValidator {
    func validate(_ event: NDKEvent) throws
}

struct StrictEventValidator: EventValidator {
    func validate(_ event: NDKEvent) throws {
        // Validate event ID
        let computedId = try computeEventId(event)
        guard event.id == computedId else {
            throw NDKError.invalidEvent("Event ID mismatch")
        }
        
        // Validate signature
        guard event.verify() else {
            throw NDKError.invalidEvent("Invalid signature")
        }
        
        // Validate timestamp (not too far in future)
        let maxFutureTime = Timestamp.now() + 900 // 15 minutes
        guard event.createdAt <= maxFutureTime else {
            throw NDKError.invalidEvent("Event timestamp too far in future")
        }
        
        // Kind-specific validation
        try validateKindSpecific(event)
    }
    
    private func validateKindSpecific(_ event: NDKEvent) throws {
        switch event.kind {
        case 0: // Metadata
            // Ensure content is valid JSON
            guard let _ = try? JSONSerialization.jsonObject(
                with: event.content.data(using: .utf8)!
            ) else {
                throw NDKError.invalidEvent("Invalid metadata JSON")
            }
            
        case 1: // Text note
            // Check content length
            guard event.content.count <= 32_000 else {
                throw NDKError.invalidEvent("Content too long")
            }
            
        default:
            break
        }
    }
}
```

## Payment Integration

### Lightning Zaps Implementation

Implement NIP-57 compliant Lightning zaps:

```swift
class ZapService {
    private let ndk: NDK
    
    struct ZapRequest {
        let amount: Int // millisatoshis
        let comment: String?
        let recipientPubkey: String
        let eventId: String?
        let relays: [String]
    }
    
    func createZapRequest(_ request: ZapRequest) async throws -> String {
        guard let signer = ndk.signer else {
            throw NDKError.signingFailed
        }
        
        var tags: [[String]] = [
            ["p", request.recipientPubkey],
            ["amount", String(request.amount)],
            ["relays"] + request.relays
        ]
        
        if let eventId = request.eventId {
            tags.append(["e", eventId])
        }
        
        var zapRequestEvent = NDKEvent(
            pubkey: signer.publicKey,
            createdAt: .now(),
            kind: 9734,
            tags: tags,
            content: request.comment ?? ""
        )
        
        try await zapRequestEvent.sign(with: signer)
        return try zapRequestEvent.serialize()
    }
    
    func requestInvoice(
        zapRequest: String,
        recipient: NDKUser
    ) async throws -> String {
        // Get recipient's LNURL
        guard let lud16 = recipient.profile?.lud16 else {
            throw NDKError.walletError("No Lightning address")
        }
        
        // Convert to LNURL
        let lnurl = try await resolveLightningAddress(lud16)
        
        // Request invoice with zap request
        let invoice = try await fetchInvoice(
            lnurl: lnurl,
            zapRequest: zapRequest
        )
        
        return invoice
    }
}
```

### Cashu Integration

Work with Cashu mints and tokens:

```swift
class CashuService {
    private let ndk: NDK
    
    func storeMintList(_ mints: [NDKCashuMintList.CashuMint]) async throws {
        guard let signer = ndk.signer else { return }
        
        let mintList = NDKCashuMintList(mints: mints)
        let event = try await mintList.toEvent(signer: signer)
        
        try await ndk.publish(event)
    }
    
    func sendNutzap(
        amount: Int,
        proofs: [CashuProof],
        recipient: String,
        mintUrl: String,
        comment: String? = nil
    ) async throws {
        guard let signer = ndk.signer else { return }
        
        // Create Nutzap event
        let nutzap = NDKNutzap(
            proofs: proofs,
            mint: mintUrl,
            comment: comment
        )
        
        var event = NDKEvent(
            pubkey: signer.publicKey,
            createdAt: .now(),
            kind: 9321, // Nutzap
            tags: [
                ["p", recipient],
                ["amount", String(amount)],
                ["u", mintUrl],
                ["proofs", nutzap.proofsJson]
            ],
            content: comment ?? ""
        )
        
        try await event.sign(with: signer)
        try await ndk.publish(event)
    }
}
```

## Performance Optimization

### Event Deduplication

Implement efficient event deduplication:

```swift
actor EventDeduplicator {
    private var seenEvents = Set<String>()
    private var eventCache = LRUCache<String, NDKEvent>(capacity: 10000)
    
    func process(_ event: NDKEvent) -> NDKEvent? {
        // Check if we've seen this event
        guard !seenEvents.contains(event.id) else {
            return nil
        }
        
        seenEvents.insert(event.id)
        
        // For replaceable events, check if we have a newer version
        if isReplaceable(event.kind) {
            let key = replaceableKey(for: event)
            if let cached = eventCache.get(key),
               cached.createdAt >= event.createdAt {
                return nil // We have a newer version
            }
            eventCache.set(key, event)
        }
        
        return event
    }
    
    private func isReplaceable(_ kind: EventKind) -> Bool {
        return kind == 0 || kind == 3 || 
               (10000...19999).contains(kind) ||
               (30000...39999).contains(kind)
    }
    
    private func replaceableKey(for event: NDKEvent) -> String {
        if (30000...39999).contains(event.kind) {
            // Parameterized replaceable
            let d = event.tagValue(for: "d") ?? ""
            return "\(event.pubkey):\(event.kind):\(d)"
        } else {
            // Regular replaceable
            return "\(event.pubkey):\(event.kind)"
        }
    }
}
```

### Concurrent Event Processing

Process events concurrently for better performance:

```swift
actor ConcurrentEventProcessor {
    private let processingQueue = DispatchQueue(
        label: "event.processing",
        attributes: .concurrent
    )
    private let maxConcurrency = 10
    
    func processEvents(_ events: [NDKEvent]) async {
        await withTaskGroup(of: Void.self) { group in
            // Limit concurrency
            let semaphore = DispatchSemaphore(value: maxConcurrency)
            
            for event in events {
                group.addTask {
                    semaphore.wait()
                    defer { semaphore.signal() }
                    
                    await self.processEvent(event)
                }
            }
        }
    }
    
    private func processEvent(_ event: NDKEvent) async {
        // Validate
        guard validateEvent(event) else { return }
        
        // Process based on kind
        switch event.kind {
        case 0:
            await processMetadata(event)
        case 1:
            await processTextNote(event)
        case 4:
            await processDirectMessage(event)
        default:
            await processGenericEvent(event)
        }
    }
}
```

## Security Best Practices

### Secure Key Storage

Implement secure storage for private keys:

```swift
import Security
import CryptoKit

class SecureKeyStorage {
    private let service = "com.yourapp.nostr"
    
    func savePrivateKey(_ nsec: String) throws {
        // Derive key from user's biometrics or passphrase
        let encryptionKey = try deriveEncryptionKey()
        
        // Encrypt the private key
        let encrypted = try encrypt(nsec, with: encryptionKey)
        
        // Store in Keychain with biometric protection
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "private-key",
            kSecValueData as String: encrypted,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrAccessControl as String: SecAccessControlCreateWithFlags(
                nil,
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                [.biometryCurrentSet, .privateKeyUsage],
                nil
            )!
        ]
        
        SecItemDelete(query as CFDictionary) // Remove old item if exists
        
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }
    
    func loadPrivateKey() throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "private-key",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let encryptedData = result as? Data else {
            throw KeychainError.loadFailed(status)
        }
        
        let encryptionKey = try deriveEncryptionKey()
        return try decrypt(encryptedData, with: encryptionKey)
    }
}
```

### Content Validation

Validate and sanitize user-generated content:

```swift
struct ContentValidator {
    static func sanitize(_ content: String) -> String {
        var sanitized = content
        
        // Remove potential XSS vectors
        let dangerousPatterns = [
            "<script[^>]*>.*?</script>",
            "javascript:",
            "on\\w+\\s*=",
            "<iframe[^>]*>.*?</iframe>"
        ]
        
        for pattern in dangerousPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                sanitized = regex.stringByReplacingMatches(
                    in: sanitized,
                    range: NSRange(sanitized.startIndex..., in: sanitized),
                    withTemplate: ""
                )
            }
        }
        
        return sanitized
    }
    
    static func validateURL(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString),
              let scheme = url.scheme else {
            return false
        }
        
        // Only allow http(s) and common protocols
        let allowedSchemes = ["http", "https", "nostr", "lightning"]
        return allowedSchemes.contains(scheme.lowercased())
    }
}
```

## Testing Strategies

### Mock Relay for Testing

Create a mock relay for unit tests:

```swift
class MockRelay: NDKRelayConnection {
    var sentMessages: [NostrMessage] = []
    var mockResponses: [NostrMessage] = []
    
    override func send(_ message: NostrMessage) async throws {
        sentMessages.append(message)
        
        // Simulate responses
        switch message {
        case .subscribe(let sub, let filters):
            // Send mock events matching filters
            for response in mockResponses {
                if case .event(_, let event) = response {
                    for filter in filters where filter.matches(event) {
                        await handleMessage(response)
                        break
                    }
                }
            }
            // Send EOSE
            await handleMessage(.endOfStoredEvents(sub))
            
        case .event(let event):
            // Simulate OK response
            await handleMessage(.ok(event.id, true, ""))
            
        default:
            break
        }
    }
}
```

### Integration Tests

Write comprehensive integration tests:

```swift
class NDKIntegrationTests: XCTestCase {
    var ndk: NDK!
    var testSigner: NDKPrivateKeySigner!
    
    override func setUp() async throws {
        // Use test relay
        ndk = NDK(relayUrls: ["wss://nos.lol"])
        testSigner = NDKPrivateKeySigner.generate()
        ndk.signer = testSigner
        
        try await ndk.connect()
    }
    
    func testPublishAndRetrieve() async throws {
        // Create unique content for this test
        let uniqueContent = "Test note \(UUID().uuidString)"
        
        // Publish event
        var event = NDKEvent(
            pubkey: testSigner.publicKey,
            createdAt: .now(),
            kind: 1,
            content: uniqueContent
        )
        
        try await event.sign(with: testSigner)
        try await ndk.publish(event)
        
        // Wait for propagation
        try await Task.sleep(nanoseconds: 2_000_000_000)
        
        // Query for the event
        let filter = NDKFilter(
            ids: [event.id],
            limit: 1
        )
        
        let subscription = ndk.subscribe(filters: [filter])
        
        let expectation = XCTestExpectation(description: "Event received")
        var receivedEvent: NDKEvent?
        
        subscription.onEvent { event in
            receivedEvent = event
            expectation.fulfill()
        }
        
        await subscription.start()
        await fulfillment(of: [expectation], timeout: 5)
        
        XCTAssertEqual(receivedEvent?.id, event.id)
        XCTAssertEqual(receivedEvent?.content, uniqueContent)
    }
}
```

### Performance Tests

Measure and optimize performance:

```swift
class PerformanceTests: XCTestCase {
    func testLargeSubscriptionPerformance() throws {
        let cache = try NDKFileCache(path: "test-cache")
        
        measure {
            let expectation = XCTestExpectation()
            
            Task {
                // Create 1000 test events
                let events = (0..<1000).map { i in
                    NDKEvent(
                        pubkey: "test",
                        createdAt: Timestamp(i),
                        kind: 1,
                        content: "Event \(i)"
                    )
                }
                
                // Save all events
                for event in events {
                    try await cache.saveEvent(event)
                }
                
                // Query with complex filter
                let filter = NDKFilter(
                    kinds: [1],
                    since: 100,
                    until: 900
                )
                
                let subscription = NDKSubscription(filters: [filter])
                let results = try await cache.query(subscription: subscription)
                
                XCTAssertEqual(results.count, 800)
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: 10)
        }
    }
}
```

## Best Practices Summary

1. **Always validate events** before processing or displaying
2. **Use appropriate cache strategies** for your use case
3. **Implement proper error handling** with meaningful error messages
4. **Optimize subscriptions** to reduce bandwidth usage
5. **Secure private keys** using platform-specific secure storage
6. **Test thoroughly** with both unit and integration tests
7. **Monitor performance** and optimize bottlenecks
8. **Follow NIPs** for standardized functionality
9. **Handle edge cases** like network failures gracefully
10. **Document your code** for future maintainability

This guide provides advanced patterns for building robust, efficient, and secure Nostr applications with NDKSwift. For basic usage, refer to the [iOS App Tutorial](./IOS_APP_TUTORIAL.md) and [API Reference](./API_REFERENCE.md).