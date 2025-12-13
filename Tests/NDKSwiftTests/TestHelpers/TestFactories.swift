import Foundation
@testable import NDKSwiftCore

// MARK: - NDK Factory

enum NDKTestFactory {
    /// Creates a test NDK instance with optional configuration
    static func createNDK(
        relayUrls: [RelayURL] = [],
        signer: NDKSigner? = nil,
        cache: NDKCache? = MemoryCache(),
        debugMode: Bool = false,
        outboxEnabled: Bool = false
    ) -> NDK {
        let ndk = NDK(
            relayUrls: relayUrls,
            signer: signer,
            cache: cache
        )
        ndk.debugMode = debugMode
        ndk.outboxEnabled = outboxEnabled
        return ndk
    }

    /// Creates an authenticated NDK instance with a generated signer
    static func createAuthenticatedNDK(
        relayUrls: [RelayURL] = [],
        cache: NDKCache? = MemoryCache()
    ) throws -> (ndk: NDK, signer: NDKSigner) {
        let signer = try NDKPrivateKeySigner.generate()
        let ndk = createNDK(relayUrls: relayUrls, signer: signer, cache: cache)
        return (ndk, signer)
    }

    /// Creates a connected NDK instance with test relays
    static func createConnectedNDK(
        useTestRelays: Bool = true,
        signer: NDKSigner? = nil,
        cache: NDKCache? = MemoryCache()
    ) async throws -> NDK {
        let relayUrls = useTestRelays ? RelayConstants.testRelays : []
        let ndk = createNDK(relayUrls: relayUrls, signer: signer, cache: cache)
        await ndk.connect()

        // Wait for connections
        _ = await ndk.waitForRelayConnections(minimumRelays: 1, timeout: 10.0)

        return ndk
    }

    /// Creates a connected, authenticated NDK with a generated signer
    static func createConnectedAuthenticatedNDK(
        useTestRelays: Bool = true,
        cache: NDKCache? = MemoryCache()
    ) async throws -> (ndk: NDK, signer: NDKSigner) {
        let (ndk, signer) = try createAuthenticatedNDK(relayUrls: useTestRelays ? RelayConstants.testRelays : [], cache: cache)
        await ndk.connect()
        _ = await ndk.waitForRelayConnections(minimumRelays: 1, timeout: 10.0)
        return (ndk, signer)
    }
}

// MARK: - Event Factory

enum EventTestFactory {
    /// Creates a test event with sensible defaults
    static func createEvent(
        kind: Kind = 1,
        content: String = "Test event",
        tags: [Tag] = [],
        pubkey: String? = nil,
        createdAt: Timestamp? = nil,
        id: EventID? = nil,
        sig: String? = nil
    ) -> NDKEvent {
        let actualPubkey = pubkey ?? generateTestPubkey()
        let actualCreatedAt = createdAt ?? Timestamp.now
        let actualId = id ?? generateEventId()
        let actualSig = sig ?? generateTestSignature()

        return NDKEvent(
            id: actualId,
            pubkey: actualPubkey,
            createdAt: actualCreatedAt,
            kind: kind,
            tags: tags,
            content: content,
            sig: actualSig
        )
    }

    /// Creates a signed event using NDKEventBuilder
    static func createSignedEvent(
        ndk: NDK,
        kind: Kind = 1,
        content: String = "Test event",
        tags: [Tag] = [],
        signer: NDKSigner? = nil
    ) async throws -> NDKEvent {
        let builder = NDKEventBuilder(ndk: ndk)
            .kind(kind)
            .content(content)

        for tag in tags {
            builder.tag(tag)
        }

        return try await builder.build(signer: signer)
    }

    /// Creates a text note (kind 1)
    static func createTextNote(
        content: String = "Test note",
        pubkey: String? = nil,
        tags: [Tag] = []
    ) -> NDKEvent {
        return createEvent(kind: 1, content: content, tags: tags, pubkey: pubkey)
    }

    /// Creates a metadata event (kind 0)
    static func createMetadataEvent(
        name: String = "Test User",
        about: String = "Test user description",
        picture: String = "https://example.com/pic.jpg",
        pubkey: String? = nil
    ) -> NDKEvent {
        let metadata = [
            "name": name,
            "about": about,
            "picture": picture,
        ]
        let content = try! JSONCoding.encodeToString(metadata)
        return createEvent(kind: 0, content: content, pubkey: pubkey)
    }

    /// Creates a contact list event (kind 3)
    static func createContactListEvent(
        contacts: [String] = [],
        pubkey: String? = nil
    ) -> NDKEvent {
        let tags = contacts.map { [NostrConstants.TagName.pubkey, $0] }
        return createEvent(kind: 3, content: "", tags: tags, pubkey: pubkey)
    }

