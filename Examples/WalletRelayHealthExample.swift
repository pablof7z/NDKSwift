#!/usr/bin/env swift

import Foundation
import NDKSwift

// Example: Monitor wallet relay health
@main
struct WalletRelayHealthExample {
    static func main() async throws {
        // Create NDK instance with signer
        let privateKey = "your_test_private_key_here"
        let signer = NDKPrivateKeySigner(privateKey: privateKey)
        
        let ndk = NDK(
            relayUrls: [
                "wss://relay.damus.io",
                "wss://relay.nostr.band",
                "wss://nos.lol"
            ],
            signer: signer
        )
        
        try await ndk.connect()
        
        // Create NIP60 wallet
        let wallet = try NIP60Wallet(ndk: ndk)
        
        // Wait for wallet configuration to load
        print("⏳ Waiting for wallet configuration...")
        try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
        
        // Check relay health
        print("\n🔍 Checking wallet relay health...")
        
        let healthStatus = try await wallet.checkWalletHealth()
        
        print("\n📊 Wallet Health Status:")
        print("   Overall Health: \(healthStatus.isHealthy ? "✅ Healthy" : "⚠️ Issues Detected")")
        print("   Last Check: \(healthStatus.lastCheckTime)")
        print("   Total Events: \(healthStatus.totalEvents)")
        print("   Synced Relays: \(healthStatus.syncedRelays)")
        print("   Out of Sync Relays: \(healthStatus.outOfSyncRelays)")
        
        print("\n📡 Relay Details:")
        for relayHealth in healthStatus.relayHealth {
            print("\n   Relay: \(relayHealth.relay.url)")
            print("   Status: \(relayHealth.isHealthy ? "✅ Healthy" : "⚠️ Out of Sync")")
            print("   Known Events: \(relayHealth.knownEvents)")
            print("   Missing Events: \(relayHealth.missingEvents.count)")
            
            if !relayHealth.missingEvents.isEmpty {
                print("   Missing Event IDs:")
                for eventId in relayHealth.missingEvents.prefix(5) {
                    print("     - \(eventId)")
                }
                if relayHealth.missingEvents.count > 5 {
                    print("     ... and \(relayHealth.missingEvents.count - 5) more")
                }
            }
        }
        
        // If any relays are out of sync, offer to repair
        let unhealthyRelays = healthStatus.relayHealth.filter { !$0.isHealthy }
        if !unhealthyRelays.isEmpty {
            print("\n🔧 Found \(unhealthyRelays.count) relay(s) needing repair")
            
            for relayHealth in unhealthyRelays {
                print("\n   Repairing relay: \(relayHealth.relay.url)")
                try await wallet.repairRelay(
                    relayHealth.relay,
                    missingEventIds: relayHealth.missingEvents
                )
            }
            
            print("\n✅ Repair complete!")
        }
        
        // Disconnect
        await ndk.disconnect()
    }
}