import Foundation
import NDKSwift

// Command-line simulation of the iOS Nostr App
// This demonstrates all the functionality from the iOS app in a CLI format

@main
struct iOSAppDemo {
    static func main() async {
        print("📱 iOS Nostr App Demo (CLI Version)")
        print(String(repeating: "=", count: 50))
        print("This simulates the iOS app functionality\n")
        
        let demo = NostrAppSimulator()
        await demo.run()
    }
}

@MainActor
class NostrAppSimulator {
    private var ndk: NDK?
    private var signer: NDKSigner?
    private var nsec: String = ""
    private var npub: String = ""
    private var pubkey: String = ""
    private var kind1Subscription: NDKSubscription?
    private var kind1Events: Set<String> = []
    private let defaultRelays = [
        "wss://relay.primal.net",
        "wss://relay.damus.io",
        "wss://nos.lol"
    ]
    
    func run() async {
        // Show menu
        print("Choose an option:")
        print("1. Create Account")
        print("2. Login with nsec")
        print("3. Exit")
        
        guard let choice = readLine() else { return }
        
        switch choice {
        case "1":
            await createAccount()
            await mainMenu()
        case "2":
            await loginWithNsec()
            await mainMenu()
        default:
            print("Goodbye!")
            return
        }
    }
    
    private func mainMenu() async {
        while true {
            print("\n📱 Main Menu")
            print("1. Show Account Info")
            print("2. Publish Message")
            print("3. Start Subscription")
            print("4. Show Relay Status")
            print("5. Exit")
            
            guard let choice = readLine() else { continue }
            
            switch choice {
            case "1":
                showAccountInfo()
            case "2":
                await publishMessage()
            case "3":
                await startSubscription()
            case "4":
                showRelayStatus()
            case "5":
                await cleanup()
                return
            default:
                print("Invalid choice")
            }
        }
    }
    
    private func createAccount() async {
        print("\n🔐 Creating new account...")
        
        do {
            // Setup NDK
            ndk = NDK()
            
            // Create signer
            let privateKeySigner = try NDKPrivateKeySigner.generate()
            signer = privateKeySigner
            ndk?.signer = signer
            
            // Get keys
            nsec = try privateKeySigner.nsec
            npub = try privateKeySigner.npub
            pubkey = try await privateKeySigner.pubkey
            
            print("✅ Account created successfully!")
            print("📱 Public Key (npub): \(npub)")
            print("🔐 Private Key (nsec): \(nsec)")
            print("⚠️  Keep your private key secure!")
            
            // Connect to relays
            await connectToRelays()
            
        } catch {
            print("❌ Failed to create account: \(error)")
        }
    }
    
    private func loginWithNsec() async {
        print("\nEnter your nsec (or press Enter to cancel):")
        guard let input = readLine(), !input.isEmpty else {
            print("Cancelled")
            return
        }
        
        guard input.hasPrefix("nsec1") else {
            print("❌ Invalid nsec format. Must start with 'nsec1'")
            return
        }
        
        do {
            // Setup NDK
            ndk = NDK()
            
            // Create signer from nsec
            let privateKeySigner = try NDKPrivateKeySigner(nsec: input)
            signer = privateKeySigner
            ndk?.signer = signer
            
            // Get keys
            nsec = input
            npub = try privateKeySigner.npub
            pubkey = try await privateKeySigner.pubkey
            
            print("✅ Logged in successfully!")
            
            // Connect to relays
            await connectToRelays()
            
        } catch {
            print("❌ Failed to login: \(error)")
        }
    }
    
    private func connectToRelays() async {
        guard let ndk = ndk else { return }
        
        print("\n🌐 Connecting to relays...")
        
        // Add relays
        for relayUrl in defaultRelays {
            _ = ndk.addRelay(relayUrl)
        }
        
        // Connect
        await ndk.connect()
        
        print("✅ Connected to \(ndk.relays.count) relay(s)")
    }
    
    private func showAccountInfo() {
        print("\n👤 Account Information")
        print("Public Key (npub): \(npub)")
        print("Public Key (hex): \(pubkey)")
        print("Connected via: Local key")
    }
    
