import XCTest
@testable import NDKSwiftCore

/// Minimal test without any dependencies on broken test infrastructure
final class NIP17MinimalTest: XCTestCase {
    
    func testNIP17Works() async throws {
        // Test data
        let alicePrivKey = "f09ac9b695d0a4c6daa418fe95b977eea20f54d9545592bc36a4f9e14f3eb840"
        let bobPrivKey = "5393a825e5892d8e18d4a5ea61ced105e8bb2a106f42876be3a40522e0b13747"
        
        // Create signers
        let alice = try NDKPrivateKeySigner(privateKey: alicePrivKey)
        let bob = try NDKPrivateKeySigner(privateKey: bobPrivKey)
        
        let bobPubkey = try await bob.pubkey
        
        // Send message
        let message = "Test NIP-17 message"
        let wrapped = try await NIP17.sendMessage(
            message,
            to: NIP17Recipient(pubkey: bobPubkey),
            signer: alice
        )
        
        // Verify it's gift wrapped
        XCTAssertEqual(wrapped.kind, 1059) // EventKind.giftWrap
        
        // Unwrap
        let unwrapped = try await NIP17.unwrapEvent(wrapped, recipientSigner: bob)
        
        // Verify content
        XCTAssertEqual(unwrapped.content, message)
        XCTAssertEqual(unwrapped.kind, 14) // EventKind.chatMessage
    }
}