    /// Creates a deletion event (kind 5)
    static func createDeletionEvent(
        eventIds: [EventID],
        reason: String = "Test deletion",
        pubkey: String? = nil
    ) -> NDKEvent {
        let tags = eventIds.map { [NostrConstants.TagName.event, $0] }
        return createEvent(kind: 5, content: reason, tags: tags, pubkey: pubkey)
    }

    /// Creates a repost event (kind 6)
    static func createRepostEvent(
        event: NDKEvent,
        pubkey: String? = nil
    ) -> NDKEvent {
        let tags = [
            [NostrConstants.TagName.event, event.id],
            [NostrConstants.TagName.pubkey, event.pubkey],
        ]
        let content = try! JSONCoding.encodeToString(event)
        return createEvent(kind: 6, content: content, tags: tags, pubkey: pubkey)
    }

    /// Creates a reaction event (kind 7)
    static func createReactionEvent(
        to event: NDKEvent,
        content: String = "+",
        pubkey: String? = nil
    ) -> NDKEvent {
        let tags = [
            [NostrConstants.TagName.event, event.id],
            [NostrConstants.TagName.pubkey, event.pubkey],
        ]
        return createEvent(kind: 7, content: content, tags: tags, pubkey: pubkey)
    }

    // MARK: - Helpers

    private static func generateTestPubkey() -> String {
        return try! generateRandomHex(32)
    }

    private static func generateEventId() -> EventID {
        return try! generateRandomHex(32)
    }

    private static func generateTestSignature() -> String {
        return try! generateRandomHex(64)
    }
}

// MARK: - Filter Factory

enum FilterTestFactory {
    /// Creates a basic filter
    static func createFilter(
        ids: [EventID]? = nil,
        authors: [PublicKey]? = nil,
        kinds: [Kind]? = nil,
        tags: [String: [String]]? = nil,
        since: Timestamp? = nil,
        until: Timestamp? = nil,
        limit: Int? = nil
    ) -> NDKFilter {
        var tagsDict: [String: Set<String>]? = nil
        if let tags = tags {
            tagsDict = [:]
            for (key, values) in tags {
                tagsDict![key] = Set(values)
            }
        }

        return NDKFilter(
            ids: ids,
            authors: authors,
            kinds: kinds,
            since: since,
            until: until,
            limit: limit,
            tags: tagsDict
        )
    }

    /// Creates a filter for text notes
    static func createTextNoteFilter(
        authors: [PublicKey]? = nil,
        since: Timestamp? = nil,
        limit: Int = 20
    ) -> NDKFilter {
        return createFilter(
            authors: authors,
            kinds: [1],
            since: since,
            limit: limit
        )
    }

    /// Creates a filter for user metadata
    static func createMetadataFilter(
        pubkeys: [PublicKey],
        since: Timestamp? = nil
    ) -> NDKFilter {
        return createFilter(
            authors: pubkeys,
            kinds: [0],
            since: since,
            limit: pubkeys.count
        )
    }

    /// Creates a filter for replies to an event
    static func createReplyFilter(
        to eventId: EventID,
        since: Timestamp? = nil,
        limit: Int = 50
    ) -> NDKFilter {
        return createFilter(
            kinds: [1],
            tags: [NostrConstants.TagName.event: [eventId]],
            since: since,
            limit: limit
        )
    }
}

// MARK: - User Factory

enum UserTestFactory {
    /// Creates a test user with signer
    static func createUser(name: String? = nil) async throws -> TestUser {
        let signer = try NDKPrivateKeySigner.generate()
        let pubkey = try await signer.pubkey

        var user = TestUser(signer: signer, pubkey: pubkey)

        // Optionally set a name
        if let name = name {
            user.name = name
        }

        return user
    }

    /// Creates multiple test users
    static func createUsers(count: Int) async throws -> [TestUser] {
        var users: [TestUser] = []
        for i in 0 ..< count {
            let user = try await createUser(name: "Test User \(i + 1)")
            users.append(user)
        }
        return users
    }
}

// MARK: - Relay Factory

enum RelayTestFactory {
    /// Creates a mock relay
    static func createMockRelay(
        url: String = "wss://mock.relay.test",
        shouldFailPublish: Bool = false,
        publishDelay: TimeInterval = 0
    ) -> MockRelay {
        let relay = MockRelay(url: url)
        relay.shouldFailPublish = shouldFailPublish
        relay.publishDelay = publishDelay
        return relay
    }

    /// Creates multiple mock relays
    static func createMockRelays(count: Int) -> [MockRelay] {
        return (0 ..< count).map { i in
            createMockRelay(url: "wss://mock\(i).relay.test")
        }
    }
}

// MARK: - Extended Test User

extension TestUser {
    var name: String? {
        get { _name }
        set { _name = newValue }
    }

    private var _name: String? {
        get {
            objc_getAssociatedObject(self, &nameKey) as? String
        }
        set {
            objc_setAssociatedObject(self, &nameKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
}

private var nameKey: UInt8 = 0
