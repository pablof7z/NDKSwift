import XCTest
@testable import NDKSwift

final class NDKFollowPackTests: XCTestCase {
    var ndk: NDK!
    var signer: NDKPrivateKeySigner!
    
    override func setUp() async throws {
        ndk = NDK()
        // Use a valid 64-character hex string for the private key
        signer = try NDKPrivateKeySigner(privateKey: "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef")
        ndk.signer = signer
    }
    
    override func tearDown() async throws {
        ndk = nil
        signer = nil
    }
    
    // Helper to create a test event
    private func createTestEvent(kind: Kind = EventKind.followPack, tags: [Tag] = [], content: String = "") -> NDKEvent {
        // Use a fixed test pubkey instead of trying to get it from signer
        let testPubkey = "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
        return NDKEvent(
            id: "test_id_32bytes_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            pubkey: testPubkey,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: kind,
            tags: tags,
            content: content,
            sig: "test_signature_64bytes_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        )
    }
    
    // MARK: - Kind Handling Tests
    
    func testDefaultKind() async throws {
        let followPack = try await NDKFollowPackBuilder(ndk: ndk).build()
        XCTAssertEqual(followPack.event.kind, EventKind.followPack)
        XCTAssertEqual(followPack.event.kind, 39089)
    }
    
    func testSupportedKinds() throws {
        XCTAssertTrue(NDKFollowPack.supportedKinds.contains(EventKind.followPack))
        XCTAssertTrue(NDKFollowPack.supportedKinds.contains(EventKind.mediaFollowPack))
        XCTAssertEqual(NDKFollowPack.supportedKinds.count, 2)
    }
    
    func testMediaFollowPackKind() async throws {
        let followPack = try await NDKFollowPackBuilder(ndk: ndk)
            .kind(EventKind.mediaFollowPack)
            .build()
        XCTAssertEqual(followPack.event.kind, 39092)
    }
    
    // MARK: - Property Tests
    
    func testTitleGetterSetter() async throws {
        let followPack = try await NDKFollowPackBuilder(ndk: ndk)
            .title("Test Title")
            .build()
        
        XCTAssertEqual(followPack.title, "Test Title")
        XCTAssertTrue(followPack.event.tags.contains(["title", "Test Title"]))
    }
    
    func testDescriptionGetterSetter() async throws {
        let followPack = try await NDKFollowPackBuilder(ndk: ndk)
            .description("A follow pack description")
            .build()
        
        XCTAssertEqual(followPack.description, "A follow pack description")
        XCTAssertTrue(followPack.event.tags.contains(["description", "A follow pack description"]))
    }
    
    func testIdentifierGetterSetter() async throws {
        let followPack = try await NDKFollowPackBuilder(ndk: ndk)
            .identifier("identifier-123")
            .build()
        
        XCTAssertEqual(followPack.identifier, "identifier-123")
        XCTAssertTrue(followPack.event.tags.contains(["d", "identifier-123"]))
    }
    
    // MARK: - Image Tests
    
    func testImageWithStringURL() async throws {
        let imageURL = "https://example.com/image.png"
        let followPack = try await NDKFollowPackBuilder(ndk: ndk)
            .image(imageURL)
            .build()
        
        XCTAssertEqual(followPack.image, imageURL)
        XCTAssertTrue(followPack.event.tags.contains(["image", imageURL]))
    }
    
    func testImageWithImetaTag() async throws {
        let imeta = NDKImetaTag(
            url: "https://example.com/image.png",
            dim: "100x100",
            alt: "Example image"
        )
        
        let followPack = try await NDKFollowPackBuilder(ndk: ndk)
            .image(imeta)
            .build()
        
        // Should set both imeta and image tags
        XCTAssertEqual(followPack.image, imeta.url)
        XCTAssertTrue(followPack.event.tags.contains(where: { $0.first == "imeta" }))
        XCTAssertTrue(followPack.event.tags.contains(["image", imeta.url!]))
    }
    
    func testImagePreferenceImetaOverImageTag() throws {
        let imetaURL = "https://example.com/image.png"
        let imeta = NDKImetaTag(url: imetaURL)
        
        // Create event with both image and imeta tags
        let event = createTestEvent(tags: [
            ["image", "https://fallback.com/image.png"],
            ImetaUtils.imetaTagToTag(imeta)
        ])
        
        let followPack = NDKFollowPack(event: event, ndk: ndk)
        
        // Should prefer imeta URL
        XCTAssertEqual(followPack.image, imetaURL)
    }
    
    func testImageRemoval() async throws {
        // Test that we can create a follow pack without an image
        let followPack = try await NDKFollowPackBuilder(ndk: ndk)
            .title("No Image Pack")
            .build()
        
        XCTAssertNil(followPack.image)
        XCTAssertFalse(followPack.event.tags.contains(where: { $0.first == "imeta" }))
        XCTAssertFalse(followPack.event.tags.contains(where: { $0.first == "image" }))
    }
    
    // MARK: - Pubkey Management Tests
    
    func testPubkeysGetterSetter() async throws {
        let pubkeys = ["pk1", "pk2", "pk3"]
        let followPack = try await NDKFollowPackBuilder(ndk: ndk)
            .pubkeys(pubkeys)
            .build()
        
        XCTAssertEqual(followPack.pubkeys, pubkeys)
        XCTAssertEqual(followPack.event.tags.filter { $0.first == "p" }.count, 3)
    }
    
    func testAddPubkey() async throws {
        let followPack = try await NDKFollowPackBuilder(ndk: ndk)
            .addPubkey("pk1")
            .addPubkey("pk2")
            .build()
        
        XCTAssertEqual(followPack.pubkeys, ["pk1", "pk2"])
    }
    
    func testContainsPubkeyFromBuilder() async throws {
        let followPack = try await NDKFollowPackBuilder(ndk: ndk)
            .pubkeys(["pk1", "pk2", "pk3"])
            .build()
        
        XCTAssertTrue(followPack.containsPubkey("pk1"))
        XCTAssertTrue(followPack.containsPubkey("pk2"))
        XCTAssertTrue(followPack.containsPubkey("pk3"))
        XCTAssertFalse(followPack.containsPubkey("pk4"))
    }
    
    func testContainsPubkey() throws {
        let event = createTestEvent(tags: [
            ["p", "pk1"],
            ["p", "pk2"]
        ])
        let followPack = NDKFollowPack(event: event, ndk: ndk)
        
        XCTAssertTrue(followPack.containsPubkey("pk1"))
        XCTAssertTrue(followPack.containsPubkey("pk2"))
        XCTAssertFalse(followPack.containsPubkey("pk3"))
    }
    
    // MARK: - Conversion Tests
    
    func testBuilderCreatesCorrectEvent() async throws {
        let followPack = try await NDKFollowPackBuilder(ndk: ndk)
            .kind(EventKind.followPack)
            .title("My Follow Pack")
            .description("A test follow pack")
            .identifier("test-pack")
            .pubkeys(["pk1", "pk2"])
            .content("Some content")
            .build()
        
        XCTAssertEqual(followPack.event.kind, EventKind.followPack)
        XCTAssertEqual(followPack.event.content, "Some content")
        XCTAssertTrue(followPack.event.tags.contains(["title", "My Follow Pack"]))
        XCTAssertTrue(followPack.event.tags.contains(["description", "A test follow pack"]))
        XCTAssertTrue(followPack.event.tags.contains(["d", "test-pack"]))
        XCTAssertTrue(followPack.event.tags.contains(["p", "pk1"]))
        XCTAssertTrue(followPack.event.tags.contains(["p", "pk2"]))
    }
    
    func testFromEvent() throws {
        let event = createTestEvent(
            kind: EventKind.mediaFollowPack,
            tags: [
                ["title", "Media Pack"],
                ["description", "Media follow pack"],
                ["d", "media-123"],
                ["p", "pk1"],
                ["p", "pk2"],
                ["image", "https://example.com/media.jpg"]
            ],
            content: "Media content"
        )
        
        let followPack = NDKFollowPack.from(event: event, ndk: ndk)
        
        XCTAssertEqual(followPack.event.kind, EventKind.mediaFollowPack)
        XCTAssertEqual(followPack.title, "Media Pack")
        XCTAssertEqual(followPack.description, "Media follow pack")
        XCTAssertEqual(followPack.identifier, "media-123")
        XCTAssertEqual(followPack.pubkeys, ["pk1", "pk2"])
        XCTAssertEqual(followPack.image, "https://example.com/media.jpg")
        XCTAssertEqual(followPack.event.content, "Media content")
    }
    
    // MARK: - Edge Cases
    
    func testMalformedTags() throws {
        let event = createTestEvent(tags: [
            ["p"],  // Missing pubkey
            ["title"],  // Missing value
            ["imeta"],  // Missing value
            ["p", ""],  // Empty pubkey
        ])
        
        let followPack = NDKFollowPack(event: event, ndk: ndk)
        
        // Getters should handle gracefully
        XCTAssertEqual(followPack.pubkeys, [""])  // Empty string is still returned
        XCTAssertNil(followPack.title)
        XCTAssertNil(followPack.image)
    }
    
    func testDuplicateTagRemoval() async throws {
        // Builder handles duplicate removal
        let builder = NDKFollowPackBuilder(ndk: ndk)
            .title("First")
            .title("Second")  // This should replace the first
        
        let followPack = try await builder.build()
        
        // Should only have one title tag
        let titleTags = followPack.event.tags.filter { $0.first == "title" }
        XCTAssertEqual(titleTags.count, 1)
        XCTAssertEqual(followPack.title, "Second")
    }
    
    // MARK: - Publishing Tests
    
    func testPublishWithBuilder() async throws {
        throw XCTSkip("Test needs to be updated for current API: relayPool property no longer exists, need different way to mock relay connections")
    }
    
    // MARK: - Observation Tests
    
    func testObserveFollowPacks() async throws {
        // Use observe to get follow packs
        let filter = NDKFilter(kinds: NDKFollowPack.supportedKinds)
        let observer = ndk.observe(filter: filter)
        
        // Verify the observer pattern works
        XCTAssertNotNil(observer)
        
        // Note: In a real test, you'd mock the relay to return test events
        // with appropriate kind values (EventKind.followPack, EventKind.mediaFollowPack)
        // and verify the observer properly filters and returns them
    }
    
}

// MARK: - Mock Relay for Testing

class FollowPackMockRelay: RelayProtocol, @unchecked Sendable {
    let url: String = "wss://mock.relay"
    var connectionState: NDKRelayConnectionState { .connected }
    var ndk: NDK?
    var activeSubscriptionIds: [String] { [] }
    
    func connect() async {}
    func disconnect() async {}
    func send(_ message: String) async throws {}
    func addSubscriptionId(_ subscriptionId: String) async {}
    func removeSubscription(byId id: String) async {}
    func getSignatureStats() async -> NDKRelaySignatureStats { NDKRelaySignatureStats() }
    func updateSignatureStats(_ updater: @Sendable (inout NDKRelaySignatureStats) -> Void) async {}
    func observeConnectionState(_ observer: @escaping @Sendable (NDKRelayConnectionState) -> Void) async {}
    func publish(_ event: NDKEvent) async throws -> (success: Bool, message: String?) {
        return (true, nil)
    }
}