    private func publishMessage() async {
        print("\nEnter your message:")
        guard let content = readLine(), !content.isEmpty else {
            print("Cancelled")
            return
        }
        
        guard let ndk = ndk else {
            print("❌ NDK not initialized")
            return
        }
        
        print("📤 Publishing message...")
        
        do {
            // Create event
            let event = NDKEvent(
                pubkey: "",
                createdAt: Timestamp(Date().timeIntervalSince1970),
                kind: 1,
                content: content
            )
            event.ndk = ndk
            
            // Sign and publish
            try await event.sign()
            let publishedRelays = try await ndk.publish(event)
            
            print("✅ Message published to \(publishedRelays.count) relay(s)")
            print("📝 Event ID: \(event.id ?? "unknown")")
            
            // Show publish status
            for relay in ndk.relays {
                let status = event.relayPublishStatuses[relay.url] ?? .pending
                print("  - \(relay.url): \(status)")
            }
            
        } catch {
            print("❌ Failed to publish: \(error)")
        }
    }
    
    private func startSubscription() async {
        guard let ndk = ndk else {
            print("❌ NDK not initialized")
            return
        }
        
        // Stop existing subscription
        if let sub = kind1Subscription {
            await sub.close()
        }
        
        print("\n📡 Starting subscription for text notes (kind:1)...")
        print("Press Enter to stop receiving events")
        
        // Create filter
        let filter = NDKFilter(kinds: [1])
        
        // Create subscription
        let subscription = ndk.subscribe(filters: [filter])
        kind1Subscription = subscription
        
        // Start subscription task
        let subscriptionTask = Task {
            await subscription.start()
            
            var receivedEOSE = false
            
            do {
                for try await event in subscription {
                    // Track unique events
                    if let eventId = event.id {
                        if !kind1Events.contains(eventId) {
                            kind1Events.insert(eventId)
                            print("\n📨 New event #\(kind1Events.count)")
                            print("  From: \(String(event.pubkey.prefix(16)))...")
                            print("  Content: \(String(event.content.prefix(100)))\(event.content.count > 100 ? "..." : "")")
                        }
                    }
                    
                    // Check EOSE
                    if !receivedEOSE {
                        let eoseReceived = await subscription.eoseReceived
                        if eoseReceived {
                            receivedEOSE = true
                            print("\n✅ Initial sync complete. Listening for new events...")
                        }
                    }
                }
            } catch {
                print("\n❌ Subscription error: \(error)")
            }
        }
        
        // Wait for user to press Enter
        _ = readLine()
        
        // Cancel subscription
        subscriptionTask.cancel()
        await subscription.close()
        
        print("📡 Subscription stopped. Received \(kind1Events.count) unique events")
    }
    
    private func showRelayStatus() {
        guard let ndk = ndk else {
            print("❌ NDK not initialized")
            return
        }
        
        print("\n🌐 Relay Status")
        print(String(repeating: "-", count: 50))
        
        for relay in ndk.relays {
            let status: String
            switch relay.connectionState {
            case .connected:
                status = "✅ Connected"
            case .connecting:
                status = "🔄 Connecting..."
            case .disconnected:
                status = "❌ Disconnected"
            case .disconnecting:
                status = "🔄 Disconnecting..."
            case .failed(let message):
                status = "❌ Failed: \(message)"
            }
            
            print("\(relay.url)")
            print("  Status: \(status)")
            print("  Messages sent: \(relay.stats.messagesSent)")
            print("  Messages received: \(relay.stats.messagesReceived)")
            if let connectedAt = relay.stats.connectedAt {
                let formatter = DateFormatter()
                formatter.timeStyle = .medium
                print("  Connected at: \(formatter.string(from: connectedAt))")
            }
            print()
        }
    }
    
    private func cleanup() async {
        print("\n🧹 Cleaning up...")
        
        if let sub = kind1Subscription {
            await sub.close()
        }
        
        if let ndk = ndk {
            await ndk.disconnect()
        }
        
        print("👋 Goodbye!")
    }
}

// Helper to simulate MainActor behavior
extension NDKEvent {
    var relayPublishStatuses: [String: PublishStatus] {
        // This would normally be tracked by the event
        // For demo purposes, we'll return a simple status
        var statuses: [String: PublishStatus] = [:]
        if let ndk = self.ndk {
            for relay in ndk.relays {
                if relay.connectionState == .connected {
                    statuses[relay.url] = .succeeded
                } else {
                    statuses[relay.url] = .failed(reason: .connectionFailed)
                }
            }
        }
        return statuses
    }
}

enum PublishStatus {
    case pending
    case succeeded
    case failed(reason: PublishFailureReason)
    case inProgress
    case rateLimited
    case retrying(attempt: Int)
}

enum PublishFailureReason {
    case connectionFailed
    case custom(String)
}
