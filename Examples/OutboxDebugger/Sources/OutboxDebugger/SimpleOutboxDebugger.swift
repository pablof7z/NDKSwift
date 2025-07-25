import Foundation
import NDKSwift

@main
struct TestEventDelivery {
    static func main() async throws {
        // Configure logger - show debug messages to see stack traces
        NDKLogger.configure(logLevel: .debug, enabledCategories: [
            .relay,
            .subscription
        ])
        
        // Check if REPL mode is requested
        let args = CommandLine.arguments
        if args.count > 1 && args[1] == "repl" {
            try await runRepl()
        } else {
            try await runOldMode()
        }
    }
    
    static func runRepl() async throws {
        print("🎮 NDK Outbox REPL")
        print("================")
        print("Commands:")
        print("  outbox [npub]     - Show known outbox info (no fetch)")
        print("  track [npub]      - Track outbox for npub")
        print("  req [npub...]     - Fetch latest event (limit:1, closeOnEose:true)")
        print("  sub [npub...]     - Stream latest events (limit:1, closeOnEose:false)")
        print("  publish [npub...] - Publish event p-tagging npub(s)")
        print("  quit              - Exit REPL")
        print("")
        
        // Initialize NDK
        let ndk = NDK(
            relayUrls: [
                "wss://nos.lol",
            ]
        )
        ndk.outboxEnabled = true
        
        print("📡 Connecting to relays...")
        await ndk.connect()
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        print("✅ Connected\n")
        
        // Active subscriptions
        var activeSubscriptions: [Task<Void, Never>] = []
        
        print("> ", terminator: "")
        fflush(stdout)
        
        while let line = readLine() {
            let components = line.split(separator: " ").map { String($0) }
            guard !components.isEmpty else {
                print("> ", terminator: "")
                fflush(stdout)
                continue
            }
            
            let command = components[0].lowercased()
            let npubs = Array(components.dropFirst())
            
            switch command {
            case "quit", "exit":
                print("👋 Goodbye!")
                // Cancel all active subscriptions
                for sub in activeSubscriptions {
                    sub.cancel()
                }
                return
                
            case "outbox":
                await handleOutboxCommand(ndk: ndk, npubs: npubs)
                
            case "track":
                await handleTrackCommand(ndk: ndk, npubs: npubs)
                
            case "req":
                await handleReqCommand(ndk: ndk, npubs: npubs)
                
            case "sub":
                let task = Task {
                    await handleSubCommand(ndk: ndk, npubs: npubs)
                }
                activeSubscriptions.append(task)
                
            case "publish":
                await handlePublishCommand(ndk: ndk, npubs: npubs)
                
            default:
                print("❌ Unknown command: \(command)")
            }
            
            print("\n> ", terminator: "")
            fflush(stdout)
        }
    }
    
    static func handleOutboxCommand(ndk: NDK, npubs: [String]) async {
        guard !npubs.isEmpty else {
            print("⚠️ Usage: outbox [npub]")
            return
        }
        
        for npub in npubs {
            guard let pubkey = try? Bech32.pubkey(from: npub) else {
                print("❌ Invalid npub: \(npub)")
                continue
            }
            
            print("\n📦 Outbox info for \(npub):")
            print("   Hex: \(pubkey)")
            
            if let outboxItem = await ndk.outboxTracker.getRelaysSyncFor(pubkey: pubkey, type: .both) {
                print("   Read relays (\(outboxItem.readRelays.count)):")
                for relay in outboxItem.readRelays {
                    print("     • \(relay.url)")
                }
                print("   Write relays (\(outboxItem.writeRelays.count)):")
                for relay in outboxItem.writeRelays {
                    print("     • \(relay.url)")
                }
                print("   Source: \(outboxItem.source)")
            } else {
                print("   ⚠️ No outbox info found")
            }
        }
    }
    
    static func handleTrackCommand(ndk: NDK, npubs: [String]) async {
        guard !npubs.isEmpty else {
            print("⚠️ Usage: track [npub]")
            return
        }
        
        for npub in npubs {
            guard let pubkey = try? Bech32.pubkey(from: npub) else {
                print("❌ Invalid npub: \(npub)")
                continue
            }
            
            print("\n🔍 Tracking \(npub)...")
            await ndk.outbox.trackUser(pubkey)
            
            // Check result
            if let outboxItem = await ndk.outboxTracker.getRelaysSyncFor(pubkey: pubkey, type: .both) {
                print("   ✅ Found outbox info:")
                print("   Read relays: \(outboxItem.readRelays.count)")
                print("   Write relays: \(outboxItem.writeRelays.count)")
            } else {
                print("   ⏳ No outbox info found yet")
            }
        }
    }
    
