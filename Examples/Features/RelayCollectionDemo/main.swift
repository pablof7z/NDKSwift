// RelayCollectionDemo - Demonstrates the new NDKRelayCollection API

import Foundation
import NDKSwift

@MainActor
class RelayDemo {
    let ndk: NDK
    let relayCollection: NDKRelayCollection

    init() {
        // Initialize NDK with some relays
        ndk = NDK(relayUrls: [
            "wss://relay.damus.io",
            "wss://nos.lol",
            "wss://relay.snort.social",
        ])

        // Create relay collection for observing
        relayCollection = ndk.createRelayCollection()
    }

    func run() async {
        print("🚀 NDKSwift Relay Collection Demo")
        print("=================================\n")

        // Connect to all relays
        print("Connecting to relays...")
        await ndk.connect()

        // Print initial state immediately
        print("\nInitial state:")

        // Print current state
        await printRelayStates()

        // Get quick summary
        let summary = await ndk.getRelayConnectionSummary()
        print("\n📊 Connection Summary: \(summary.connected)/\(summary.total) relays connected")

        // Add a new relay
        print("\n➕ Adding new relay: wss://relay.nostr.band")
        await relayCollection.addRelay("wss://relay.nostr.band")

        // Wait a bit
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        // Print updated state
        await printRelayStates()

        // Disconnect
        print("\n🔌 Disconnecting all relays...")
        await ndk.disconnect()

        try? await Task.sleep(nanoseconds: 500_000_000)
        await printRelayStates()
    }

    func printRelayStates() async {
        print("\n📡 Relay States:")
        print("---------------")

        let relays = relayCollection.relays
        for relay in relays {
            let status = relay.isConnected ? "✅" : "❌"
            let state = switch relay.state {
            case .connected: "connected"
            case .connecting: "connecting..."
            case .disconnected: "disconnected"
            case .disconnecting: "disconnecting..."
            case let .failed(error): "failed: \(error)"
            case let .authRequired(challenge): "auth required: \(challenge)"
            case .authenticating: "authenticating..."
            case .authenticated: "authenticated"
            }

            print("\(status) \(relay.url) - \(state)")

            if let lastConnected = relay.lastConnectedAt {
                let formatter = RelativeDateTimeFormatter()
                formatter.unitsStyle = .abbreviated
                let relative = formatter.localizedString(for: lastConnected, relativeTo: Date())
                print("   Last connected: \(relative)")
            }
        }

        print("\nConnected: \(relayCollection.connectedCount)/\(relayCollection.totalCount)")
    }
}

// Run the demo
@main
struct Main {
    static func main() async {
        let demo = RelayDemo()
        await demo.run()

        print("\n✨ Demo complete!")
    }
}
