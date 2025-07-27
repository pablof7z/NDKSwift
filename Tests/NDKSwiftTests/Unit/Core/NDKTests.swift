import XCTest
@testable import NDKSwift

final class NDKTests: NDKTestCase {
    
    // MARK: - Initialization Tests
    
    func testInitializationWithDefaults() async {
        let ndk = NDK()
        
        XCTAssertNil(ndk.signer)
        XCTAssertNil(ndk.cache)
        let activeUser = await ndk.activeUser
        XCTAssertNil(activeUser)
        XCTAssertTrue(ndk.outboxEnabled)
        XCTAssertFalse(ndk.debugMode)
        let relays = await ndk.relays
        XCTAssertTrue(relays.isEmpty)
    }
    
    func testInitializationWithParameters() async throws {
        let relayUrls = ["wss://relay1.test", "wss://relay2.test"]
        let signer = try NDKPrivateKeySigner.generate()
        let cache = createMemoryCache()
        
        let ndk = NDK(
            relayUrls: relayUrls,
            signer: signer,
            cache: cache
        )
        
        XCTAssertNotNil(ndk.signer)
        XCTAssertNotNil(ndk.cache)
        let activeUser = await ndk.activeUser
        XCTAssertNotNil(activeUser)
        let signerPubkey = try await signer.pubkey
        XCTAssertEqual(activeUser?.pubkey, signerPubkey)
        let relays = await ndk.relays
        XCTAssertEqual(relays.count, 2)
        XCTAssertEqual(Set(relays.map(\.url)), Set(relayUrls))
    }
    
    func testActiveUserUpdatesWithSigner() async throws {
        let ndk = createTestNDK()
        let activeUser1 = await ndk.activeUser
        XCTAssertNil(activeUser1)
        
        let signer = try NDKPrivateKeySigner.generate()
        ndk.signer = signer
        
        let activeUser2 = await ndk.activeUser
        XCTAssertNotNil(activeUser2)
        let signerPubkey = try await signer.pubkey
        XCTAssertEqual(activeUser2?.pubkey, signerPubkey)
    }
    
    // MARK: - Relay Management Tests
    
    func testAddRelay() async {
        let ndk = createTestNDK()
        let relayUrl = "wss://test.relay"
        
        let relay = await ndk.addRelay(relayUrl)
        
        XCTAssertEqual(relay.url, relayUrl)
        XCTAssertTrue(ndk.relays.contains { $0.url == relayUrl })
        XCTAssertEqual(ndk.relays.count, 1)
    }
    
    func testAddDuplicateRelay() async {
        let ndk = createTestNDK()
        let relayUrl = "wss://test.relay"
        
        let relay1 = await ndk.addRelay(relayUrl)
        let relay2 = await ndk.addRelay(relayUrl)
        
        XCTAssertEqual(relay1.url, relay2.url)
        XCTAssertEqual(ndk.relays.count, 1) // Should not duplicate
    }
    
    func testRemoveRelay() async {
        let ndk = createTestNDK()
        let relayUrl = "wss://test.relay"
        
        await ndk.addRelay(relayUrl)
        XCTAssertEqual(ndk.relays.count, 1)
        
        await ndk.removeRelay(relayUrl)
        XCTAssertEqual(ndk.relays.count, 0)
    }
    
    func testRemoveNonExistentRelay() async {
        let ndk = createTestNDK()
        await ndk.addRelay("wss://test1.relay")
        
        await ndk.removeRelay("wss://nonexistent.relay")
        XCTAssertEqual(ndk.relays.count, 1) // Should not affect existing relays
    }
    
    // MARK: - Connection Tests
    
    func testConnectDisconnect() async throws {
        let ndk = createTestNDK(relayUrls: ["wss://mock.relay"])
        
        // Initially disconnected
        let initiallyConnected = await ndk.relays.asyncMap { await $0.isConnected }
        XCTAssertTrue(initiallyConnected.allSatisfy { !$0 })
        
        // Connect
        await ndk.connect()
        
        // Disconnect
        await ndk.disconnect()
    }
    
    func testWaitForRelayConnections() async {
        let ndk = createTestNDK()
        
        // No relays, should return 0 immediately
        let connected = await ndk.waitForRelayConnections(minimumRelays: 1, timeout: 1.0)
        XCTAssertEqual(connected, 0)
    }
    
    // MARK: - Event Publishing Tests
    
    func testPublishWithoutSigner() async throws {
        let ndk = createTestNDK()
        let event = EventTestFactory.createEvent()
        
        await XCTAssertAsyncThrows {
            _ = try await ndk.publish(event)
        }
    }
    
