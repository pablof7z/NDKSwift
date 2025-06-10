#!/usr/bin/env swift

import Foundation
import NDKSwift

// NIP-44 Encrypted Chat CLI
// A simple mIRC-inspired chat application using Nostr

@main
struct SecureChatCLI {
    static func main() async {
        print("╔════════════════════════════════════════════════════════════════╗")
        print("║          🔐 Nostr Secure Chat (NIP-44 Encrypted)              ║")
        print("║                    Kind 9999 Messages                          ║")
        print("╚════════════════════════════════════════════════════════════════╝")
        print()
        
        // Get user credentials
        guard let (signer, userPubkey, userNpub) = await setupUser() else {
            print("❌ Failed to setup user")
            return
        }
        
        // Get recipient
        guard let (recipientPubkey, recipientNpub) = getRecipient() else {
            print("❌ Failed to get recipient")
            return
        }
        
        // Initialize NDK
        let ndk = NDK()
        ndk.signer = signer
        
        // Add relays
        print("\n📡 Connecting to relays...")
        let relays = [
            "wss://relay.damus.io",
            "wss://relay.nostr.band",
            "wss://nos.lol",
            "wss://relay.primal.net"
        ]
        
        for relayUrl in relays {
            _ = try? await ndk.relay(relayUrl)
        }
        
        // Wait a bit for connections
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        print("✅ Connected to \(ndk.pool.relays.count) relays")
        print("\n═══════════════════════════════════════════════════════════════════")
        print("💬 Chat Session Started")
        print("═══════════════════════════════════════════════════════════════════")
        print("You: \(userNpub)")
        print("Recipient: \(recipientNpub)")
        print("═══════════════════════════════════════════════════════════════════")
        print("\nCommands:")
        print("  /quit - Exit the chat")
        print("  /status - Show connection status")
        print("  /clear - Clear the screen")
        print("\n")
        
        // Start message listener in background
        let messageTask = Task {
            await listenForMessages(
                ndk: ndk,
                userPubkey: userPubkey,
                recipientPubkey: recipientPubkey,
                signer: signer
            )
        }
        
        // Main chat loop
        await chatLoop(
            ndk: ndk,
            signer: signer,
            userPubkey: userPubkey,
            recipientPubkey: recipientPubkey
        )
        
        // Clean up
        messageTask.cancel()
        await ndk.disconnect()
        print("\n👋 Chat session ended")
    }
    
    static func setupUser() async -> (NDKPrivateKeySigner, String, String)? {
        print("\n🔑 User Setup")
        print("─────────────")
        print("Enter your nsec (or press Enter to generate new identity):")
        
        guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }
        
