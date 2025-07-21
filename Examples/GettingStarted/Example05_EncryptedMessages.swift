import Foundation
import NDKSwift

struct Example05_EncryptedMessages {
    static func run() async throws {
        print("🔐 NDKSwift Example: Encrypted Messages")
        print("=======================================\n")
        
        // Step 1: Create two users (Alice and Bob)
        print("👥 Creating two users for the example...")
        
        // Alice
        let aliceNDK = NDK(relayUrls: ["wss://relay.primal.net"])
        let aliceSigner = try NDKPrivateKeySigner.generate()
        aliceNDK.signer = aliceSigner
        let alicePubkey = try await aliceSigner.pubkey
        
        // Bob
        let bobNDK = NDK(relayUrls: ["wss://relay.primal.net"])
        let bobSigner = try NDKPrivateKeySigner.generate()
        bobNDK.signer = bobSigner
        let bobPubkey = try await bobSigner.pubkey
        
        print("✅ Created Alice: \(String(alicePubkey.prefix(16)))...")
        print("✅ Created Bob: \(String(bobPubkey.prefix(16)))...")
        
        // Step 2: Connect both users
        await aliceNDK.connect()
        await bobNDK.connect()
        print("\n📡 Both users connected to relay")
        
        // Step 3: Bob subscribes to encrypted messages
        print("\n📥 Bob subscribing to encrypted messages...")
        
        let bobDMFilter = NDKFilter(
            kinds: [EventKind.encryptedDirectMessage],
            tags: ["p": [bobPubkey]] // Messages where Bob is tagged
        )
        
        let bobSubscription = bobNDK.observe(filter: bobDMFilter)
        var receivedMessage: String?
        
        // Start Bob's listener in background
        let bobListenerTask = Task {
            for await event in bobSubscription.events {
                print("\n🔔 Bob received an encrypted message!")
                
                // Decrypt the message
                if let decrypted = try? await event.decryptedContent(
                    signer: bobSigner,
                    senderPubkey: alicePubkey,
                    ndk: bobNDK
                ) {
                    print("🔓 Decrypted content: \(decrypted)")
                    receivedMessage = decrypted
                } else {
                    print("❌ Failed to decrypt message")
                }
                break // Exit after first message
            }
        }
        
        // Step 4: Alice sends an encrypted message to Bob
        print("\n📤 Alice sending encrypted message to Bob...")
        
        let secretMessage = "Hello Bob! This is a secret message from Alice 🤫"
        
        // Create encrypted DM event
        let dmEvent = try await NDKEvent.encryptedDirectMessage(
            content: secretMessage,
            recipientPubkey: bobPubkey,
            signer: aliceSigner,
            useNIP44: false // Using NIP-04 for this example
        )
        
        let publishResult = try await aliceNDK.publish(dmEvent)
        
        print("✅ Encrypted message sent!")
        print("📍 Event ID: \(dmEvent.id)")
        print("🔒 Encrypted content preview: \(String(dmEvent.content.prefix(50)))...")
        
        // Wait for Bob to receive and decrypt
        try await Task.sleep(nanoseconds: 2_000_000_000)
        bobListenerTask.cancel()
        
        // Step 5: Demonstrate NIP-44 (newer encryption standard)
        print("\n🔐 Trying NIP-44 encryption (if supported)...")
        
        do {
            let nip44Event = try await NDKEvent.encryptedDirectMessage(
                content: "This uses NIP-44 encryption! 🔒",
                recipientPubkey: bobPubkey,
                signer: aliceSigner,
                useNIP44: true
            )
            
            let _ = try await aliceNDK.publish(nip44Event)
            print("✅ NIP-44 message sent successfully")
            print("📍 Event ID: \(nip44Event.id)")
        } catch {
            print("⚠️  NIP-44 might not be fully supported yet: \(error)")
        }
        
        // Step 6: Fetch conversation history
        print("\n📜 Fetching conversation history...")
        
        // Filter for messages between Alice and Bob
        let conversationFilter = NDKFilter(
            authors: [alicePubkey, bobPubkey],
            kinds: [EventKind.encryptedDirectMessage],
            tags: ["p": [alicePubkey, bobPubkey]]
        )
        
        let conversationSource = aliceNDK.observe(filter: conversationFilter)
        var conversationEvents: [NDKEvent] = []
        
        let conversationTask = Task {
            for await event in conversationSource.events {
                conversationEvents.append(event)
                if conversationEvents.count >= 10 {
                    break
                }
            }
        }
        
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        conversationTask.cancel()
        
        print("📊 Found \(conversationEvents.count) messages in conversation")
        
        for event in conversationEvents {
            let sender = event.pubkey == alicePubkey ? "Alice" : "Bob"
            print("\n💬 From \(sender):")
            
            // Try to decrypt (will only work for messages we can decrypt)
            let senderPubkey = event.pubkey == alicePubkey ? bobPubkey : alicePubkey
            if let decrypted = try? await event.decryptedContent(
                signer: aliceSigner,
                senderPubkey: senderPubkey,
                ndk: aliceNDK
            ) {
                print("   \(decrypted)")
            } else {
                print("   [Encrypted - cannot decrypt]")
            }
        }
        
        // Step 7: Disconnect
        await aliceNDK.disconnect()
        await bobNDK.disconnect()
        
        print("\n📚 Key Concepts:")
        print("- Encrypted DMs use kind 4 events")
        print("- NIP-04 is the original encryption standard")
        print("- NIP-44 is the newer, more secure standard")
        print("- Messages are encrypted using the sender's private key and recipient's public key")
        print("- Only the sender and recipient can decrypt the messages")
        print("- The 'p' tag indicates the recipient")
    }
}