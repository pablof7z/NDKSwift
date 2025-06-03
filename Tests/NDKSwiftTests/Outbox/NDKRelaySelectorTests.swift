import XCTest
@testable import NDKSwift

final class NDKRelaySelectorTests: XCTestCase {
    var ndk: NDK!
    var tracker: NDKOutboxTracker!
    var ranker: NDKRelayRanker!
    var selector: NDKRelaySelector!
    
    override func setUp() async throws {
        ndk = NDK()
        tracker = NDKOutboxTracker(ndk: ndk)
        ranker = NDKRelayRanker(ndk: ndk, tracker: tracker)
        selector = NDKRelaySelector(ndk: ndk, tracker: tracker, ranker: ranker)
    }
    
    func testSelectRelaysForPublishing() async {
        // Set up author's write relays
        await tracker.track(
            pubkey: "author_pubkey",
            readRelays: ["wss://read.relay"],
            writeRelays: ["wss://write1.relay", "wss://write2.relay"]
        )
        
        // Create event
        let event = NDKEvent(
            pubkey: "author_pubkey",
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: 1,
            tags: [],
            content: "Test note"
        )
        
        let result = await selector.selectRelaysForPublishing(event: event)
        
        XCTAssertTrue(result.relays.contains("wss://write1.relay"))
        XCTAssertTrue(result.relays.contains("wss://write2.relay"))
        XCTAssertEqual(result.missingRelayInfoPubkeys.count, 0)
    }
    
    func testPublishingWithMentions() async {
        // Set up relays for event author
        await tracker.track(
            pubkey: "author_pubkey",
            writeRelays: ["wss://author.relay"]
        )
        
        // Set up relays for mentioned users
        await tracker.track(
            pubkey: "mentioned_user1",
            readRelays: ["wss://user1.relay"],
            writeRelays: ["wss://user1-write.relay"]
        )
        
        await tracker.track(
            pubkey: "mentioned_user2",
            readRelays: ["wss://user2.relay"]
        )
        
        // Create event with mentions
        let event = NDKEvent(
            pubkey: "author_pubkey",
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: 1,
            tags: [
                ["p", "mentioned_user1"],
                ["p", "mentioned_user2"],
                ["p", "unknown_user"]
            ],
            content: "Hello @mentioned_user1 and @mentioned_user2"
        )
        
        let result = await selector.selectRelaysForPublishing(event: event)
        
        // Should include author's write relay
        XCTAssertTrue(result.relays.contains("wss://author.relay"))
        
        // Should include mentioned users' write relays (or read if no write)
        XCTAssertTrue(result.relays.contains("wss://user1-write.relay"))
        XCTAssertTrue(result.relays.contains("wss://user2.relay")) // Falls back to read
        
        // Should track missing user
        XCTAssertTrue(result.missingRelayInfoPubkeys.contains("unknown_user"))
    }
    
    func testPublishingWithReplyContext() async {
        await tracker.track(
            pubkey: "author_pubkey",
            writeRelays: ["wss://author.relay"]
        )
        
        // Create reply event with e tags
        let event = NDKEvent(
            pubkey: "author_pubkey",
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: 1,
            tags: [
                ["e", "parent_event_id", "wss://parent.relay"],
                ["e", "root_event_id", "wss://root.relay"]
            ],
            content: "This is a reply"
        )
        
        let result = await selector.selectRelaysForPublishing(event: event)
        
        // Should include recommended relays from e tags
        XCTAssertTrue(result.relays.contains("wss://parent.relay"))
        XCTAssertTrue(result.relays.contains("wss://root.relay"))
    }
    
    func testPublishingNIP65RelayList() async {
        await tracker.track(
            pubkey: "author_pubkey",
            readRelays: ["wss://read1.relay", "wss://read2.relay"],
            writeRelays: ["wss://write1.relay", "wss://write2.relay"]
        )
        
        // Create NIP-65 relay list event
        let event = NDKEvent(
            pubkey: "author_pubkey",
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: NDKRelayList.kind,
            tags: [
                ["r", "wss://new-read.relay", "read"],
                ["r", "wss://new-write.relay", "write"]
            ],
            content: ""
        )
        
        let result = await selector.selectRelaysForPublishing(event: event)
        
        // Should publish to both read and write relays for relay lists
        XCTAssertTrue(result.relays.contains("wss://read1.relay"))
        XCTAssertTrue(result.relays.contains("wss://write1.relay"))
    }
    