        do {
            let signer: NDKPrivateKeySigner
            
            if input.isEmpty {
                // Generate new identity
                signer = try NDKPrivateKeySigner.generate()
                print("\n🆕 Generated new identity:")
                print("nsec: \(try signer.nsec)")
                print("npub: \(try signer.npub)")
                print("\n⚠️  Save your nsec to use this identity again!")
            } else {
                // Use provided nsec
                signer = try NDKPrivateKeySigner(nsec: input)
                print("✅ Loaded identity: \(try signer.npub)")
            }
            
            let pubkey = try await signer.pubkey
            let npub = try signer.npub
            
            return (signer, pubkey, npub)
        } catch {
            print("❌ Error: \(error)")
            return nil
        }
    }
    
    static func getRecipient() -> (String, String)? {
        print("\n👤 Recipient Setup")
        print("──────────────────")
        print("Enter recipient's npub:")
        
        guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !input.isEmpty else {
            return nil
        }
        
        do {
            let pubkey = try Bech32.publicKey(from: input)
            return (pubkey, input)
        } catch {
            print("❌ Invalid npub: \(error)")
            return nil
        }
    }
    
    static func chatLoop(
        ndk: NDK,
        signer: NDKPrivateKeySigner,
        userPubkey: String,
        recipientPubkey: String
    ) async {
        while true {
            // Show prompt
            print("[You] ", terminator: "")
            fflush(stdout)
            
            guard let input = readLine() else {
                break
            }
            
            let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Handle commands
            if trimmed.hasPrefix("/") {
                if await handleCommand(trimmed, ndk: ndk) {
                    break
                }
                continue
            }
            
            // Skip empty messages
            if trimmed.isEmpty {
                continue
            }
            
            // Send message
            do {
                try await sendMessage(
                    content: trimmed,
                    ndk: ndk,
                    signer: signer,
                    recipientPubkey: recipientPubkey
                )
            } catch {
                print("❌ Failed to send: \(error)")
            }
        }
    }
    
    static func handleCommand(_ command: String, ndk: NDK) async -> Bool {
        switch command.lowercased() {
        case "/quit", "/exit":
            return true
            
        case "/status":
            print("\n📊 Connection Status")
            print("───────────────────")
            for relay in ndk.pool.relays {
                let state = relay.connectionState
                let icon = state == .connected ? "🟢" : "🔴"
                print("\(icon) \(relay.url): \(state)")
            }
            print()
            
        case "/clear":
            print("\u{001B}[2J\u{001B}[H") // ANSI clear screen
            print("═══════════════════════════════════════════════════════════════════")
            print("💬 Chat Session (cleared)")
            print("═══════════════════════════════════════════════════════════════════")
            
        default:
            print("Unknown command: \(command)")
        }
        
        return false
    }
    
    static func sendMessage(
        content: String,
        ndk: NDK,
        signer: NDKPrivateKeySigner,
        recipientPubkey: String
    ) async throws {
        // Encrypt message with NIP-44
        let recipient = NDKUser(pubkey: recipientPubkey)
        let encrypted = try await signer.encrypt(
            recipient: recipient,
            value: content,
            scheme: .nip44
        )
        
        // Create event
        let event = NDKEvent(
            pubkey: try await signer.pubkey,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: 9999, // Custom kind for encrypted chat
            tags: [
                ["p", recipientPubkey], // Tag recipient
                ["encrypted", "nip44"]  // Indicate encryption method
            ],
            content: encrypted
        )
        
        // Sign and publish
        try await event.sign(using: signer)
        let published = try await ndk.publish(event)
        
        if !published.isEmpty {
            // Message sent successfully - no need to print anything
            // as it will appear in our own feed
        } else {
            print("⚠️  Message may not have been sent to all relays")
        }
    }
    
    static func listenForMessages(
        ndk: NDK,
        userPubkey: String,
        recipientPubkey: String,
        signer: NDKPrivateKeySigner
    ) async {
        // Create filter for messages between user and recipient
        let filter = NDKFilter(
            kinds: [9999],
            authors: [userPubkey, recipientPubkey],
            tags: [
                "p": [userPubkey, recipientPubkey]
            ]
        )
        
        // Subscribe to messages
        let subscription = await ndk.subscribe(filter)
        
        // Keep track of seen events to avoid duplicates
        var seenEvents = Set<String>()
        
        // Listen for messages
        do {
            for await event in subscription {
                guard let eventId = event.id,
                      !seenEvents.contains(eventId) else {
                    continue
                }
                seenEvents.insert(eventId)
                
                // Check if it's encrypted with NIP-44
                let isNip44 = event.tags.contains { tag in
                    tag.count >= 2 && tag[0] == "encrypted" && tag[1] == "nip44"
                }
                
                guard isNip44 else {
                    continue
                }
                
                // Decrypt and display
                await displayMessage(
                    event: event,
                    userPubkey: userPubkey,
                    recipientPubkey: recipientPubkey,
                    signer: signer
                )
            }
        } catch {
            print("\n⚠️  Message stream interrupted: \(error)")
        }
    }
    
    static func displayMessage(
        event: NDKEvent,
        userPubkey: String,
        recipientPubkey: String,
        signer: NDKPrivateKeySigner
    ) async {
        do {
            let isOwnMessage = event.pubkey == userPubkey
            let sender = isOwnMessage ? 
                NDKUser(pubkey: recipientPubkey) : 
                NDKUser(pubkey: event.pubkey)
            
            // Decrypt message
            let decrypted = try await signer.decrypt(
                sender: sender,
                value: event.content,
                scheme: .nip44
            )
            
            // Format timestamp
            let date = Date(timeIntervalSince1970: TimeInterval(event.createdAt))
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            let timeStr = formatter.string(from: date)
            
            // Clear current line and display message
            print("\r\u{001B}[K", terminator: "") // Clear line
            
            if isOwnMessage {
                // Our own message
                print("[\(timeStr)] <You> \(decrypted)")
            } else {
                // Message from recipient
                let shortPubkey = String(event.pubkey.prefix(8))
                print("[\(timeStr)] <\(shortPubkey)...> \(decrypted)")
            }
            
            // Restore prompt
            print("[You] ", terminator: "")
            fflush(stdout)
            
        } catch {
            // Silently ignore decryption errors (might be messages for others)
        }
    }
}

// Extensions for better display
extension NDKRelayConnectionState: CustomStringConvertible {
    public var description: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting"
        case .connected: return "Connected"
        case .disconnecting: return "Disconnecting"
        case .error: return "Error"
        }
    }
}