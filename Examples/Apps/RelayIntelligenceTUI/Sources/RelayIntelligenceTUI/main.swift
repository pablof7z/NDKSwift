import Foundation
import NDKSwiftCore

@main
struct OutboxTest {
    /// Resolve NIP-05 identifier to pubkey
    static func resolveNIP05(_ identifier: String) async throws -> String? {
        // Parse identifier: name@domain or _@domain
        let parts = identifier.split(separator: "@")
        guard parts.count == 2 else { return nil }

        let name = String(parts[0])
        let domain = String(parts[1])

        // Fetch .well-known/nostr.json
        guard let url = URL(string: "https://\(domain)/.well-known/nostr.json?name=\(name)") else {
            return nil
        }

        let (data, _) = try await URLSession.shared.data(from: url)

        // Parse JSON
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let names = json["names"] as? [String: String],
              let pubkey = names[name] else {
            return nil
        }

        return pubkey
    }

    static func main() async throws {
        // Parse command line arguments
        guard CommandLine.arguments.count > 1 else {
            print("Usage: outbox-test <npub|pubkey|nip05>")
            print("Examples:")
            print("  outbox-test npub1sg6plzptd64u62a878hep2kev3zw7gnway9epr")
            print("  outbox-test _@dergigi.com")
            exit(1)
        }

        let input = CommandLine.arguments[1]

        print("🚀 Outbox Relay Intelligence Test")
        print(String(repeating: "=", count: 50))
        
        // Initialize NDK with only purplepag.es as outbox relay
        print("\n📦 Initializing NDK...")
        print("   Outbox relay: wss://purplepag.es")
        print("   App relays: none")
        
        let ndk = NDK(
            relayURLs: [],
            cache: MemoryCache(),
            debugMode: true,
            outboxEnabled: true,
            outboxConfig: NDKOutboxConfig(
                blacklistedRelays: [],
                outboxRelays: ["wss://purplepag.es"]
            )
        )
        
        // Monitor relay pool changes
        Task {
            for await change in await ndk.pool.relayChanges {
                switch change {
                case .relayAdded(let relay):
                    print("🔌 Relay added: \(relay.url)")
                case .relayConnected(let relay):
                    print("✅ Relay connected: \(relay.url)")
                case .relayDisconnected(let relay):
                    print("❌ Relay disconnected: \(relay.url)")
                case .relayRemoved(let url):
                    print("🗑️  Relay removed: \(url)")
                }
            }
        }
        
        // Monitor relay discoveries
        Task {
            for await discovery in ndk.outbox.relayDiscoveries {
                print("📡 Discovery: \(discovery.pubkey.prefix(8))... found \(discovery.readRelays.count) read, \(discovery.writeRelays.count) write relays")
                if !discovery.readRelays.isEmpty {
                    let relayList = discovery.readRelays.sorted().prefix(3).joined(separator: ", ")
                    print("   Read relays: \(relayList)\(discovery.readRelays.count > 3 ? " ..." : "")")
                }
            }
        }
        
        // Connect to relays
        print("\n🔌 Connecting to relays...")
        await ndk.connect()
        
        // Small delay to let connection establish
        try await Task.sleep(for: .seconds(2))

        // Resolve input to hex pubkey
        let pubkey: String
        if input.hasPrefix("npub") {
            // Bech32 npub
            let decoded = try Bech32.decode(input).data
            pubkey = decoded.map { String(format: "%02x", $0) }.joined()
            print("\n👤 User: \(input)")
            print("   Pubkey: \(pubkey)")
        } else if input.contains("@") {
            // NIP-05 identifier
            print("\n🔍 Resolving NIP-05: \(input)...")
            guard let resolved = try await resolveNIP05(input) else {
                print("❌ Failed to resolve NIP-05 identifier")
                exit(1)
            }
            pubkey = resolved
            print("👤 User: \(input)")
            print("   Pubkey: \(pubkey)")
        } else {
            // Assume hex pubkey
            pubkey = input
            print("\n👤 Pubkey: \(pubkey)")
        }
        
        // Fetch kind:3 contact list
        print("\n📋 Fetching contact list (kind:3)...")
        let contactListFilter = NDKFilter(
            authors: [pubkey],
            kinds: [3]
        )
        
        let contactSubscription = NDKSubscription(
            ndk: ndk,
            filter: contactListFilter,
            maxAge: 60
        )
        
        let contactEvents = await contactSubscription.collect(timeout: 10.0)
        guard let contactEvent = contactEvents.mostRecent else {
            print("❌ No contact list found for this user")
            exit(1)
        }
        
        // Extract follow pubkeys
        let followPubkeys = contactEvent.tags
            .filter { $0.first == "p" }
            .compactMap { $0.dropFirst().first }
            .map { String($0) }
        
        print("   Found \(followPubkeys.count) follows")
        
        guard !followPubkeys.isEmpty else {
            print("❌ User has no follows")
            exit(1)
        }
        
        // Show pool status before subscription
        let poolBefore = await ndk.pool.relays.count
        print("\n📊 Pool status before subscription:")
        print("   Total relays: \(poolBefore)")
        
        // Create subscription for kinds:[1] from follows
        print("\n📡 Creating subscription for kinds:[1] from \(followPubkeys.count) authors...")
        print("   This should trigger outbox relay discovery!")
        
        let feedFilter = NDKFilter(
            authors: followPubkeys,
            kinds: [1],
            limit: 50
        )
        
        let feedSubscription = NDKSubscription(
            ndk: ndk,
            filter: feedFilter,
            maxAge: 0
        )
        
        // Monitor events (silently count)
        var eventCount = 0
        Task {
            for await batch in feedSubscription.events {
                eventCount += batch.count
            }
        }
        
        // Wait for discoveries to happen
        print("\n⏳ Waiting for relay discoveries (15 seconds)...")
        try await Task.sleep(for: .seconds(15))
        
        // Show final pool status
        let relays = await ndk.pool.relays
        var connected = 0
        var persistentCount = 0
        var dynamicCount = 0
        
        for relay in relays {
            let connectionState = await relay.connectionState
            if connectionState == .connected {
                connected += 1
            }
            if await relay.isPersistent {
                persistentCount += 1
            } else {
                dynamicCount += 1
            }
        }
        
        print("\n📊 Final pool status:")
        print("   Total relays: \(relays.count)")
        print("   Connected: \(connected)")
        print("   Persistent: \(persistentCount)")
        print("   Dynamic: \(dynamicCount)")
        print("   Events received: \(eventCount)")
        
        print("\n🎯 Relay breakdown:")
        for relay in relays.sorted(by: { $0.url < $1.url }) {
            let connectionState = await relay.connectionState
            let isPersist = await relay.isPersistent
            let origin = await relay.origin
            let status = connectionState == .connected ? "✅" : "❌"
            let type = isPersist ? "persistent" : "dynamic"
            print("   \(status) \(relay.url) (\(type), origin: \(origin))")
        }

        print("\n✨ Test complete!")
    }
}