    func testSelectRelaysForFetching() async {
        // Set up user's read relays
        await tracker.track(
            pubkey: "user_pubkey",
            readRelays: ["wss://user-read1.relay", "wss://user-read2.relay"]
        )
        
        // Set up author relays
        await tracker.track(
            pubkey: "author1",
            readRelays: ["wss://author1-read.relay"]
        )
        
        let filter = NDKFilter(
            authors: ["author1"],
            kinds: [1]
        )
        
        // Mock signer to return user_pubkey
        ndk.signer = MockSigner(publicKey: "user_pubkey")
        
        let result = await selector.selectRelaysForFetching(filter: filter)
        
        // Should include user's read relays
        XCTAssertTrue(result.relays.contains("wss://user-read1.relay"))
        
        // Should include author's read relays
        XCTAssertTrue(result.relays.contains("wss://author1-read.relay"))
    }
    
    func testFetchingWithTaggedUsers() async {
        await tracker.track(
            pubkey: "tagged_user",
            readRelays: ["wss://tagged-read.relay"],
            writeRelays: ["wss://tagged-write.relay"]
        )
        
        let filter = NDKFilter(
            kinds: [1],
            tags: ["p": ["tagged_user"]]
        )
        
        let result = await selector.selectRelaysForFetching(filter: filter)
        
        // Should include tagged user's read relays
        XCTAssertTrue(result.relays.contains("wss://tagged-read.relay"))
    }
    
    func testChooseRelayCombinationForPubkeys() async {
        // Set up relays for multiple authors
        await tracker.track(
            pubkey: "author1",
            readRelays: ["wss://common.relay", "wss://relay1.com"]
        )
        
        await tracker.track(
            pubkey: "author2",
            readRelays: ["wss://common.relay", "wss://relay2.com"]
        )
        
        await tracker.track(
            pubkey: "author3",
            readRelays: ["wss://relay3.com"]
        )
        
        let relayMap = await selector.chooseRelayCombinationForPubkeys(
            ["author1", "author2", "author3"],
            type: .read,
            config: CombinationConfig(relaysPerAuthor: 2)
        )
        
        // common.relay should serve multiple authors
        let commonRelayAuthors = relayMap["wss://common.relay"] ?? []
        XCTAssertTrue(commonRelayAuthors.contains("author1"))
        XCTAssertTrue(commonRelayAuthors.contains("author2"))
        
        // Each author should have coverage
        let authorCoverage = countAuthorCoverage(relayMap: relayMap)
        XCTAssertGreaterThanOrEqual(authorCoverage["author1"] ?? 0, 1)
        XCTAssertGreaterThanOrEqual(authorCoverage["author2"] ?? 0, 1)
        XCTAssertGreaterThanOrEqual(authorCoverage["author3"] ?? 0, 1)
    }
    
    func testFallbackRelays() async {
        // Create event with no relay information
        let event = NDKEvent(
            pubkey: "unknown_author",
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: 1,
            tags: [],
            content: "Test"
        )
        
        // Add some default relays to NDK
        ndk.addRelay("wss://default1.relay")
        ndk.addRelay("wss://default2.relay")
        
        let config = PublishingConfig(minRelayCount: 2)
        let result = await selector.selectRelaysForPublishing(
            event: event,
            config: config
        )
        
        // Should use fallback relays
        XCTAssertGreaterThanOrEqual(result.relays.count, 2)
        XCTAssertEqual(result.selectionMethod, .fallback)
    }
    
    func testMaxRelayLimit() async {
        // Track many relays
        var writeRelays = Set<String>()
        for i in 0..<20 {
            writeRelays.insert("wss://relay\(i).com")
        }
        
        await tracker.track(
            pubkey: "author_pubkey",
            writeRelays: writeRelays
        )
        
        let event = NDKEvent(
            pubkey: "author_pubkey",
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: 1,
            tags: [],
            content: "Test"
        )
        
        let config = PublishingConfig(maxRelayCount: 5)
        let result = await selector.selectRelaysForPublishing(
            event: event,
            config: config
        )
        
        // Should respect max relay count
        XCTAssertLessThanOrEqual(result.relays.count, 5)
    }
    
    // MARK: - Helper Methods
    
    private func countAuthorCoverage(relayMap: RelayToPubkeysMap) -> [String: Int] {
        var coverage: [String: Int] = [:]
        
        for (_, authors) in relayMap {
            for author in authors {
                coverage[author, default: 0] += 1
            }
        }
        
        return coverage
    }
}

// MARK: - Mock Signer

class MockSigner: NDKSigner {
    let publicKey: String
    
    init(publicKey: String) {
        self.publicKey = publicKey
    }
    
    var pubkey: PublicKey {
        get async throws {
            return publicKey
        }
    }
    
    func sign(_ event: NDKEvent) async throws -> Signature {
        return "mock_signature"
    }
    
    func blockUntilReady() async throws {
        // Mock implementation - immediately ready
    }
    
    func encrypt(recipient: NDKUser, value: String, scheme: NDKEncryptionScheme) async throws -> String {
        return "encrypted_message"
    }
    
    func decrypt(sender: NDKUser, value: String, scheme: NDKEncryptionScheme) async throws -> String {
        return "decrypted_message"
    }
}