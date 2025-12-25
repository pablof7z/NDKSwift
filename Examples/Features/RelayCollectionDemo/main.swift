// RelayCollectionDemo - Demonstrates the observable relay state API

import Foundation
import NDKSwift

@MainActor
class RelayDemo {
    let ndk: NDK

    init() {
        // Initialize NDK with some relays
        ndk = NDK(relayUrls: [
            "wss://relay.damus.io",
            "wss://nos.lol",
            "wss://relay.snort.social",
        ])
    }

    func run() async {
        print("🚀 NDKSwift Observable Relay Demo")
        print("==================================\n")

        // Connect to all relays
        print("Connecting to relays...")
        await ndk.connect()

        // Print initial state immediately
        print("\nInitial state:")

        // Print current state
        printRelayStates()

        // Get quick summary
        print("\n📊 Connection Summary: \(ndk.connectedRelayCount)/\(ndk.relays.count) relays connected")

        // Add a new relay
        print("\n➕ Adding new relay: wss://relay.nostr.band")
        _ = await ndk.addRelay("wss://relay.nostr.band")

        // Wait a bit
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        // Print updated state
        printRelayStates()

        // Disconnect
        print("\n🔌 Disconnecting all relays...")
        await ndk.disconnect()

        try? await Task.sleep(nanoseconds: 500_000_000)
        printRelayStates()
    }

    func printRelayStates() {
        print("\n📡 Relay States:")
        print("---------------")

        for relay in ndk.relays {
            let status = relay.ui.isConnected ? "✅" : "❌"
            let state = switch relay.ui.connectionState {
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

            if let lastConnected = relay.ui.lastConnectedAt {
                let formatter = RelativeDateTimeFormatter()
                formatter.unitsStyle = .abbreviated
                let relative = formatter.localizedString(for: lastConnected, relativeTo: Date())
                print("   Last connected: \(relative)")
            }
        }

        print("\nConnected: \(ndk.connectedRelayCount)/\(ndk.relays.count)")
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
