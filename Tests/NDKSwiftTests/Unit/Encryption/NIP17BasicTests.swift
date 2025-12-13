@testable import NDKSwiftCore
import XCTest

/// Basic tests for NIP-17 implementation
final class NIP17BasicTests: XCTestCase {
    func testBasicNIP17Flow() async throws {
        // Create signers
        let alice = try NDKPrivateKeySigner.generate()
        let bob = try NDKPrivateKeySigner.generate()

        let alicePubkey = try await alice.pubkey
        let bobPubkey = try await bob.pubkey

        // Create a simple message
        let message = "Hello, this is a NIP-17 test message!"
        let recipient = NIP17Recipient(pubkey: bobPubkey)

        // Alice sends message to Bob
        let wrappedMessage = try await NIP17.sendMessage(
            message,
            to: recipient,
            signer: alice,
            subject: "Test Subject"
        )

        // Verify wrapped message
        XCTAssertEqual(wrappedMessage.kind, EventKind.giftWrap)
        XCTAssertTrue(wrappedMessage.tags.contains { $0[0] == "p" && $0[1] == bobPubkey })

        // Bob unwraps the message
        let unwrapped = try await NIP17.unwrapEvent(wrappedMessage, recipientSigner: bob)

        // Verify unwrapped message
        XCTAssertEqual(unwrapped.content, message)
        XCTAssertEqual(unwrapped.pubkey, alicePubkey)
        XCTAssertEqual(unwrapped.kind, EventKind.chatMessage)

        // Verify subject tag
        let subjectTag = unwrapped.tags.first { $0[0] == "subject" }
        XCTAssertEqual(subjectTag?[1], "Test Subject")
    }

    func testNIP59GiftWrap() async throws {
        let signer = try NDKPrivateKeySigner.generate()
        let recipientSigner = try NDKPrivateKeySigner.generate()

        let senderPubkey = try await signer.pubkey
        let recipientPubkey = try await recipientSigner.pubkey

        // Create a rumor
        let rumor = NIP59.createRumor(
            kind: EventKind.textNote,
            content: "Test rumor",
            tags: [],
            pubkey: senderPubkey
        )

        // Seal and wrap
        let wrapped = try await NIP59.sealAndWrap(
            rumor: rumor,
            signer: signer,
            recipientPubkey: recipientPubkey
        )

        XCTAssertEqual(wrapped.kind, EventKind.giftWrap)

        // Unwrap and unseal
        let recovered = try await NIP59.unwrapAndUnseal(
            giftWrap: wrapped,
            recipientSigner: recipientSigner
        )

        XCTAssertEqual(recovered.content, rumor.content)
        XCTAssertEqual(recovered.pubkey, rumor.pubkey)
    }
}
