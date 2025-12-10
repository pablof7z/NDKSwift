import XCTest
@testable import NDKSwiftCore

/// Simple test to verify NIP-17 works without dependencies on broken test infrastructure
final class NIP17SimpleTest: XCTestCase {
    
    func testNIP17BasicFunctionality() async throws {
        // Create signers
        let alice = try NDKPrivateKeySigner.generate()
        let bob = try NDKPrivateKeySigner.generate()
        
        let alicePubkey = try await alice.pubkey
        let bobPubkey = try await bob.pubkey
        
        // Test message
        let message = "Hello Bob, this is a test!"
        let subject = "Test Subject"
        
        // Send message
        let wrapped = try await NIP17.sendMessage(
            message,
            to: NIP17Recipient(pubkey: bobPubkey),
            signer: alice,
            subject: subject
        )
        
        // Verify gift wrap
        XCTAssertEqual(wrapped.kind, EventKind.giftWrap, "Should be gift wrapped")
        XCTAssertNotEqual(wrapped.pubkey, alicePubkey, "Sender should be hidden")
        
        // Unwrap message
        let unwrapped = try await NIP17.unwrapEvent(wrapped, recipientSigner: bob)
        
        // Verify content
        XCTAssertEqual(unwrapped.content, message, "Message content should match")
        XCTAssertEqual(unwrapped.pubkey, alicePubkey, "Should reveal sender after unwrap")
        XCTAssertEqual(unwrapped.kind, EventKind.chatMessage, "Should be chat message")
        
        // Verify subject
        let subjectTag = unwrapped.tags.first { $0[0] == "subject" }
        XCTAssertEqual(subjectTag?[1], subject, "Subject should be preserved")
        
        print("✅ NIP-17 basic functionality test passed!")
    }
}