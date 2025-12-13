import Foundation
import NDKSwift

/// Example: NIP-17 Private Direct Messages
///
/// This example demonstrates how to use NIP-17 for sending and receiving
/// metadata-private direct messages using gift wrapping.

@main
struct NIP17Example {
    static func main() async throws {
        print("🔐 NIP-17 Private Direct Messages Example")
        print("=" * 50)

        // Initialize NDK
        let ndk = NDK()

        // Generate keys for demonstration
        let alice = NDKPrivateKeySigner.generate()
        let bob = NDKPrivateKeySigner.generate()

        let alicePubkey = await alice.publicKey
        let bobPubkey = await bob.publicKey

        print("👤 Alice's pubkey: \(String(alicePubkey.prefix(16)))...")
        print("👤 Bob's pubkey: \(String(bobPubkey.prefix(16)))...")
        print()

        // MARK: - Send a Simple Message

        print("📤 Sending a simple private message from Alice to Bob...")

        let message = "Hello Bob! This is a private message using NIP-17."
        let recipient = NIP17Recipient(
            pubkey: bobPubkey,
            relayURL: "wss://relay.damus.io"
        )

        let wrappedMessage = try await NIP17.sendMessage(
            message,
            to: recipient,
            signer: alice,
            subject: "First NIP-17 Message"
        )

        print("✅ Message wrapped successfully!")
        print("   Kind: \(wrappedMessage.kind) (gift wrap)")
        print("   Wrapped by: \(String(wrappedMessage.pubkey.prefix(16)))... (random key)")
        print("   Tagged recipient: \(wrappedMessage.tags.first { $0[0] == "p" }?[1].prefix(16) ?? "none")...")
        print()

        // MARK: - Receive and Unwrap Message

        print("📥 Bob unwrapping the message...")

        let unwrappedMessage = try await NIP17.unwrapEvent(
            wrappedMessage,
            recipientSigner: bob
        )

        print("✅ Message unwrapped successfully!")
        print("   From: \(String(unwrappedMessage.pubkey.prefix(16)))... (Alice)")
        print("   Content: \(unwrappedMessage.content)")
        print("   Subject: \(unwrappedMessage.tags.first { $0[0] == "subject" }?[1] ?? "No subject")")
        print()

        // MARK: - Group Message Example

        print("📤 Sending a group message to multiple recipients...")

        let charlie = NDKPrivateKeySigner.generate()
        let charliePubkey = await charlie.publicKey

        let groupRecipients = [
            NIP17Recipient(pubkey: bobPubkey, relayURL: "wss://relay.damus.io"),
            NIP17Recipient(pubkey: charliePubkey, relayURL: "wss://nos.lol"),
        ]

        let groupMessage = "Hey everyone! This is a group message."
        let wrappedEvents = try await NIP17.sendToMany(
            groupMessage,
            to: groupRecipients,
            signer: alice,
            subject: "Team Update"
        )

        print("✅ Group message wrapped for \(wrappedEvents.events.count) recipients")
        print("   Recipients:")
        for (pubkey, event) in wrappedEvents.events {
            print("   - \(String(pubkey.prefix(16)))... (kind \(event.kind))")
        }
        print()

        // MARK: - Reply Example

        print("📤 Bob replying to Alice's message...")

        let replyConfig = NIP17MessageConfig(
            recipients: [NIP17Recipient(pubkey: alicePubkey)],
            subject: "Re: First NIP-17 Message",
            replyTo: NIP17ReplyTo(
                eventId: unwrappedMessage.id,
                relayURL: "wss://relay.damus.io"
            )
        )

        let replyEvent = try NIP17.createEvent(
            content: "Thanks for the message, Alice!",
            config: replyConfig,
            senderPubkey: bobPubkey
        )

        let wrappedReply = try await NIP17.wrapEvent(
            replyEvent,
            signer: bob,
            recipient: NIP17Recipient(pubkey: alicePubkey)
        )

        print("✅ Reply wrapped successfully!")
        print("   Reply tag: \(replyEvent.tags.first { $0[0] == "e" && $0.count > 3 && $0[3] == "reply" } ?? [])")
        print()

        // MARK: - File Message Example

        print("📤 Sending a file message...")

        let fileMetadata = """
        {
            "url": "https://example.com/document.pdf",
            "mimeType": "application/pdf",
            "size": 2048000,
            "name": "Important Document.pdf"
        }
        """

        let fileConfig = NIP17MessageConfig(
            recipients: [NIP17Recipient(pubkey: bobPubkey)],
            subject: "Document for review"
        )

        let fileEvent = try NIP17.createEvent(
            content: fileMetadata,
            config: fileConfig,
            senderPubkey: alicePubkey,
            kind: EventKind.fileMessage
        )

        let wrappedFile = try await NIP17.wrapEvent(
            fileEvent,
            signer: alice,
            recipient: NIP17Recipient(pubkey: bobPubkey)
        )

        print("✅ File message wrapped!")
        print("   Event kind: \(fileEvent.kind) (file message)")
        print()

        // MARK: - Privacy Features Demo

        print("🔒 Privacy Features:")
        print("   1. Metadata Protection:")
        print("      - Sender identity is hidden (random gift wrap key)")
        print("      - Timestamp is randomized (+/- 2 days)")
        print("      - Message relationships are encrypted")
        print()
        print("   2. Forward Secrecy:")
        print("      - Each message uses fresh encryption")
        print("      - Compromise of one message doesn't affect others")
        print()
        print("   3. Plausible Deniability:")
        print("      - Messages are unsigned 'rumors'")
        print("      - Recipients can't prove authorship to third parties")

        print("\n✅ NIP-17 example completed!")
    }
}

// Helper to repeat strings
extension String {
    static func * (lhs: String, rhs: Int) -> String {
        return String(repeating: lhs, count: rhs)
    }
}
