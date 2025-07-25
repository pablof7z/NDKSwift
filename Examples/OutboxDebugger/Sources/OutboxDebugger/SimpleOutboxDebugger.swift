import Foundation
import NDKSwift

@main
struct SimpleOutboxDebugger {
    static func main() async {
        // Configure NDKLogger to show what we care about
        NDKLogger.configure(
            logLevel: .trace,
            enabledCategories: [.relay, .subscription, .outbox, .event]
        )
        
        print("🚀 Outbox Debugger Started")
        print("📡 Connecting to relay.primal.net...")
        print("=" * 80)
        
        // Generate private key
        let signer = try! NDKPrivateKeySigner.generate()
        let pubkey = try! await signer.pubkey
        let npub = try! pubkey.npub()
        
        print("🔑 Generated key: \(npub)")
        print("=" * 80)
        
        // Create NDK instance
        let ndk = NDK(
            relayUrls: ["wss://relay.primal.net"],
            signer: signer
        )
        
        // Connect
        await ndk.connect()
        
        // Wait a bit for connection
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        
        let (connected, total) = await ndk.getRelayConnectionSummary()
        print("📊 Connected to \(connected)/\(total) relays")
        print("=" * 80)
        
        // Simple command loop
        print("\nCommands:")
        print("  outbox <npub>     - Show outbox info for npub")
        print("  publish <npub>... - Publish event tagging npubs") 
        print("  req <npub>...     - Fetch recent events from npubs")
        print("  exit              - Exit")
        print("")
        
        while true {
            print("\n> ", terminator: "")
            fflush(stdout)
            
            guard let line = readLine() else { break }
            let parts = line.split(separator: " ").map(String.init)
            guard !parts.isEmpty else { continue }
            
            let command = parts[0].lowercased()
            let args = Array(parts.dropFirst())
            
            switch command {
            case "exit":
                print("👋 Goodbye!")
                exit(0)
                
            case "outbox":
                await handleOutbox(ndk: ndk, npubs: args)
                
            case "publish":
                await handlePublish(ndk: ndk, signer: signer, npubs: args)
                
            case "req":
                await handleReq(ndk: ndk, npubs: args)
                
            default:
                print("❌ Unknown command: \(command)")
            }
        }
    }
    
    static func handleOutbox(ndk: NDK, npubs: [String]) async {
        guard !npubs.isEmpty else {
            print("Usage: outbox <npub>...")
            return
        }
        
        print("\n🔍 Checking outbox for \(npubs.count) npub(s)...")
        
        for npub in npubs {
            guard let pubkey = try? String.fromNpub(npub) else {
                print("❌ Invalid npub: \(npub)")
                continue
            }
            
            print("\n📦 Outbox for \(npub):")
            
            if let outboxInfo = await ndk.outbox.getCachedOutbox(for: pubkey) {
                print("  Read relays (\(outboxInfo.readRelays.count)):")
                for relay in outboxInfo.readRelays {
                    print("    • \(relay.url)")
                }
                
                print("  Write relays (\(outboxInfo.writeRelays.count)):")
                for relay in outboxInfo.writeRelays {
                    print("    • \(relay.url)")
                }
            } else {
                print("  ⚠️ No outbox information cached")
            }
        }
    }
    
    static func handlePublish(ndk: NDK, signer: NDKSigner, npubs: [String]) async {
        guard !npubs.isEmpty else {
            print("Usage: publish <npub>...")
            return
        }
        
        print("\n📝 Publishing event...")
        
        var tags: [[String]] = []
        for npub in npubs {
            guard let pubkey = try? String.fromNpub(npub) else {
                print("⚠️ Skipping invalid npub: \(npub)")
                continue
            }
            tags.append(["p", pubkey])
        }
        
        let content = "Test from Outbox Debugger at \(Date())"
        
        let event = try! await NDKEventBuilder(ndk: ndk)
            .content(content)
            .kind(EventKind.textNote)
            .tags(tags)
            .build(signer: signer)
        
        print("📤 Event ID: \(event.id)")
        print("   Content: \(content)")
        print("   Tagged: \(tags.count) users")
        
        print("\n🚀 Publishing to relays...")
        
        let relays = try! await ndk.publish(event)
        
        print("\n✅ Published to \(relays.count) relay(s):")
        for relay in relays {
            print("   • \(relay.url)")
        }
    }
    
    static func handleReq(ndk: NDK, npubs: [String]) async {
        guard !npubs.isEmpty else {
            print("Usage: req <npub>...")
            return
        }
        
        print("\n🔍 Fetching recent events for \(npubs.count) npub(s)...")
        
        var pubkeys: [String] = []
        for npub in npubs {
            guard let pubkey = try? String.fromNpub(npub) else {
                print("❌ Invalid npub: \(npub)")
                continue
            }
            pubkeys.append(pubkey)
        }
        
        guard !pubkeys.isEmpty else { return }
        
        let filter = NDKFilter(
            authors: pubkeys,
            kinds: [EventKind.textNote],
            limit: 5
        )
        
        print("📡 Creating subscription with filter:")
        print("   Authors: \(pubkeys.count)")
        print("   Kinds: [1]")
        print("   Limit: 5")
        
        // Use NDK's observe to get real-time updates
        let dataSource = ndk.observe(filter: filter)
        
        print("\n⏳ Waiting for events...")
        
        var eventCount = 0
        let startTime = Date()
        let timeout: TimeInterval = 10.0
        
        // Process events as they arrive
        for await event in dataSource.events {
            eventCount += 1
            print("\n📨 Event #\(eventCount):")
            print("   ID: \(event.id)")
            print("   Author: \(event.pubkey.prefix(16))...")
            print("   Created: \(Date(timeIntervalSince1970: TimeInterval(event.createdAt)))")
            print("   Content: \(event.content.prefix(100))\(event.content.count > 100 ? "..." : "")")
            
            // Check timeout
            if Date().timeIntervalSince(startTime) > timeout {
                print("\n⏱️ Timeout reached after \(timeout)s")
                break
            }
        }
        
        if eventCount == 0 {
            print("\n📭 No events found")
        } else {
            print("\n✅ Received \(eventCount) event(s)")
        }
    }
}

// Helper extension
extension String {
    static func *(lhs: String, rhs: Int) -> String {
        String(repeating: lhs, count: rhs)
    }
}