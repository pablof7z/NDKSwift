@testable import NDKSwiftCore
import XCTest

final class NIP89Tests: XCTestCase {
    // MARK: - Client Tag Tests

    func testClientTagBuilder() async throws {
        let ndk = try await NDKTestFactory.createNDK()
        let builder = NDKEventBuilder(ndk: ndk)

        _ = builder
            .content("Hello, world!")
            .clientTag(name: "TestClient", address: "31990:abc123:test", relay: "wss://relay.test")

        XCTAssertEqual(builder.tags.count, 1)
        XCTAssertEqual(builder.tags.first, ["client", "TestClient", "31990:abc123:test", "wss://relay.test"])
    }

    func testClientTagBuilderWithoutRelay() async throws {
        let ndk = try await NDKTestFactory.createNDK()
        let builder = NDKEventBuilder(ndk: ndk)

        _ = builder
            .content("Hello, world!")
            .clientTag(name: "TestClient", address: "31990:abc123:test")

        XCTAssertEqual(builder.tags.count, 1)
        XCTAssertEqual(builder.tags.first, ["client", "TestClient", "31990:abc123:test"])
    }

    func testClientTagBuilderWithoutAddress() async throws {
        let ndk = try await NDKTestFactory.createNDK()
        let builder = NDKEventBuilder(ndk: ndk)

        _ = builder
            .content("Hello, world!")
            .clientTag(name: "TestClient")

        XCTAssertEqual(builder.tags.count, 1)
        XCTAssertEqual(builder.tags.first, ["client", "TestClient"])
    }

    func testClientTagBuilderWithoutAddressButWithRelay() async throws {
        let ndk = try await NDKTestFactory.createNDK()
        let builder = NDKEventBuilder(ndk: ndk)

        _ = builder
            .content("Hello, world!")
            .clientTag(name: "TestClient", relay: "wss://relay.test")

        XCTAssertEqual(builder.tags.count, 1)
        XCTAssertEqual(builder.tags.first, ["client", "TestClient", "", "wss://relay.test"])
    }

    func testEventClientTagExtraction() async throws {
        let event = NDKEvent(
            id: "test_id",
            pubkey: "test_pubkey",
            createdAt: 1_234_567_890,
            kind: 1,
            tags: [
                ["client", "TestClient", "31990:abc123:test", "wss://relay.test"],
                ["p", "somepubkey"],
            ],
            content: "Hello, world!",
            sig: "test_sig"
        )

        let clientTag = event.clientTag
        XCTAssertNotNil(clientTag)
        XCTAssertEqual(clientTag?.name, "TestClient")
        XCTAssertEqual(clientTag?.address, "31990:abc123:test")
        XCTAssertEqual(clientTag?.relay, "wss://relay.test")
    }

    func testEventClientTagExtractionWithoutRelay() async throws {
        let event = NDKEvent(
            id: "test_id",
            pubkey: "test_pubkey",
            createdAt: 1_234_567_890,
            kind: 1,
            tags: [
                ["client", "TestClient", "31990:abc123:test"],
                ["p", "somepubkey"],
            ],
            content: "Hello, world!",
            sig: "test_sig"
        )

        let clientTag = event.clientTag
        XCTAssertNotNil(clientTag)
        XCTAssertEqual(clientTag?.name, "TestClient")
        XCTAssertEqual(clientTag?.address, "31990:abc123:test")
        XCTAssertNil(clientTag?.relay)
    }

    func testEventClientTagExtractionWithoutAddress() async throws {
        let event = NDKEvent(
            id: "test_id",
            pubkey: "test_pubkey",
            createdAt: 1_234_567_890,
            kind: 1,
            tags: [
                ["client", "TestClient"],
                ["p", "somepubkey"],
            ],
            content: "Hello, world!",
            sig: "test_sig"
        )

        let clientTag = event.clientTag
        XCTAssertNotNil(clientTag)
        XCTAssertEqual(clientTag?.name, "TestClient")
        XCTAssertNil(clientTag?.address)
        XCTAssertNil(clientTag?.relay)
    }

    func testEventWithoutClientTag() async throws {
        let event = NDKEvent(
            id: "test_id",
            pubkey: "test_pubkey",
            createdAt: 1_234_567_890,
            kind: 1,
            tags: [
                ["p", "somepubkey"],
            ],
            content: "Hello, world!",
            sig: "test_sig"
        )

        let clientTag = event.clientTag
        XCTAssertNil(clientTag)
    }

