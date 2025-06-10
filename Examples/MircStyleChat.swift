#!/usr/bin/env swift

import Foundation
import NDKSwift

// mIRC-style Nostr Chat Client
// Features: NIP-44 encryption, colored output, chat history, multi-relay support

// ANSI color codes
struct Colors {
    static let reset = "\u{001B}[0m"
    static let bold = "\u{001B}[1m"
    static let dim = "\u{001B}[2m"
    
    static let black = "\u{001B}[30m"
    static let red = "\u{001B}[31m"
    static let green = "\u{001B}[32m"
    static let yellow = "\u{001B}[33m"
    static let blue = "\u{001B}[34m"
    static let magenta = "\u{001B}[35m"
    static let cyan = "\u{001B}[36m"
    static let white = "\u{001B}[37m"
    
    static let bgBlack = "\u{001B}[40m"
    static let bgWhite = "\u{001B}[47m"
}

// Chat message for history
struct ChatMessage {
    let timestamp: Date
    let sender: String
    let content: String
    let isOwn: Bool
}

@main
struct MircStyleChat {
    static var chatHistory: [ChatMessage] = []
    static let maxHistory = 100
    
    static func main() async {
        clearScreen()
        showBanner()
        
        // Setup
        guard let (signer, userPubkey, userNpub) = await setupUser() else {
            printError("Failed to setup user")
            return
        }
        
        guard let (recipientPubkey, recipientNpub, recipientName) = await getRecipient() else {
            printError("Failed to get recipient")
            return
        }
        
        // Initialize NDK
        let ndk = NDK()
        ndk.signer = signer
        
        // Connect to relays
        await connectToRelays(ndk)
        
        clearScreen()
        showChatHeader(userNpub: userNpub, recipientName: recipientName, recipientNpub: recipientNpub)
        
        // Start message listener
        let messageTask = Task {
            await listenForMessages(
                ndk: ndk,
                userPubkey: userPubkey,
                recipientPubkey: recipientPubkey,
                signer: signer,
                recipientName: recipientName
            )
        }
        
        // Load recent history
        printStatus("Loading message history...")
        await loadRecentHistory(
            ndk: ndk,
            userPubkey: userPubkey,
            recipientPubkey: recipientPubkey,
            signer: signer,
            recipientName: recipientName
        )
        
        // Main chat loop
        await chatLoop(
            ndk: ndk,
            signer: signer,
            userPubkey: userPubkey,
            recipientPubkey: recipientPubkey,
            recipientName: recipientName
        )
        
        // Cleanup
        messageTask.cancel()
        await ndk.disconnect()
        
        clearScreen()
        print("\(Colors.yellow)════════════════════════════════════════\(Colors.reset)")
        print("\(Colors.yellow)    Thanks for using Nostr Chat!        \(Colors.reset)")
        print("\(Colors.yellow)════════════════════════════════════════\(Colors.reset)")
    }
    
    static func clearScreen() {
        print("\u{001B}[2J\u{001B}[H")
    }
    
    static func showBanner() {
        print("\(Colors.cyan)╔══════════════════════════════════════════════════════════════════╗\(Colors.reset)")
        print("\(Colors.cyan)║\(Colors.reset)  \(Colors.bold)\(Colors.yellow)     _   _  ___  ____ _____ ____     ____ _   _    _  _____    \(Colors.reset)\(Colors.cyan)║\(Colors.reset)")
        print("\(Colors.cyan)║\(Colors.reset)  \(Colors.bold)\(Colors.yellow)    | \\ | |/ _ \\/ ___|_   _|  _ \\   / ___| | | |  / \\|_   _|   \(Colors.reset)\(Colors.cyan)║\(Colors.reset)")
        print("\(Colors.cyan)║\(Colors.reset)  \(Colors.bold)\(Colors.yellow)    |  \\| | | | \\___ \\ | | | |_) | | |   | |_| | / _ \\ | |     \(Colors.reset)\(Colors.cyan)║\(Colors.reset)")
        print("\(Colors.cyan)║\(Colors.reset)  \(Colors.bold)\(Colors.yellow)    | |\\  | |_| |___) || | |  _ <  | |___|  _  |/ ___ \\| |     \(Colors.reset)\(Colors.cyan)║\(Colors.reset)")
        print("\(Colors.cyan)║\(Colors.reset)  \(Colors.bold)\(Colors.yellow)    |_| \\_|\\___/|____/ |_| |_| \\_\\  \\____|_| |_/_/   \\_\\_|     \(Colors.reset)\(Colors.cyan)║\(Colors.reset)")
        print("\(Colors.cyan)║\(Colors.reset)                                                                  \(Colors.cyan)║\(Colors.reset)")
        print("\(Colors.cyan)║\(Colors.reset)              \(Colors.green)🔐 NIP-44 Encrypted • Kind 9999 Events\(Colors.reset)             \(Colors.cyan)║\(Colors.reset)")
        print("\(Colors.cyan)╚══════════════════════════════════════════════════════════════════╝\(Colors.reset)")
        print()
    }
    