    func testPublishWithSigner() async throws {
        let signer = try NDKPrivateKeySigner.generate()
        let ndk = createTestNDK(signer: signer)
        
        let builder = NDKEventBuilder(ndk: ndk)
            .content("Test publish")
            .kind(1)
        
        let event = try await builder.build()
        
        // Should succeed even without relays (optimistic publishing)
        let publishedRelays = try await ndk.publish(event)
        XCTAssertTrue(publishedRelays.isEmpty) // No relays connected
        
        // Event should be signed
        XCTAssertFalse(event.sig.isEmpty)
        XCTAssertEqual(event.pubkey, try await signer.pubkey)
    }
    
    func testPublishToSpecificRelays() async throws {
        let signer = try NDKPrivateKeySigner.generate()
        let ndk = createTestNDK(signer: signer)
        
        // Add multiple relays
        await ndk.addRelay("wss://relay1.test")
        await ndk.addRelay("wss://relay2.test")
        await ndk.addRelay("wss://relay3.test")
        
        let event = try await NDKEventBuilder(ndk: ndk)
            .content("Test targeted publish")
            .build()
        
        // Publish to specific relays only
        let targetRelays = Set(["wss://relay1.test", "wss://relay2.test"])
        let publishedRelays = try await ndk.publish(event: event, to: targetRelays)
        
        // Note: Since we're using mock relays that aren't connected,
        // this will return empty but the API should work
        XCTAssertTrue(publishedRelays.isEmpty || publishedRelays.allSatisfy { targetRelays.contains($0.url) })
    }
    
    // MARK: - Data Access Tests
    
    func testObserveCreatesDataSource() {
        let ndk = createTestNDK()
        let filter = NDKFilter(kinds: [1])
        
        let dataSource = ndk.observe(filter: filter)
        
        XCTAssertNotNil(dataSource)
        XCTAssertEqual(dataSource.filter.kinds, [1])
    }
    
    func testObserveWithTransform() {
        let ndk = createTestNDK()
        let filter = NDKFilter(kinds: [0])
        
        let dataSource = ndk.observe(
            filter: filter,
            transform: { event -> NDKUserProfile? in
                try? event.decodeMetadata()
            }
        )
        
        XCTAssertNotNil(dataSource)
    }
    
    func testFetchEventsWithCache() async throws {
        let cache = createMemoryCache()
        let ndk = createTestNDK(cache: cache)
        
        // Pre-populate cache
        let events = [
            EventTestFactory.createEvent(kind: 1, content: "Event 1"),
            EventTestFactory.createEvent(kind: 1, content: "Event 2"),
            EventTestFactory.createEvent(kind: 2, content: "Event 3")
        ]
        
        for event in events {
            try await cache.saveEvent(event)
        }
        
        // Fetch from cache
        let filter = NDKFilter(kinds: [1])
        let fetchedEvents = await ndk.fetchEvents(filter)
        
        XCTAssertEqual(fetchedEvents.count, 2)
        XCTAssertTrue(fetchedEvents.allSatisfy { $0.kind == 1 })
    }
    
    func testFetchEventById() async throws {
        let cache = createMemoryCache()
        let ndk = createTestNDK(cache: cache)
        
        let event = EventTestFactory.createEvent()
        try await cache.saveEvent(event)
        
        let fetchedEvent = await ndk.fetchEvent(event.id)
        
        XCTAssertNotNil(fetchedEvent)
        XCTAssertEqual(fetchedEvent?.id, event.id)
    }
    
    func testFetchEventByFilter() async throws {
        let cache = createMemoryCache()
        let ndk = createTestNDK(cache: cache)
        
        let event = EventTestFactory.createEvent(kind: 30023)
        try await cache.saveEvent(event)
        
        let filter = NDKFilter(kinds: [30023], limit: 1)
        let fetchedEvent = await ndk.fetchEvent(filter)
        
        XCTAssertNotNil(fetchedEvent)
        XCTAssertEqual(fetchedEvent?.kind, 30023)
    }
    
    // MARK: - User Management Tests
    
    func testGetUserFromNpub() throws {
        let ndk = createTestNDK()
        let npub = "npub1w0zv839p6nz2wnfp8u5fqdqzs9d9pdhg3znye9ej63wh27h73gns6h9nkx"
        
        let user = ndk.getUser(npub: npub)
        
        XCTAssertNotNil(user)
        XCTAssertEqual(user.npub, npub)
        XCTAssertFalse(user.pubkey.isEmpty)
    }
    
