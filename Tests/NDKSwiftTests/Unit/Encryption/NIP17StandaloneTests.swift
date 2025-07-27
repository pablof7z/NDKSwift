import XCTest
@testable import NDKSwift

final class NIP17StandaloneTests: XCTestCase {
    
    func testBasicNIP17Flow() async throws {
        let alice = try NDKPrivateKeySigner.generate()
        let bob = try NDKPrivateKeySigner.generate()
        
        let alicePubkey = try await alice.pubkey
        let bobPubkey = try await bob.pubkey
        
        // Create a private message
        let originalContent = "Hello Bob, this is a secret message!"
        
        // Create the gift wrap
        let giftWrap = try await NIP17PrivateMessages.createPrivateMessage(
            content: originalContent,
            to: [bobPubkey],
            signer: alice
        )
        
        XCTAssertEqual(giftWrap.kind, EventKind.giftWrap)
        XCTAssertEqual(giftWrap.pubkey.count, 64)
        XCTAssertNotEqual(giftWrap.pubkey, alicePubkey, "Gift wrap should use ephemeral key")
        
        // Bob unwraps the gift
        let unwrapped = try await NIP17PrivateMessages.unwrapPrivateMessage(
            giftWrap: giftWrap,
            recipientSigner: bob
        )
        
        XCTAssertEqual(unwrapped.content, originalContent)
        XCTAssertEqual(unwrapped.pubkey, alicePubkey)
        XCTAssertEqual(unwrapped.kind, EventKind.privateDirectMessage)
        
        // Verify tags
        let pTags = unwrapped.tags.filter { $0[0] == "p" }
        XCTAssertEqual(pTags.count, 1)
        XCTAssertEqual(pTags[0][1], bobPubkey)
    }
    
    func testGroupMessaging() async throws {
        let alice = try NDKPrivateKeySigner.generate()
        let bob = try NDKPrivateKeySigner.generate()
        let charlie = try NDKPrivateKeySigner.generate()
        
        let alicePubkey = try await alice.pubkey
        let bobPubkey = try await bob.pubkey
        let charliePubkey = try await charlie.pubkey
        
        let groupContent = "Hey team, this is our secret group chat!"
        
        // Alice sends to Bob and Charlie
        let giftWrap = try await NIP17PrivateMessages.createPrivateMessage(
            content: groupContent,
            to: [bobPubkey, charliePubkey],
            signer: alice
        )
        
        // Bob unwraps
        let bobUnwrapped = try await NIP17PrivateMessages.unwrapPrivateMessage(
            giftWrap: giftWrap,
            recipientSigner: bob
        )
        
        XCTAssertEqual(bobUnwrapped.content, groupContent)
        XCTAssertEqual(bobUnwrapped.pubkey, alicePubkey)
        
        // Verify all recipients are tagged
        let pTags = bobUnwrapped.tags.filter { $0[0] == "p" }
        let taggedPubkeys = pTags.map { $0[1] }
        XCTAssertTrue(taggedPubkeys.contains(bobPubkey))
        XCTAssertTrue(taggedPubkeys.contains(charliePubkey))
    }
    
    func testNIP59GiftWrap() async throws {
        let signer = try NDKPrivateKeySigner.generate()
        let recipient = try NDKPrivateKeySigner.generate()
        
        let recipientPubkey = try await recipient.pubkey
        
        // Create a regular event
        let originalEvent = try await EventTestFactory.createSignedEvent(
            ndk: NDK(relayUrls: []),
            kind: 1,
            content: "This will be wrapped",
            signer: signer
        )
        
        // Gift wrap it
        let wrappedEvent = try await NIP59GiftWrap.wrap(
            event: originalEvent,
            recipientPubkey: recipientPubkey
        )
        
        XCTAssertEqual(wrappedEvent.kind, EventKind.giftWrap)
        XCTAssertNotNil(wrappedEvent.content)
        XCTAssertFalse(wrappedEvent.content.isEmpty)
        
        // Verify ephemeral pubkey
        XCTAssertNotEqual(wrappedEvent.pubkey, originalEvent.pubkey)
        XCTAssertEqual(wrappedEvent.pubkey.count, 64)
        
        // Try to unwrap
        let unwrappedEvent = try await NIP59GiftWrap.unwrap(
            wrappedEvent,
            using: recipient
        )
        
        XCTAssertEqual(unwrappedEvent.content, originalEvent.content)
        XCTAssertEqual(unwrappedEvent.kind, originalEvent.kind)
        XCTAssertEqual(unwrappedEvent.pubkey, originalEvent.pubkey)
    }
    
    func testPrivacyFeatures() async throws {
        let alice = try NDKPrivateKeySigner.generate()
        let bob = try NDKPrivateKeySigner.generate()
        
        let bobPubkey = try await bob.pubkey
        
        // Create multiple messages
        let messages = [
            "First message",
            "Second message",
            "Third message"
        ]
        
        var giftWraps: [NDKEvent] = []
        
        for message in messages {
            let giftWrap = try await NIP17PrivateMessages.createPrivateMessage(
                content: message,
                to: [bobPubkey],
                signer: alice
            )
            giftWraps.append(giftWrap)
        }
        
        // Verify each gift wrap has unique ephemeral pubkey
        let pubkeys = giftWraps.map { $0.pubkey }
        let uniquePubkeys = Set(pubkeys)
        XCTAssertEqual(uniquePubkeys.count, pubkeys.count, "Each message should use different ephemeral key")
        
        // Verify randomized timestamps
        let timestamps = giftWraps.map { $0.createdAt }
        let sortedTimestamps = timestamps.sorted()
        XCTAssertNotEqual(timestamps, sortedTimestamps, "Timestamps should be randomized")
        
        // Verify all can be unwrapped
        for (index, giftWrap) in giftWraps.enumerated() {
            let unwrapped = try await NIP17PrivateMessages.unwrapPrivateMessage(
                giftWrap: giftWrap,
                recipientSigner: bob
            )
            XCTAssertEqual(unwrapped.content, messages[index])
        }
    }
}