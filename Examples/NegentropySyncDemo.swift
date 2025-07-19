#!/usr/bin/env swift

import Foundation
import NDKSwift

// E2E test script for NIP-77 Negentropy Sync implementation
// This demonstrates syncing events between a local cache and a relay

@main
struct NegentropySyncDemo {
    static func main() async {
        print("🔄 NIP-77 Negentropy Sync Demo")
        print("==============================\n")
        
        do {
            // Setup NDK with SQLite cache
            let ndk = NDK()
            let cache = try await NDKSQLiteCache(path: "/tmp/negentropy_demo.db", debugMode: true)
            await ndk.setCacheAdapter(cache)
            
            // Create test signer
            let privateKey = try NDKPrivateKeySigner.generatePrivateKey()
            let signer = NDKPrivateKeySigner(privateKey: privateKey)
            ndk.signer = signer
            
            print("📝 Creating test events...")
            
            // Create some local events (simulating events we already have)
            let localEvents = try await createLocalEvents(ndk: ndk, count: 50)
            print("✅ Created \(localEvents.count) local events")
            
            // Save them to cache
            for event in localEvents {
                try await cache.saveEvent(event)
            }
            print("💾 Saved events to local cache")
            
            // Connect to a relay that supports NIP-77
            let relayURL = "wss://relay.damus.io" // Replace with NIP-77 supporting relay
            print("\n🌐 Connecting to relay: \(relayURL)")
            try await ndk.connect(relayURLs: [relayURL])
            
            // Create a filter for sync (e.g., all text notes from the last hour)
            let oneHourAgo = Timestamp(Date().timeIntervalSince1970 - 3600)
            let filter = NDKFilter(
                kinds: [1], // Text notes
                since: oneHourAgo
            )
            
            print("\n🔄 Starting Negentropy sync...")
            print("Filter: kind=1, since=\(oneHourAgo)")
            
            // Perform the sync
            let syncResult = try await ndk.syncEvents(
                filter: filter,
                relay: relayURL
            )
            
            // Display results
            print("\n📊 Sync Results:")
            print("================")
            print("✅ Events we had locally: \(syncResult.localEventCount)")
            print("📥 New events from relay: \(syncResult.downloadedEvents.count)")
            print("📤 Events sent to relay: \(syncResult.uploadedEvents.count)")
            print("💬 Messages exchanged: \(syncResult.messageRounds)")
            print("📏 Bytes transferred: \(formatBytes(syncResult.bytesTransferred))")
            
            if syncResult.downloadedEvents.count > 0 {
                print("\n📥 Sample of new events:")
                for event in syncResult.downloadedEvents.prefix(5) {
                    print("  - \(event.id.prefix(8))... by \(event.pubkey.prefix(8))...")
                }
            }
            
            // Verify cache has new events
            let cachedEvents = try await cache.queryEvents(filter)
            print("\n✅ Total events in cache after sync: \(cachedEvents.count)")
            
            // Test sync with multiple relays
            print("\n🌐 Testing multi-relay sync...")
            let multiRelayResults = try await ndk.syncWithAllRelays(filter: filter)
            
            // Also demonstrate receive-only sync (for wallet apps)
            // .receive = download only (wallet apps, privacy-sensitive)
            // .send = upload only (backup, broadcasting)
            // .both = bidirectional sync (default, full sync)
            print("\n📥 Testing receive-only sync...")
            let receiveOnlyResults = try await ndk.syncWithAllRelays(filter: filter, direction: .receive)
            
            for (relay, result) in multiRelayResults {
                print("\nRelay: \(relay)")
                print("  - Downloaded: \(result.downloadedEvents.count)")
                print("  - Uploaded: \(result.uploadedEvents.count)")
                print("  - Efficiency: \(result.efficiencyRatio)%")
            }
            
            print("\n✅ NIP-77 Negentropy Sync Demo Complete!")
            
        } catch {
            print("❌ Error: \(error)")
        }
    }
    
    static func createLocalEvents(ndk: NDK, count: Int) async throws -> [NDKEvent] {
        var events: [NDKEvent] = []
        
        for i in 0..<count {
            let content = "Test event #\(i) - \(Date())"
            let event = try NDKEvent(
                ndk: ndk,
                kind: 1,
                content: content,
                tags: []
            )
            events.append(event)
        }
        
        return events
    }
    
    
    static func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: Int64(bytes))
    }
}



// Import the NIP-77 implementation
// The sync methods are now implemented in NDKSyncExtension.swift