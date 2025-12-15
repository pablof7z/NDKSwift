@testable import NDKSwiftCore
import XCTest

final class NDKTests: NDKTestCase {
    // MARK: - Initialization Tests

    func testInitializationWithDefaults() async throws {
        try await performAsyncTest(timeout: 30) { [self] in
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
    }

    func testInitializationWithParameters() async throws {
        try await performAsyncTest(timeout: 30) { [self] in
            let relayUrls = ["wss://relay1.test", "wss://relay2.test"]
            let signer = try NDKPrivateKeySigner.generate()
            let cache = self.createMemoryCache()

            let ndk = NDK(
                relayURLs: relayUrls,
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
    }

    func testActiveUserUpdatesWithSigner() async throws {
        try await performAsyncTest(timeout: 30) { [self] in
            let ndk = self.createTestNDK()
            let activeUser1 = await ndk.activeUser
            XCTAssertNil(activeUser1)

            let signer = try NDKPrivateKeySigner.generate()
            ndk.signer = signer

            let activeUser2 = await ndk.activeUser
            XCTAssertNotNil(activeUser2)
            let signerPubkey = try await signer.pubkey
            XCTAssertEqual(activeUser2?.pubkey, signerPubkey)
        }
    }

    // MARK: - Relay Management Tests

    func testAddRelay() async throws {
        try await performAsyncTest(timeout: 30) { [self] in
            let ndk = self.createTestNDK()
            let relayUrl = "wss://test.relay"

            let relay = await ndk.addRelay(relayUrl)

            XCTAssertEqual(relay.url, relayUrl)
            let relays = await ndk.relays
            XCTAssertTrue(relays.contains { $0.url == relayUrl })
            XCTAssertEqual(relays.count, 1)
        }
    }

    func testAddDuplicateRelay() async throws {
        try await performAsyncTest(timeout: 30) { [self] in
            let ndk = self.createTestNDK()
            let relayUrl = "wss://test.relay"

            let relay1 = await ndk.addRelay(relayUrl)
            let relay2 = await ndk.addRelay(relayUrl)

            XCTAssertEqual(relay1.url, relay2.url)
            let relays = await ndk.relays
            XCTAssertEqual(relays.count, 1) // Should not duplicate
        }
    }

    func testRemoveRelay() async {
        let ndk = createTestNDK()
        let relayUrl = "wss://test.relay"

        await ndk.addRelay(relayUrl)
        var relays = await ndk.relays
        XCTAssertEqual(relays.count, 1)

        await ndk.removeRelay(relayUrl)
        relays = await ndk.relays
        XCTAssertEqual(relays.count, 0)
    }

    func testRemoveNonExistentRelay() async {
        let ndk = createTestNDK()
        await ndk.addRelay("wss://test1.relay")

        await ndk.removeRelay("wss://nonexistent.relay")
        let relays = await ndk.relays
        XCTAssertEqual(relays.count, 1) // Should not affect existing relays
    }

    // MARK: - Connection Tests

    func testConnectDisconnect() async throws {
        let ndk = createTestNDK(relayURLs: ["wss://mock.relay"])

        // Initially disconnected
        let relays = await ndk.relays
        let initiallyConnected = await withTaskGroup(of: (Int, Bool).self) { group in
            for (index, relay) in relays.enumerated() {
                group.addTask {
                    (index, await relay.isConnected)
                }
            }

            var results = Array(repeating: false, count: relays.count)
            for await(index, isConnected) in group {
                results[index] = isConnected
            }
            return results
        }
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
        let pubkey = try await signer.pubkey
        XCTAssertEqual(event.pubkey, pubkey)
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
        let publishedRelays = try await ndk.publish(event, to: targetRelays)

        // Note: Since we're using mock relays that aren't connected,
        // this will return empty but the API should work
        XCTAssertTrue(publishedRelays.isEmpty || publishedRelays.allSatisfy { targetRelays.contains($0.url) })
    }

    // MARK: - Data Access Tests

    func testObserveCreatesDataSource() {
        let ndk = createTestNDK()
        let filter = NDKFilter(kinds: [1])

        let dataSource = ndk.subscribe(filter: filter)

        XCTAssertNotNil(dataSource)
        // Test passes if data source was created successfully
    }

    func testObserveWithTransform() {
        let ndk = createTestNDK()
        let filter = NDKFilter(kinds: [0])

        let dataSource = ndk.subscribe(
            filter: filter,
            transform: { event -> NDKUserProfile? in
                guard event.kind == 0 else { return nil }
                return try? JSONCoding.decode(NDKUserProfile.self, from: event.content)
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
            EventTestFactory.createEvent(kind: 2, content: "Event 3"),
        ]

        for event in events {
            try await cache.saveEvent(event)
        }

        // Fetch from cache
        let filter = NDKFilter(kinds: [1])
        // Use observe with immediate EOSE to fetch from cache
        var fetchedEvents: [NDKEvent] = []
        let dataSource = ndk.subscribe(filter: filter, maxAge: 0, cachePolicy: .cacheOnly, closeOnEose: true)

        // Collect events
        for await event in dataSource.events {
            fetchedEvents.append(event)
        }

        XCTAssertEqual(fetchedEvents.count, 2)
        XCTAssertTrue(fetchedEvents.allSatisfy { $0.kind == 1 })
    }

    func testFetchEventById() async throws {
        let cache = createMemoryCache()
        let ndk = createTestNDK(cache: cache)

        let event = EventTestFactory.createEvent()
        try await cache.saveEvent(event)

        // Use observe to fetch single event by ID
        let idFilter = NDKFilter(ids: [event.id])
        let dataSource = ndk.subscribe(filter: idFilter, maxAge: 0, cachePolicy: .cacheOnly, closeOnEose: true)

        var fetchedEvent: NDKEvent? = nil
        for await event in dataSource.events {
            fetchedEvent = event
            break
        }

        XCTAssertNotNil(fetchedEvent)
        XCTAssertEqual(fetchedEvent?.id, event.id)
    }

    func testFetchEventByFilter() async throws {
        let cache = createMemoryCache()
        let ndk = createTestNDK(cache: cache)

        let event = EventTestFactory.createEvent(kind: 30023)
        try await cache.saveEvent(event)

        let filter = NDKFilter(kinds: [30023], limit: 1)
        // Use observe to fetch single event by filter
        let dataSource = ndk.subscribe(filter: filter, maxAge: 0, cachePolicy: .cacheOnly, closeOnEose: true)

        var fetchedEvent: NDKEvent? = nil
        for await event in dataSource.events {
            fetchedEvent = event
            break
        }

        XCTAssertNotNil(fetchedEvent)
        XCTAssertEqual(fetchedEvent?.kind, 30023)
    }

    // MARK: - User Management Tests

    func testGetUserFromNpub() throws {
        let ndk = createTestNDK()
        let npub = "npub1w0zv839p6nz2wnfp8u5fqdqzs9d9pdhg3znye9ej63wh27h73gns6h9nkx"

        let user = ndk.getUser(npub: npub)

        XCTAssertNotNil(user)
        XCTAssertEqual(user?.npub, npub)
        XCTAssertFalse(user?.pubkey.isEmpty ?? true)
    }

    func testGetUserFromPubkey() {
        let ndk = createTestNDK()
        let pubkey = TestFixtures.Keys.alice.publicKey

        let user = ndk.getUser(pubkey)

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
        // Use observe to fetch profile
        let profileFilter = NDKFilter(authors: [TestFixtures.Keys.alice.publicKey], kinds: [0], limit: 1)
        let dataSource = ndk.subscribe(filter: profileFilter, maxAge: 0, cachePolicy: .cacheOnly, closeOnEose: true)

        var profile: NDKUserProfile? = nil
        for await event in dataSource.events {
            if event.kind == 0 {
                profile = try? JSONCoding.decode(NDKUserProfile.self, from: event.content)
                break
            }
        }

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
            (pubkey: TestFixtures.Keys.charlie.publicKey, name: "Charlie"),
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
        // Use observe to fetch multiple profiles
        let profilesFilter = NDKFilter(authors: pubkeys, kinds: [0])
        let dataSource = ndk.subscribe(filter: profilesFilter, maxAge: 0, cachePolicy: .cacheOnly, closeOnEose: true)

        var profiles: [NDKUserProfile] = []
        for await event in dataSource.events {
            if event.kind == 0,
               let profile = try? JSONCoding.decode(NDKUserProfile.self, from: event.content)
            {
                profiles.append(profile)
            }
        }

        XCTAssertEqual(profiles.count, 3)
        XCTAssertEqual(Set(profiles.compactMap { $0.name }), Set(["Alice", "Bob", "Charlie"]))
    }

    // MARK: - Configuration Tests

    func testDebugModeConfiguration() {
        // Test default value
        let ndkDefault = createTestNDK()
        XCTAssertFalse(ndkDefault.debugMode)

        // Test initialized with debugMode: true
        let ndkDebug = NDK(debugMode: true)
        XCTAssertTrue(ndkDebug.debugMode)
    }

    func testOutboxConfiguration() {
        // Test default value
        let ndkDefault = createTestNDK()
        XCTAssertTrue(ndkDefault.outboxEnabled) // Default

        // Test initialized with outboxEnabled: false
        let ndkNoOutbox = NDK(outboxEnabled: false)
        XCTAssertFalse(ndkNoOutbox.outboxEnabled)

        // Test outbox config via initializer
        let outboxRelays = Set(["wss://outbox1.test", "wss://outbox2.test"])
        let config = NDKOutboxConfig(outboxRelays: outboxRelays)
        let ndkWithConfig = NDK(outboxConfig: config)
        XCTAssertEqual(ndkWithConfig.outboxConfig.outboxRelays, outboxRelays)
    }

    // MARK: - Integration with Other Components Tests

    func testSubscriptionTracking() async {
        let ndk = createTestNDK()
        let filter = NDKFilter(kinds: [1])

        // Create data source (modern subscription approach)
        let dataSource = ndk.subscribe(filter: filter)

        // Verify data source is created
        XCTAssertNotNil(dataSource)

        // Cancel the data source to stop observing
        // (DataSource automatically manages lifecycle)
    }

    func testSignatureVerificationConfig() {
        let ndk = createTestNDK()

        let defaultConfig = ndk.signatureVerificationConfig
        XCTAssertEqual(defaultConfig.initialValidationRatio, NDKSignatureVerificationConfig.default.initialValidationRatio)
        XCTAssertEqual(defaultConfig.lowestValidationRatio, NDKSignatureVerificationConfig.default.lowestValidationRatio)

        // Create custom config
        let customConfig = NDKSignatureVerificationConfig(
            initialValidationRatio: 0.5,
            lowestValidationRatio: 0.1,
            autoBlacklistInvalidRelays: false,
            validationRatioFunction: nil
        )

        let ndkWithCustomConfig = NDK(
            signatureVerificationConfig: customConfig
        )

        XCTAssertEqual(ndkWithCustomConfig.signatureVerificationConfig.initialValidationRatio, 0.5)
        XCTAssertEqual(ndkWithCustomConfig.signatureVerificationConfig.lowestValidationRatio, 0.1)
    }
}