    // MARK: - Handler Information Tests

    func testHandlerInfoBuilder() async throws {
        let ndk = try await NDKTestFactory.createNDK()
        let builder = NDKEventBuilder(ndk: ndk)

        let metadata = NIP89HandlerMetadata(
            name: "Test Handler",
            about: "A test handler",
            picture: "https://example.com/icon.png",
            website: "https://example.com",
            lud16: "test@example.com"
        )

        _ = builder.nip89HandlerInfo(
            identifier: "test-handler",
            supportedKinds: [1, 6, 7],
            handlerURLs: [
                "web": "https://example.com/e/<bech32>",
                "ios": "testapp://e/<bech32>",
            ],
            metadata: metadata
        )

        XCTAssertEqual(builder.kind, 31990)
        XCTAssertTrue(builder.tags.contains(["d", "test-handler"]))
        XCTAssertTrue(builder.tags.contains(["k", "1"]))
        XCTAssertTrue(builder.tags.contains(["k", "6"]))
        XCTAssertTrue(builder.tags.contains(["k", "7"]))
        XCTAssertTrue(builder.tags.contains(["web", "https://example.com/e/<bech32>", "nevent"]))
        XCTAssertTrue(builder.tags.contains(["ios", "testapp://e/<bech32>"]))
        XCTAssertFalse(builder.content.isEmpty)
    }

    func testHandlerInfoEventParsing() async throws {
        let event = NDKEvent(
            id: "test_id",
            pubkey: "test_pubkey",
            createdAt: 1_234_567_890,
            kind: 31990,
            tags: [
                ["d", "test-handler"],
                ["k", "1"],
                ["k", "6"],
                ["k", "7"],
                ["web", "https://example.com/e/<bech32>", "nevent"],
                ["ios", "testapp://e/<bech32>"],
            ],
            content: #"{"name":"Test Handler","about":"A test handler"}"#,
            sig: "test_sig"
        )

        let handlerInfo = event.asNIP89HandlerInfo()
        XCTAssertNotNil(handlerInfo)
        XCTAssertEqual(handlerInfo?.identifier, "test-handler")
        XCTAssertEqual(handlerInfo?.supportedKinds, [1, 6, 7])
        XCTAssertEqual(handlerInfo?.handlerURLs["web"], "https://example.com/e/<bech32>")
        XCTAssertEqual(handlerInfo?.handlerURLs["ios"], "testapp://e/<bech32>")
        XCTAssertEqual(handlerInfo?.metadata?.name, "Test Handler")
        XCTAssertEqual(handlerInfo?.metadata?.about, "A test handler")
    }

    // MARK: - Recommendation Tests

    func testRecommendationBuilder() async throws {
        let ndk = try await NDKTestFactory.createNDK()
        let builder = NDKEventBuilder(ndk: ndk)

        let handlers = [
            NIP89HandlerReference(
                address: "31990:abc123:handler1",
                relay: "wss://relay1.test",
                platform: "web"
            ),
            NIP89HandlerReference(
                address: "31990:def456:handler2",
                relay: "wss://relay2.test",
                platform: "ios"
            ),
        ]

        _ = builder.nip89Recommendation(
            eventKind: 1,
            handlers: handlers
        )

        XCTAssertEqual(builder.kind, 31989)
        XCTAssertTrue(builder.tags.contains(["d", "1"]))
        XCTAssertTrue(builder.tags.contains(["a", "31990:abc123:handler1", "wss://relay1.test", "web"]))
        XCTAssertTrue(builder.tags.contains(["a", "31990:def456:handler2", "wss://relay2.test", "ios"]))
    }