    func testGetUserFromPubkey() {
        let ndk = createTestNDK()
        let pubkey = TestFixtures.Keys.alice.publicKey
        
        let user = ndk.getUser(pubkey: pubkey)
        
        XCTAssertNotNil(user)
        XCTAssertEqual(user.pubkey, pubkey)
    }
    
    // MARK: - Profile Fetching Tests
    
    func testFetchProfileFromCache() async throws {
        let cache = createMemoryCache()
        let ndk = createTestNDK(cache: cache)
        
        // Create and cache metadata event
        let metadataEvent = EventTestFactory.createMetadataEvent(
            name: "Alice Test",
            pubkey: TestFixtures.Keys.alice.publicKey
        )
        try await cache.saveEvent(metadataEvent)
        
        // Fetch profile
        let profile = await ndk.fetchProfile(TestFixtures.Keys.alice.publicKey)
        
        XCTAssertNotNil(profile)
        XCTAssertEqual(profile?.name, "Alice Test")
    }
    
    func testFetchProfilesMultiple() async throws {
        let cache = createMemoryCache()
        let ndk = createTestNDK(cache: cache)
        
        // Create metadata events for multiple users
        let users = [
            (pubkey: TestFixtures.Keys.alice.publicKey, name: "Alice"),
            (pubkey: TestFixtures.Keys.bob.publicKey, name: "Bob"),
            (pubkey: TestFixtures.Keys.charlie.publicKey, name: "Charlie")
        ]
        
        for user in users {
            let event = EventTestFactory.createMetadataEvent(
                name: user.name,
                pubkey: user.pubkey
            )
            try await cache.saveEvent(event)
        }
        
        // Fetch multiple profiles
        let pubkeys = users.map(\.pubkey)
        let profiles = await ndk.fetchProfiles(pubkeys)
        
        XCTAssertEqual(profiles.count, 3)
        XCTAssertEqual(Set(profiles.compactMap(\.name)), Set(["Alice", "Bob", "Charlie"]))
    }
    
    // MARK: - Configuration Tests
    
    func testDebugModeConfiguration() {
        let ndk = createTestNDK()
        
        XCTAssertFalse(ndk.debugMode)
        
        ndk.debugMode = true
        XCTAssertTrue(ndk.debugMode)
    }
    
    func testOutboxConfiguration() {
        let ndk = createTestNDK()
        
        XCTAssertTrue(ndk.outboxEnabled) // Default
        
        ndk.outboxEnabled = false
        XCTAssertFalse(ndk.outboxEnabled)
        
        // Test outbox config
        let config = NDKOutboxConfig()
        ndk.outboxConfig = config
        XCTAssertEqual(ndk.outboxConfig.relaysPerAuthor, config.relaysPerAuthor)
    }
    
    // MARK: - Integration with Other Components Tests
    
    func testSubscriptionTracking() async {
        let ndk = createTestNDK()
        let filter = NDKFilter(kinds: [1])
        
        // Create subscription
        let sub = await ndk.subscribe(filter)
        
        // Should be tracked
        let activeSubscriptions = await ndk.subscriptionTracker.getActiveSubscriptions()
        XCTAssertTrue(activeSubscriptions.contains { $0.id == sub.id })
        
        // Stop subscription
        sub.stop()
        
        // Brief delay for async cleanup
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        // Should no longer be tracked
        let updatedSubscriptions = await ndk.subscriptionTracker.getActiveSubscriptions()
        XCTAssertFalse(updatedSubscriptions.contains { $0.id == sub.id })
    }
    
    func testSignatureVerificationConfig() {
        let ndk = createTestNDK()
        
        let defaultConfig = ndk.signatureVerificationConfig
        XCTAssertEqual(defaultConfig.enabled, NDKSignatureVerificationConfig.default.enabled)
        XCTAssertEqual(defaultConfig.samplingRate, NDKSignatureVerificationConfig.default.samplingRate)
        
        // Create custom config
        let customConfig = NDKSignatureVerificationConfig(
            enabled: false,
            samplingRate: 0.5,
            cacheSize: 1000
        )
        
        let ndkWithCustomConfig = NDK(
            signatureVerificationConfig: customConfig
        )
        
        XCTAssertFalse(ndkWithCustomConfig.signatureVerificationConfig.enabled)
        XCTAssertEqual(ndkWithCustomConfig.signatureVerificationConfig.samplingRate, 0.5)
    }
}