import Foundation
import NDKSwift

struct Example01_ConnectToRelay {
    static func run() async throws {
        print("🚀 NDKSwift Example: Connect to Relay")
        print("=====================================\n")
        
        // Step 1: Create an NDK instance with relay URLs
        let relayUrls = [
            RelayConstants.damus,
            RelayConstants.primal,
            RelayConstants.nosLol
        ]
        
        let ndk = NDK(relayUrls: relayUrls)
        print("✅ Created NDK instance with \(relayUrls.count) relays")
        
        // Step 2: Connect to the relays
        print("\n📡 Connecting to relays...")
        await ndk.connect()
        
        // Step 3: Check connection status
        let (connected, total) = await ndk.getRelayConnectionSummary()
        print("\n📊 Connection Status: \(connected)/\(total) relays connected")
        
        // Step 4: Wait a moment to see the connections
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        // Step 5: Disconnect when done
        print("\n👋 Disconnecting from relays...")
        await ndk.disconnect()
        print("✅ Disconnected successfully")
        
        print("\n📚 Key Concepts:")
        print("- NDK manages relay connections automatically")
        print("- You can connect to multiple relays simultaneously")
        print("- Connection status can be monitored")
        print("- Always disconnect when done to clean up resources")
    }
}