    static func showChatHeader(userNpub: String, recipientName: String, recipientNpub: String) {
        print("\(Colors.bgWhite)\(Colors.black) NOSTR CHAT v1.0 - Secure Messaging \(Colors.reset)")
        print("\(Colors.dim)─────────────────────────────────────────────────────────────────────\(Colors.reset)")
        print("\(Colors.green)●\(Colors.reset) You: \(Colors.cyan)\(userNpub.prefix(20))...\(Colors.reset)")
        print("\(Colors.green)●\(Colors.reset) Chatting with: \(Colors.magenta)\(recipientName)\(Colors.reset) (\(Colors.dim)\(recipientNpub.prefix(20))...\(Colors.reset))")
        print("\(Colors.dim)─────────────────────────────────────────────────────────────────────\(Colors.reset)")
        print()
    }
    
    static func setupUser() async -> (NDKPrivateKeySigner, String, String)? {
        print("\(Colors.yellow)User Setup\(Colors.reset)")
        print("\(Colors.dim)──────────\(Colors.reset)")
        print("Enter your \(Colors.cyan)nsec\(Colors.reset) (or press \(Colors.green)Enter\(Colors.reset) to generate new identity):")
        print("> ", terminator: "")
        
        guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }
        
        do {
            let signer: NDKPrivateKeySigner
            
            if input.isEmpty {
                signer = try NDKPrivateKeySigner.generate()
                print("\n\(Colors.green)✨ Generated new identity:\(Colors.reset)")
                print("  \(Colors.bold)nsec:\(Colors.reset) \(Colors.red)\(try signer.nsec)\(Colors.reset)")
                print("  \(Colors.bold)npub:\(Colors.reset) \(Colors.cyan)\(try signer.npub)\(Colors.reset)")
                print("\n\(Colors.yellow)⚠️  Save your nsec to use this identity again!\(Colors.reset)")
                print("\nPress Enter to continue...")
                _ = readLine()
            } else {
                signer = try NDKPrivateKeySigner(nsec: input)
                print("\(Colors.green)✓\(Colors.reset) Loaded identity: \(Colors.cyan)\(try signer.npub)\(Colors.reset)")
            }
            
            let pubkey = try await signer.pubkey
            let npub = try signer.npub
            
            return (signer, pubkey, npub)
        } catch {
            printError("Invalid nsec: \(error)")
            return nil
        }
    }
    
    static func getRecipient() async -> (String, String, String)? {
        print("\n\(Colors.yellow)Recipient Setup\(Colors.reset)")
        print("\(Colors.dim)───────────────\(Colors.reset)")
        print("Enter recipient's \(Colors.cyan)npub\(Colors.reset):")
        print("> ", terminator: "")
        
        guard let npub = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !npub.isEmpty else {
            return nil
        }
        
        print("Enter a nickname for this person (optional):")
        print("> ", terminator: "")
        
        let nickname = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        do {
            let pubkey = try Bech32.publicKey(from: npub)
            let name = nickname.isEmpty ? String(pubkey.prefix(8)) : nickname
            return (pubkey, npub, name)
        } catch {
            printError("Invalid npub: \(error)")
            return nil
        }
    }
    
    static func connectToRelays(_ ndk: NDK) async {
        print("\n\(Colors.yellow)Connecting to relays...\(Colors.reset)")
        
        let relays = [
            "wss://relay.damus.io",
            "wss://relay.nostr.band",
            "wss://nos.lol",
            "wss://relay.primal.net",
            "wss://relay.snort.social"
        ]
        
        for relayUrl in relays {
            print("  \(Colors.dim)→\(Colors.reset) \(relayUrl)", terminator: "")
            do {
                _ = try await ndk.relay(relayUrl)
                print(" \(Colors.green)✓\(Colors.reset)")
            } catch {
                print(" \(Colors.red)✗\(Colors.reset)")
            }
        }
        
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        
        let connectedCount = ndk.pool.relays.filter { $0.connectionState == .connected }.count
        print("\n\(Colors.green)Connected to \(connectedCount) relays\(Colors.reset)")
        print("\nPress Enter to start chatting...")
        _ = readLine()
    }
    
    static func loadRecentHistory(
        ndk: NDK,
        userPubkey: String,
        recipientPubkey: String,
        signer: NDKPrivateKeySigner,
        recipientName: String
    ) async {
        // Create filter for last 24 hours of messages
        let since = Timestamp(Date().timeIntervalSince1970 - 86400) // 24 hours ago
        
        let filter = NDKFilter(
            kinds: [9999],
            authors: [userPubkey, recipientPubkey],
            tags: ["p": [userPubkey, recipientPubkey]],
            since: since
        )
        
        do {
            let events = try await ndk.fetchEvents(filter)
            
            // Sort by timestamp
            let sortedEvents = events.sorted { $0.createdAt < $1.createdAt }
            
            for event in sortedEvents {
                await processHistoricalMessage(
                    event: event,
                    userPubkey: userPubkey,
                    signer: signer,
                    recipientName: recipientName
                )
            }
            
            if !chatHistory.isEmpty {
                printStatus("Loaded \(chatHistory.count) messages from history")
                displayAllMessages()
            }
        } catch {
            printError("Failed to load history: \(error)")
        }
    }
    
    static func processHistoricalMessage(
        event: NDKEvent,
        userPubkey: String,
        signer: NDKPrivateKeySigner,
        recipientName: String
    ) async {
        // Check if it's NIP-44 encrypted
        let isNip44 = event.tags.contains { tag in
            tag.count >= 2 && tag[0] == "encrypted" && tag[1] == "nip44"
        }
        
        guard isNip44 else { return }
        
        do {
            let isOwnMessage = event.pubkey == userPubkey
            let sender = isOwnMessage ? 
                NDKUser(pubkey: event.tags.first { $0[0] == "p" }?[1] ?? "") : 
                NDKUser(pubkey: event.pubkey)
            
            let decrypted = try await signer.decrypt(
                sender: sender,
                value: event.content,
                scheme: .nip44
            )
            
            let message = ChatMessage(
                timestamp: Date(timeIntervalSince1970: TimeInterval(event.createdAt)),
                sender: isOwnMessage ? "You" : recipientName,
                content: decrypted,
                isOwn: isOwnMessage
            )
            
            chatHistory.append(message)
            
            // Limit history size
            if chatHistory.count > maxHistory {
                chatHistory.removeFirst()
            }
        } catch {
            // Ignore decryption errors
        }
    }
    
    static func displayAllMessages() {
        clearScreen()
        showChatHeader(userNpub: "", recipientName: "", recipientNpub: "")
        
        for message in chatHistory {
            displayChatMessage(message)
        }
    }
    
    static func displayChatMessage(_ message: ChatMessage) {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let timeStr = formatter.string(from: message.timestamp)
        
        if message.isOwn {
            print("\(Colors.dim)[\(timeStr)]\(Colors.reset) \(Colors.cyan)<\(message.sender)>\(Colors.reset) \(message.content)")
        } else {
            print("\(Colors.dim)[\(timeStr)]\(Colors.reset) \(Colors.magenta)<\(message.sender)>\(Colors.reset) \(message.content)")
        }
    }
    
    static func chatLoop(
        ndk: NDK,
        signer: NDKPrivateKeySigner,
        userPubkey: String,
        recipientPubkey: String,
        recipientName: String
    ) async {
        while true {
            // Show input prompt
            print("\n\(Colors.green)>\(Colors.reset) ", terminator: "")
            fflush(stdout)
            
            guard let input = readLine() else {
                break
            }
            
            let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Handle commands
            if trimmed.hasPrefix("/") {
                if await handleCommand(trimmed, ndk: ndk, recipientName: recipientName) {
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
                
                // Add to history immediately
                let message = ChatMessage(
                    timestamp: Date(),
                    sender: "You",
                    content: trimmed,
                    isOwn: true
                )
                chatHistory.append(message)
                if chatHistory.count > maxHistory {
                    chatHistory.removeFirst()
                }
                
                // Clear input line and show message
                print("\u{001B}[1A\u{001B}[2K", terminator: "") // Move up and clear line
                displayChatMessage(message)
                
            } catch {
                printError("Failed to send: \(error)")
            }
        }
    }
    
    static func handleCommand(_ command: String, ndk: NDK, recipientName: String) async -> Bool {
        let parts = command.lowercased().split(separator: " ")
        let cmd = String(parts[0])
        
        switch cmd {
        case "/quit", "/exit", "/q":
            return true
            
        case "/status", "/s":
            print("\n\(Colors.yellow)📊 Connection Status\(Colors.reset)")
            print("\(Colors.dim)───────────────────\(Colors.reset)")
            for relay in ndk.pool.relays {
                let state = relay.connectionState
                let icon = state == .connected ? "\(Colors.green)●\(Colors.reset)" : "\(Colors.red)●\(Colors.reset)"
                print("\(icon) \(relay.url): \(state)")
            }
            
        case "/clear", "/cls":
            displayAllMessages()
            
        case "/help", "/h", "/?":
            print("\n\(Colors.yellow)Available Commands:\(Colors.reset)")
            print("\(Colors.dim)──────────────────\(Colors.reset)")
            print("  \(Colors.cyan)/quit\(Colors.reset), \(Colors.cyan)/q\(Colors.reset)     - Exit the chat")
            print("  \(Colors.cyan)/status\(Colors.reset), \(Colors.cyan)/s\(Colors.reset)   - Show relay connection status")
            print("  \(Colors.cyan)/clear\(Colors.reset), \(Colors.cyan)/cls\(Colors.reset) - Clear and redraw screen")
            print("  \(Colors.cyan)/history\(Colors.reset)       - Show message count")
            print("  \(Colors.cyan)/help\(Colors.reset), \(Colors.cyan)/?\(Colors.reset)     - Show this help")
            
        case "/history":
            print("\n\(Colors.yellow)Message History:\(Colors.reset) \(chatHistory.count) messages")
            
        default:
            print("\(Colors.red)Unknown command:\(Colors.reset) \(command)")
            print("Type \(Colors.cyan)/help\(Colors.reset) for available commands")
        }
        
        return false
    }
    
    static func sendMessage(
        content: String,
        ndk: NDK,
        signer: NDKPrivateKeySigner,
        recipientPubkey: String
    ) async throws {
        let recipient = NDKUser(pubkey: recipientPubkey)
        let encrypted = try await signer.encrypt(
            recipient: recipient,
            value: content,
            scheme: .nip44
        )
        
        let event = NDKEvent(
            pubkey: try await signer.pubkey,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: 9999,
            tags: [
                ["p", recipientPubkey],
                ["encrypted", "nip44"]
            ],
            content: encrypted
        )
        
        try await event.sign(using: signer)
        _ = try await ndk.publish(event)
    }
    
    static func listenForMessages(
        ndk: NDK,
        userPubkey: String,
        recipientPubkey: String,
        signer: NDKPrivateKeySigner,
        recipientName: String
    ) async {
        let filter = NDKFilter(
            kinds: [9999],
            authors: [recipientPubkey], // Only listen for messages from recipient
            tags: ["p": [userPubkey]]   // That are tagged to us
        )
        
        let subscription = await ndk.subscribe(filter)
        var seenEvents = Set<String>()
        
        do {
            for await event in subscription {
                guard let eventId = event.id,
                      !seenEvents.contains(eventId) else {
                    continue
                }
                seenEvents.insert(eventId)
                
                // Check if it's NIP-44
                let isNip44 = event.tags.contains { tag in
                    tag.count >= 2 && tag[0] == "encrypted" && tag[1] == "nip44"
                }
                
                guard isNip44 else { continue }
                
                // Decrypt and display
                do {
                    let sender = NDKUser(pubkey: event.pubkey)
                    let decrypted = try await signer.decrypt(
                        sender: sender,
                        value: event.content,
                        scheme: .nip44
                    )
                    
                    let message = ChatMessage(
                        timestamp: Date(timeIntervalSince1970: TimeInterval(event.createdAt)),
                        sender: recipientName,
                        content: decrypted,
                        isOwn: false
                    )
                    
                    chatHistory.append(message)
                    if chatHistory.count > maxHistory {
                        chatHistory.removeFirst()
                    }
                    
                    // Clear current line and display
                    print("\r\u{001B}[2K", terminator: "")
                    displayChatMessage(message)
                    
                    // Play notification sound (bell)
                    print("\u{0007}", terminator: "")
                    
                    // Restore prompt
                    print("\n\(Colors.green)>\(Colors.reset) ", terminator: "")
                    fflush(stdout)
                    
                } catch {
                    // Ignore decryption errors
                }
            }
        } catch {
            printStatus("Message stream interrupted")
        }
    }
    
    static func printError(_ message: String) {
        print("\(Colors.red)❌ \(message)\(Colors.reset)")
    }
    
    static func printStatus(_ message: String) {
        print("\(Colors.yellow)ℹ️  \(message)\(Colors.reset)")
    }
}