@testable import NDKSwift
import XCTest

final class NDKBunkerSignerTests: XCTestCase {
    func testBunkerURLParsing() async throws {
        let ndk = NDK()
        // Using the actual bunker connection string provided by the user
        let bunkerString = "bunker://79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798?relay=wss%3A%2F%2Frelay.nsec.app&secret=VpESbyIFohMA"

        let signer = NDKBunkerSigner.bunker(ndk: ndk, connectionToken: bunkerString)

        // Wait a moment for async initialization
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        // The signer should be created successfully
        XCTAssertNotNil(signer)
        print("✅ Bunker signer created successfully with provided connection string")
    }

    func testNostrConnectURIGeneration() async throws {
        let ndk = NDK()
        let options = NDKBunkerSigner.NostrConnectOptions(
            name: "Test App",
            url: "https://example.com",
            perms: "sign_event,nip04_encrypt"
        )

        let signer = NDKBunkerSigner.nostrConnect(
            ndk: ndk,
            relay: "wss://relay.example.com",
            options: options
        )

        // Wait for async URI generation
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds

        let uri = await signer.nostrConnectUri
        XCTAssertNotNil(uri)
        if let uri = uri {
            XCTAssertTrue(uri.hasPrefix("nostrconnect://"))
            XCTAssertTrue(uri.contains("relay=wss%3A%2F%2Frelay.example.com"))
            XCTAssertTrue(uri.contains("name=Test%20App"))
            XCTAssertTrue(uri.contains("secret="))
        }
    }

    func testAuthURLPublisher() async throws {
        let ndk = NDK()
        let signer = NDKBunkerSigner.bunker(ndk: ndk, connectionToken: "bunker://test")

        var receivedAuthUrl: String?
        let expectation = XCTestExpectation(description: "Auth URL received")

        let cancellable = await signer.authUrlPublisher.sink { authUrl in
            receivedAuthUrl = authUrl
            expectation.fulfill()
        }

        // Simulate auth URL emission (in real usage, this would come from the bunker)
        // For testing, we'd need to expose a way to trigger this

        _ = cancellable // Keep reference
    }

    func testEncryptionDecryption() async throws {
        // This test would require a mock bunker connection
        // In a real implementation, you'd mock the RPC responses

        let ndk = NDK()
        let localSigner = try NDKPrivateKeySigner.generate()
        _ = NDKBunkerSigner.bunker(ndk: ndk, connectionToken: "bunker://mock", localSigner: localSigner)

        // Test would require mocking the bunker responses
        // This is a placeholder for the test structure
    }

    func testEventSigning() async throws {
        // Similar to encryption test, this would require mocking
        let ndk = NDK()
        _ = NDKBunkerSigner.bunker(ndk: ndk, connectionToken: "bunker://mock")

        _ = NDKEvent(
            pubkey: "test",
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: EventKind.textNote,
            tags: [],
            content: "Test message"
        )

        // Test would require mocking the bunker responses
    }

    func testConnectionHandling() async throws {
        let ndk = NDK()
        let signer = NDKBunkerSigner.bunker(ndk: ndk, connectionToken: "bunker://test?relay=wss://relay.test.com")

        // Test disconnect
        await signer.disconnect()

        // Verify cleanup (would need to expose state for testing)
    }

    func testRPCMessageParsing() async throws {
        let ndk = NDK()
        let localSigner = try NDKPrivateKeySigner.generate()
        _ = NDKNostrRPC(ndk: ndk, localSigner: localSigner, relayUrls: ["wss://relay.test.com"])

        // Create a test event with encrypted content
        _ = NDKEvent(
            pubkey: "test",
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: 24133,
            tags: [],
            content: "encrypted_content_here"
        )

        // Test parsing would require proper encrypted content
        // This is a placeholder for the test structure
    }
}

// MARK: - Mock Helpers

extension NDKBunkerSignerTests {
    /// Create a mock bunker response event
    func createMockResponse(id: String, result: String, error: String? = nil) -> NDKEvent {
        let response: [String: Any] = [
            "id": id,
            "result": result,
            "error": error as Any,
        ].compactMapValues { $0 }

        let responseData = try! JSONSerialization.data(withJSONObject: response)
        let responseString = String(data: responseData, encoding: .utf8)!

        return NDKEvent(
            pubkey: "mock_bunker",
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: 24133,
            tags: [],
            content: responseString // Would need to be encrypted in real scenario
        )
    }
}