    static func handleReqCommand(ndk: NDK, npubs: [String]) async {
        guard !npubs.isEmpty else {
            print("⚠️ Usage: req [npub...]")
            return
        }
        
        var pubkeys: [String] = []
        for npub in npubs {
            guard let pubkey = try? Bech32.pubkey(from: npub) else {
                print("❌ Invalid npub: \(npub)")
                continue
            }
            pubkeys.append(pubkey)
        }
        
        guard !pubkeys.isEmpty else { return }
        
        let filter = NDKFilter(
            authors: pubkeys,
            kinds: [1],
            limit: 1
        )
        
        print("\n📨 Requesting events for \(pubkeys.count) author(s)...")
        
        // Use observe with closeOnEose: true to fetch and close
        let subscription = ndk.observe(
            filter: filter,
            maxAge: 0,
            cachePolicy: .cacheWithNetwork,
            relays: nil,
            exclusiveRelays: false,
            subscriptionId: nil,
            closeOnEose: true
        )
        
        var foundEvents = false
        for await event in subscription.events {
            foundEvents = true
            print("\n   ✅ Event from \(event.pubkey.prefix(8))...")
            print("      ID: \(event.id)")
            print("      Created: \(Date(timeIntervalSince1970: TimeInterval(event.createdAt)))")
            print("      Content: \(event.content.prefix(100))...")
        }
        
        if !foundEvents {
            print("   ⚠️ No events found")
        }
    }
    
    static func handleSubCommand(ndk: NDK, npubs: [String]) async {
        guard !npubs.isEmpty else {
            print("⚠️ Usage: sub [npub...]")
            return
        }
        
        var pubkeys: [String] = []
        for npub in npubs {
            guard let pubkey = try? Bech32.pubkey(from: npub) else {
                print("❌ Invalid npub: \(npub)")
                continue
            }
            pubkeys.append(pubkey)
        }
        
        guard !pubkeys.isEmpty else { return }
        
        let filter = NDKFilter(
            authors: pubkeys,
            kinds: [1],
            limit: 1
        )
        
        print("\n📡 Subscribing to \(pubkeys.count) author(s)...")
        print("   (Subscription will continue in background)")
        
        let subscription = ndk.observe(
            filter: filter,
            maxAge: 0,
            cachePolicy: .cacheWithNetwork,
            relays: nil,
            exclusiveRelays: false,
            subscriptionId: nil,
            closeOnEose: false
        )
        
        Task {
            for await event in subscription.events {
                print("\n   🔔 New event from \(event.pubkey.prefix(8))...")
                print("      ID: \(event.id)")
                print("      Created: \(Date(timeIntervalSince1970: TimeInterval(event.createdAt)))")
                print("      Content: \(event.content.prefix(100))...")
                print("\n> ", terminator: "")
                fflush(stdout)
            }
        }
    }
    
    static func handlePublishCommand(ndk: NDK, npubs: [String]) async {
        guard !npubs.isEmpty else {
            print("⚠️ Usage: publish [npub...]")
            return
        }
        
        var pubkeys: [String] = []
        for npub in npubs {
            guard let pubkey = try? Bech32.pubkey(from: npub) else {
                print("❌ Invalid npub: \(npub)")
                continue
            }
            pubkeys.append(pubkey)
        }
        
        guard !pubkeys.isEmpty else { return }
        
        // Create a new signer for this event
        let signer: NDKPrivateKeySigner
        do {
            signer = try NDKPrivateKeySigner.generate()
        } catch {
            print("❌ Failed to create signer: \(error)")
            return
        }
        
        // Set the signer on NDK temporarily
        let originalSigner = ndk.signer
        ndk.signer = signer
        
        let signerPubkey: String
        do {
            signerPubkey = try await signer.pubkey
        } catch {
            print("❌ Failed to get pubkey: \(error)")
            ndk.signer = originalSigner
            return
        }
        
        print("\n📤 Publishing event...")
        print("   From: \(signerPubkey.prefix(8))...")
        print("   P-tagging: \(pubkeys.count) user(s)")
        
        do {
            // Use the event builder pattern
            let (publishedEvent, relays) = try await ndk.publish { builder in
                builder
                    .kind(1)
                    .content("Test event from NDK Outbox REPL at \(Date())")
                    .tags(pubkeys.map { ["p", $0] })
            }
            
            print("   ✅ Published! Event ID: \(publishedEvent.id)")
            print("   Published to \(relays.count) relay(s)")
        } catch {
            print("   ❌ Failed to publish: \(error)")
        }
        
        // Restore original signer
        ndk.signer = originalSigner
    }
    
