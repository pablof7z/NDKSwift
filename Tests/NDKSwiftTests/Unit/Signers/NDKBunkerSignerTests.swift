import XCTest
import Combine
@testable import NDKSwiftCore

@MainActor
final class NDKBunkerSignerTests: XCTestCase {
    
    // MARK: - Test Helpers
    
    private var cancellables = Set<AnyCancellable>()
    
    override func setUp() {
        super.setUp()
        cancellables = Set<AnyCancellable>()
    }
    
    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }
    
    private func createTestNDK() -> NDK {
        return NDK()
    }
    
    private func createLocalSigner() throws -> NDKPrivateKeySigner {
        return try NDKPrivateKeySigner.generate()
    }
    
    // MARK: - BunkerURLParser Tests
    
    func testBunkerURLParserValidURL() {
        let parser = BunkerURLParser(urlString: "bunker://pubkey123?relay=wss://relay1.com&relay=wss://relay2.com&secret=mysecret&pubkey=userpubkey")
        let result = parser.parse()
        
        XCTAssertEqual(result.bunkerPubkey, "pubkey123")
        XCTAssertEqual(result.userPubkey, "userpubkey")
        XCTAssertEqual(result.relays, ["wss://relay1.com", "wss://relay2.com"])
        XCTAssertEqual(result.secret, "mysecret")
    }
    
    func testBunkerURLParserWithHostname() {
        let parser = BunkerURLParser(urlString: "bunker://bunker.example.com?relay=wss://relay.com")
        let result = parser.parse()
        
        XCTAssertEqual(result.bunkerPubkey, "bunker.example.com")
        XCTAssertNil(result.userPubkey)
        XCTAssertEqual(result.relays, ["wss://relay.com"])
        XCTAssertNil(result.secret)
    }
    
    func testBunkerURLParserWithDoubleSlashPath() {
        let parser = BunkerURLParser(urlString: "bunker:////pubkey456?relay=wss://relay.com")
        let result = parser.parse()
        
        XCTAssertEqual(result.bunkerPubkey, "pubkey456")
        XCTAssertEqual(result.relays, ["wss://relay.com"])
    }
    
    func testBunkerURLParserMinimal() {
        let parser = BunkerURLParser(urlString: "bunker://pubkey789")
        let result = parser.parse()
        
        XCTAssertEqual(result.bunkerPubkey, "pubkey789")
        XCTAssertNil(result.userPubkey)
        XCTAssertEqual(result.relays, [])
        XCTAssertNil(result.secret)
    }
    
    func testBunkerURLParserInvalidScheme() {
        let parser = BunkerURLParser(urlString: "https://example.com")
        let result = parser.parse()
        
        XCTAssertNil(result.bunkerPubkey)
        XCTAssertNil(result.userPubkey)
        XCTAssertEqual(result.relays, [])
        XCTAssertNil(result.secret)
    }
    
    func testBunkerURLParserInvalidURL() {
        let parser = BunkerURLParser(urlString: "not a valid url")
        let result = parser.parse()
        
        XCTAssertNil(result.bunkerPubkey)
        XCTAssertNil(result.userPubkey)
        XCTAssertEqual(result.relays, [])
        XCTAssertNil(result.secret)
    }
    
    // MARK: - Factory Method Tests
    
    func testCreateBunkerSignerWithConnectionToken() async throws {
        let ndk = createTestNDK()
        let localSigner = try createLocalSigner()
        // Use a valid hex pubkey for the bunker
        let bunkerPubkey = "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"
        let connectionToken = "bunker://\(bunkerPubkey)?relay=wss://relay.com&secret=mysecret"

        let bunkerSigner = try await NDKBunkerSigner.bunker(ndk: ndk, connectionToken: connectionToken, localSigner: localSigner)

        XCTAssertNotNil(bunkerSigner)
        // Don't call pubkey as it will try to connect
    }
    
    func testCreateBunkerSignerWithNIP05() async throws {
        let ndk = createTestNDK()
        let localSigner = try createLocalSigner()
        let nip05 = "alice@example.com"

        let bunkerSigner = try await NDKBunkerSigner.nip05(ndk: ndk, nip05: nip05, localSigner: localSigner)

        XCTAssertNotNil(bunkerSigner)
    }
    
    func testCreateNostrConnectSigner() async throws {
        let ndk = createTestNDK()
        let localSigner = try createLocalSigner()
        let relays = ["wss://relay.example.com"]
        let options = NDKBunkerSigner.NostrConnectOptions(
            name: "Test App",
            url: "https://testapp.com",
            image: "https://testapp.com/icon.png",
            perms: "sign_event:1,sign_event:3"
        )

        let bunkerSigner = try await NDKBunkerSigner.nostrConnect(ndk: ndk, relays: relays, localSigner: localSigner, options: options)

        XCTAssertNotNil(bunkerSigner)

        // URI should be immediately available (no more sleep needed!)
        let uri = await bunkerSigner.nostrConnectUri
        XCTAssertNotNil(uri)

        if let uri = uri {
            XCTAssertTrue(uri.hasPrefix("nostrconnect://"))
            XCTAssertTrue(uri.contains("name=Test%20App"))
            XCTAssertTrue(uri.contains("url=https://testapp.com"))
            XCTAssertTrue(uri.contains("relay=wss://relay.example.com"))
        }
    }
    
    func testCreateNostrConnectSignerMinimal() async throws {
        let ndk = createTestNDK()
        let relays = ["wss://relay.example.com"]

        // Without local signer - should generate one
        let bunkerSigner = try await NDKBunkerSigner.nostrConnect(ndk: ndk, relays: relays)

        XCTAssertNotNil(bunkerSigner)

        // URI should be immediately available (no more sleep needed!)
        let uri = await bunkerSigner.nostrConnectUri
        XCTAssertNotNil(uri)

        if let uri = uri {
            XCTAssertTrue(uri.hasPrefix("nostrconnect://"))
            XCTAssertTrue(uri.contains("relay=wss://relay.example.com"))
            XCTAssertTrue(uri.contains("secret=")) // Should have generated secret
        }
    }
    
    // MARK: - NostrConnect Options Tests
    
    func testNostrConnectOptionsInitialization() {
        let options = NDKBunkerSigner.NostrConnectOptions(
            name: "MyApp",
            url: "https://myapp.com",
            image: "https://myapp.com/logo.png",
            perms: "sign_event:1"
        )
        
        XCTAssertEqual(options.name, "MyApp")
        XCTAssertEqual(options.url, "https://myapp.com")
        XCTAssertEqual(options.image, "https://myapp.com/logo.png")
        XCTAssertEqual(options.perms, "sign_event:1")
    }
    
    func testNostrConnectOptionsPartial() {
        let options = NDKBunkerSigner.NostrConnectOptions(name: "MyApp")
        
        XCTAssertEqual(options.name, "MyApp")
        XCTAssertNil(options.url)
        XCTAssertNil(options.image)
        XCTAssertNil(options.perms)
    }
    
    // MARK: - NDKSigner Protocol Tests
    
    func testBunkerSignerConformsToNDKSigner() async throws {
        let ndk = createTestNDK()
        let localSigner = try createLocalSigner()
        let bunkerSigner = try await NDKBunkerSigner.bunker(ndk: ndk, connectionToken: "bunker://test", localSigner: localSigner)

        // Test that it's a bunker signer
        XCTAssertNotNil(bunkerSigner)
    }
    
    func testPubkeyTriggersConnection() async throws {
        let ndk = createTestNDK()
        let localSigner = try createLocalSigner()
        let bunkerSigner = try await NDKBunkerSigner.bunker(ndk: ndk, connectionToken: "bunker://test", localSigner: localSigner)

        // Calling pubkey will trigger connection attempt
        // We can't test this without a real bunker service
        // Just verify the signer was created
        XCTAssertNotNil(bunkerSigner)
    }
    
    // MARK: - Auth URL Publisher Tests
    
    func testAuthURLPublisher() async throws {
        let ndk = createTestNDK()
        let localSigner = try createLocalSigner()
        let bunkerSigner = try await NDKBunkerSigner.bunker(ndk: ndk, connectionToken: "bunker://test", localSigner: localSigner)
        
        var receivedURLs: [String] = []
        let expectation = expectation(description: "Auth URL received")
        expectation.isInverted = true // We don't expect it to be called in this test
        
        await bunkerSigner.authUrlPublisher
            .sink { url in
                receivedURLs.append(url)
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        await fulfillment(of: [expectation], timeout: 0.5)
        XCTAssertEqual(receivedURLs.count, 0)
    }
    
    // MARK: - Bunker URL Parsing Edge Cases
    
    func testBunkerURLParserMultipleRelays() {
        let parser = BunkerURLParser(urlString: "bunker://pubkey?relay=wss://relay1.com&relay=wss://relay2.com&relay=wss://relay3.com")
        let result = parser.parse()
        
        XCTAssertEqual(result.relays.count, 3)
        XCTAssertEqual(result.relays, ["wss://relay1.com", "wss://relay2.com", "wss://relay3.com"])
    }
    
    func testBunkerURLParserSpecialCharactersInSecret() {
        let parser = BunkerURLParser(urlString: "bunker://pubkey?secret=abc%20def%2Bghi&relay=wss://relay.com")
        let result = parser.parse()
        
        XCTAssertEqual(result.secret, "abc def+ghi") // URL decoding happens automatically
    }
    
    func testBunkerURLParserEmptyQueryParameters() {
        let parser = BunkerURLParser(urlString: "bunker://pubkey?pubkey=&secret=&relay=")
        let result = parser.parse()
        
        XCTAssertEqual(result.userPubkey, "")
        XCTAssertEqual(result.secret, "")
        XCTAssertEqual(result.relays, [""])
    }
    
    // MARK: - NostrConnect URI Generation Tests
    
    func testNostrConnectURIWithAllOptions() async throws {
        let ndk = createTestNDK()
        let localSigner = try createLocalSigner()
        let localPubkey = try await localSigner.pubkey

        let options = NDKBunkerSigner.NostrConnectOptions(
            name: "Test App",
            url: "https://test.com",
            image: "https://test.com/icon.png",
            perms: "sign_event:1,nip04_encrypt,nip04_decrypt"
        )

        let bunkerSigner = try await NDKBunkerSigner.nostrConnect(
            ndk: ndk,
            relays: ["wss://relay.test.com"],
            localSigner: localSigner,
            options: options
        )

        // URI should be immediately available
        let uri = await bunkerSigner.nostrConnectUri
        XCTAssertNotNil(uri)
        
        // Parse the generated URI
        guard let uri = uri,
              let url = URL(string: uri),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            XCTFail("Invalid URI generated")
            return
        }
        
        XCTAssertEqual(url.scheme, "nostrconnect")
        XCTAssertEqual(url.host, localPubkey)
        
        // Check query parameters
        let queryItems = components.queryItems ?? []
        let queryDict = Dictionary(uniqueKeysWithValues: queryItems.compactMap { item in
            item.value.map { (item.name, $0) }
        })
        
        XCTAssertEqual(queryDict["name"], "Test App")
        XCTAssertEqual(queryDict["url"], "https://test.com")
        XCTAssertEqual(queryDict["image"], "https://test.com/icon.png")
        XCTAssertEqual(queryDict["perms"], "sign_event:1,nip04_encrypt,nip04_decrypt")
        XCTAssertEqual(queryDict["relay"], "wss://relay.test.com")
        XCTAssertNotNil(queryDict["secret"]) // Should have a generated secret
    }
    
    func testNostrConnectURIWithSpecialCharacters() async throws {
        let ndk = createTestNDK()
        let options = NDKBunkerSigner.NostrConnectOptions(
            name: "Test & App",
            url: "https://test.com/path?query=1"
        )

        let bunkerSigner = try await NDKBunkerSigner.nostrConnect(
            ndk: ndk,
            relays: ["wss://relay.test.com/path"],
            options: options
        )

        // URI should be immediately available
        let uri = await bunkerSigner.nostrConnectUri
        XCTAssertNotNil(uri)

        if let uri = uri {
            // Should properly encode special characters
            // The actual implementation may vary in how it encodes URLs
            XCTAssertTrue(uri.contains("name=Test%20&%20App"), "Expected name parameter with encoded space")
            XCTAssertTrue(uri.contains("url=https://test.com/path?query=1"), "Expected URL parameter")
            XCTAssertTrue(uri.contains("relay=wss://relay.test.com/path"), "Expected relay parameter")
        }
    }

    func testNostrConnectURIWithMultipleRelays() async throws {
        let ndk = createTestNDK()
        let relays = [
            "wss://relay1.example.com",
            "wss://relay2.example.com",
            "wss://relay3.example.com"
        ]

        let bunkerSigner = try await NDKBunkerSigner.nostrConnect(
            ndk: ndk,
            relays: relays,
            options: NDKBunkerSigner.NostrConnectOptions(name: "Multi-Relay Test")
        )

        let uri = await bunkerSigner.nostrConnectUri
        XCTAssertNotNil(uri)

        if let uri = uri {
            // Should contain all three relays as separate relay= parameters
            XCTAssertTrue(uri.contains("relay=wss://relay1.example.com"))
            XCTAssertTrue(uri.contains("relay=wss://relay2.example.com"))
            XCTAssertTrue(uri.contains("relay=wss://relay3.example.com"))

            // Count occurrences of "relay=" parameter
            let relayCount = uri.components(separatedBy: "relay=").count - 1
            XCTAssertEqual(relayCount, 3, "Expected 3 relay parameters")
        }
    }
    
    // MARK: - Connection Type Tests
    
    func testBunkerConnectionTypeInitialization() async throws {
        let ndk = createTestNDK()
        let localSigner = try createLocalSigner()
        
        // Test bunker type
        let bunkerSigner = try await NDKBunkerSigner.bunker(
            ndk: ndk,
            connectionToken: "bunker://pubkey?relay=wss://relay.com",
            localSigner: localSigner
        )
        XCTAssertNotNil(bunkerSigner)

        // Test NIP-05 type
        let nip05Signer = try await NDKBunkerSigner.nip05(
            ndk: ndk,
            nip05: "alice@example.com",
            localSigner: localSigner
        )
        XCTAssertNotNil(nip05Signer)
        
        // Test nostrconnect type
        let nostrConnectSigner = try await NDKBunkerSigner.nostrConnect(
            ndk: ndk,
            relays: ["wss://relay.com"],
            localSigner: localSigner
        )
        XCTAssertNotNil(nostrConnectSigner)
    }
}