    func testRecommendationEventParsing() async throws {
        let event = NDKEvent(
            id: "test_id",
            pubkey: "test_pubkey",
            createdAt: 1_234_567_890,
            kind: 31989,
            tags: [
                ["d", "1"],
                ["a", "31990:abc123:handler1", "wss://relay1.test", "web"],
                ["a", "31990:def456:handler2", "wss://relay2.test", "ios"],
            ],
            content: "",
            sig: "test_sig"
        )

        let recommendation = event.asNIP89Recommendation()
        XCTAssertNotNil(recommendation)
        XCTAssertEqual(recommendation?.eventKind, 1)
        XCTAssertEqual(recommendation?.handlers.count, 2)

        let handler1 = recommendation?.handlers.first { $0.address == "31990:abc123:handler1" }
        XCTAssertNotNil(handler1)
        XCTAssertEqual(handler1?.relay, "wss://relay1.test")
        XCTAssertEqual(handler1?.platform, "web")

        let handler2 = recommendation?.handlers.first { $0.address == "31990:def456:handler2" }
        XCTAssertNotNil(handler2)
        XCTAssertEqual(handler2?.relay, "wss://relay2.test")
        XCTAssertEqual(handler2?.platform, "ios")
    }

    // MARK: - Automatic Client Tagging Tests

    func testAutomaticClientTagging() async throws {
        let signer = try NDKPrivateKeySigner(privateKey: "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef")
        let ndk = NDK(
            cache: try await NDKTestFactory.createTestCache(),
            clientTagConfig: NDKClientTagConfig(
                name: "TestClient",
                address: "31990:abc123:test",
                relay: "wss://relay.test",
                autoTag: true,
                excludedKinds: [4] // Exclude DMs
            )
        )

        // Test that client tag is automatically added
        let event1 = try await NDKEventBuilder(ndk: ndk)
            .content("Hello, world!")
            .kind(1)
            .build(signer: signer)

        XCTAssertNotNil(event1.clientTag)
        XCTAssertEqual(event1.clientTag?.name, "TestClient")
        XCTAssertEqual(event1.clientTag?.address, "31990:abc123:test")
        XCTAssertEqual(event1.clientTag?.relay, "wss://relay.test")

        // Test that excluded kinds don't get client tags
        let event2 = try await NDKEventBuilder(ndk: ndk)
            .content("Secret message")
            .kind(4)
            .build(signer: signer)

        XCTAssertNil(event2.clientTag)
    }

    func testDisabledAutomaticClientTagging() async throws {
        let signer = try NDKPrivateKeySigner(privateKey: "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef")
        let ndk = NDK(
            cache: try await NDKTestFactory.createTestCache(),
            clientTagConfig: NDKClientTagConfig(
                name: "TestClient",
                address: "31990:abc123:test",
                relay: "wss://relay.test",
                autoTag: false
            )
        )

        // Test that client tag is not automatically added
        let event = try await NDKEventBuilder(ndk: ndk)
            .content("Hello, world!")
            .kind(1)
            .build(signer: signer)

        XCTAssertNil(event.clientTag)
    }

    func testManualClientTagOverridesAutomatic() async throws {
        let signer = try NDKPrivateKeySigner(privateKey: "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef")
        let ndk = NDK(
            cache: try await NDKTestFactory.createTestCache(),
            clientTagConfig: NDKClientTagConfig(
                name: "TestClient",
                address: "31990:abc123:test",
                relay: "wss://relay.test",
                autoTag: true
            )
        )

        // Test that manual client tag overrides automatic one
        let event = try await NDKEventBuilder(ndk: ndk)
            .content("Hello, world!")
            .kind(1)
            .clientTag(name: "ManualClient", address: "31990:manual:test")
            .build(signer: signer)

        XCTAssertNotNil(event.clientTag)
        XCTAssertEqual(event.clientTag?.name, "ManualClient")
        XCTAssertEqual(event.clientTag?.address, "31990:manual:test")
        XCTAssertNil(event.clientTag?.relay)
    }

    func testAutomaticClientTaggingWithoutAddress() async throws {
        let signer = try NDKPrivateKeySigner(privateKey: "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef")
        let ndk = NDK(
            cache: try await NDKTestFactory.createTestCache(),
            clientTagConfig: NDKClientTagConfig(
                name: "TestClient",
                relay: "wss://relay.test",
                autoTag: true
            )
        )

        // Test that client tag is automatically added
        let event = try await NDKEventBuilder(ndk: ndk)
            .content("Hello, world!")
            .kind(1)
            .build(signer: signer)

        XCTAssertNotNil(event.clientTag)
        XCTAssertEqual(event.clientTag?.name, "TestClient")
        XCTAssertNil(event.clientTag?.address)
        XCTAssertEqual(event.clientTag?.relay, "wss://relay.test")
    }
}