    static func runOldMode() async throws {
        print("🚀 Starting Outbox Event Delivery Test")
        
        // Get npub from command line arguments or use default
        let args = CommandLine.arguments
        let testPubkey = args.count > 1 ? args[1] : "npub1l2vyh47mk2p0qlsku7hg0vn29faehy9hy34ygaclpn66ukqp3afqutajft"
        
        print("👤 Using pubkey: \(testPubkey)")
        
        // Initialize NDK with outbox enabled
        let ndk = NDK(
            relayUrls: [
                "wss://nos.lol",
            ]
        )
        
        // Enable outbox
        ndk.outboxEnabled = true
        
        print("\n📡 Step 1: Connecting to relays...")
        await ndk.connect()
        
        // Wait for connections
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        print("✅ NDK started")
        
        // Convert npub to hex
        let pubkey: String
        do {
            pubkey = try Bech32.pubkey(from: testPubkey)
        } catch {
            print("❌ Failed to decode npub: \(error)")
            return
        }
        
        print("\n🔍 Step 2: Tracking outbox for \(testPubkey)")
        print("   Hex pubkey: \(pubkey)")
        
        // Explicitly track the user to discover their outbox relays
        await ndk.outbox.trackUser(pubkey)
        print("   Started tracking user's outbox relays...")
        
        // The trackUser method should have completed the discovery
        // Let's check if we have the outbox info
        if let outboxItem = await ndk.outboxTracker.getRelaysSyncFor(pubkey: pubkey, type: .both) {
            print("\n📦 Outbox info discovered:")
            print("   Read relays (\(outboxItem.readRelays.count)):")
            for relay in outboxItem.readRelays {
                print("     • \(relay.url)")
            }
            print("   Write relays (\(outboxItem.writeRelays.count)):")
            for relay in outboxItem.writeRelays {
                print("     • \(relay.url)")
            }
            print("   Source: \(outboxItem.source)")
        } else {
            print("⚠️ No outbox info found after tracking - waiting 2 more seconds...")
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            
            // Try again
            if let outboxItem = await ndk.outboxTracker.getRelaysSyncFor(pubkey: pubkey, type: .both) {
                print("\n📦 Outbox info discovered after wait:")
                print("   Read relays (\(outboxItem.readRelays.count)):")
                for relay in outboxItem.readRelays {
                    print("     • \(relay.url)")
                }
                print("   Write relays (\(outboxItem.writeRelays.count)):")
                for relay in outboxItem.writeRelays {
                    print("     • \(relay.url)")
                }
                print("   Source: \(outboxItem.source)")
            } else {
                print("❌ Still no outbox info found for pubkey")
            }
        }
        
        print("\n📨 Step 3: Requesting events using outbox model")
        
        // Create filter for the user's posts (with limit:1)
        let filter = NDKFilter(
            authors: [pubkey],
            kinds: [1],
            limit: 1
        )
        
        print("   Filter: kinds:[1], authors:[\(pubkey.prefix(8))...], limit:1")
        
        print("\n⏳ Step 4: Observing events (streaming continuously)...")
        
        // Start observing with explicit closeOnEose: false
        let subscription = ndk.observe(
            filter: filter,
            maxAge: 0,
            cachePolicy: .cacheWithNetwork,
            relays: nil,
            exclusiveRelays: false,
            subscriptionId: nil,
            closeOnEose: false  // Explicitly set to false
        )
        
        print("   Subscription started with closeOnEose: false")
        
        // Stream events continuously
        for await event in subscription.events {
            print("\n✅ EVENT RECEIVED!")
            print("   ID: \(event.id)")
            print("   Author: \(event.pubkey.prefix(8))...")
            print("   Created: \(Date(timeIntervalSince1970: TimeInterval(event.createdAt)))")
            print("   Content: \(event.content)")
            print("   Tags: \(event.tags.count) tags")
            print("   ----")
        }
        
        print("\n⚠️ Subscription ended unexpectedly")
    }
}