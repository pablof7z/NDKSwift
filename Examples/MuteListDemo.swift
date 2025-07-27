#!/usr/bin/env swift

import Foundation
import NDKSwift

// MARK: - Mute List and Blocked Relays Demo

/// This example demonstrates:
/// - Loading mute lists and blocked relays as part of session data
/// - Automatic filtering of muted pubkeys from event streams
/// - Checking if specific pubkeys or relays are blocked
/// - How blocked relays are excluded from outbox operations

@main
struct MuteListDemo {
    static func main() async {
        print("🔇 NDKSwift Mute List & Blocked Relays Demo")
        print("=" * 50)
        
        // Initialize NDK
        let ndk = NDK(
            relayUrls: [
                RelayConstants.damus,
                RelayConstants.primal,
                RelayConstants.nosLol
            ]
        )
        
        // Create or restore a signer
        let signer: NDKSigner
        if let privateKey = ProcessInfo.processInfo.environment["NOSTR_PRIVATE_KEY"] {
            signer = try! NDKPrivateKeySigner(privateKey: privateKey)
            print("✅ Using provided private key")
        } else {
            signer = NDKPrivateKeySigner.generate()
            print("🔑 Generated new keypair: \(signer.publicKey)")
        }
        
        // Connect to relays
        await ndk.connect()
        print("🌐 Connected to \(await ndk.pool.connectedRelays().count) relays")
        
        do {
            // Start session with mute list and blocked relays
            print("\n📋 Loading Session Data...")
            let sessionData = try await ndk.startSession(
                signer: signer,
                config: NDKSessionConfiguration(
                    dataRequirements: [.followList, .muteList, .blockedRelays],
                    preloadStrategy: .blocking // Wait for all data
                )
            )
            
            // Display loaded data
            print("\n✅ Session Data Loaded:")
            print("  - Following: \(sessionData.followList.count) users")
            print("  - Muted: \(sessionData.muteList.count) users")
            print("  - Blocked: \(sessionData.blockedRelays.count) relays")
            
            // Show some muted pubkeys (first 3)
            if !sessionData.muteList.isEmpty {
                print("\n🔇 Sample Muted Pubkeys:")
                for pubkey in sessionData.muteList.prefix(3) {
                    print("  - \(pubkey.prefix(16))...")
                }
            }
            
            // Show blocked relays
            if !sessionData.blockedRelays.isEmpty {
                print("\n🚫 Blocked Relays:")
                for relay in sessionData.blockedRelays {
                    print("  - \(relay)")
                }
            }
            
            // Demonstrate O(1) lookup
            print("\n🔍 Checking Specific Items:")
            let testPubkey = "82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2" // jack
            print("  - Is \(testPubkey.prefix(8))... muted? \(sessionData.isMuted(testPubkey))")
            
            let testRelay = "wss://bad-relay.com"
            print("  - Is \(testRelay) blocked? \(sessionData.isRelayBlocked(testRelay))")
            
            // Create a reactive filter that automatically filters muted users
            print("\n📡 Creating Reactive Feed Filter...")
            let feedFilter = ReactiveFilter(
                dependencies: [.followList],
                builder: { sessionData in
                    NDKFilter(
                        authors: Array(sessionData.followList),
                        kinds: [EventKind.textNote],
                        limit: 10
                    )
                }
            )
            
            print("🎯 Fetching recent notes from follows (muted users automatically filtered)...")
            
            var receivedCount = 0
            var filteredCount = 0
            
            // Track filtered events for demonstration
            let startTime = Date()
            
            for await event in ndk.observe(feedFilter) {
                receivedCount += 1
                
                // This event is guaranteed not to be from a muted pubkey
                print("\n📝 Note from @\(event.pubkey.prefix(8))...")
                print("   \"\(event.content.prefix(100))...\"")
                
                // Stop after a few events
                if receivedCount >= 5 {
                    break
                }
                
                // Timeout after 10 seconds
                if Date().timeIntervalSince(startTime) > 10 {
                    print("\n⏱️ Timeout reached")
                    break
                }
            }
            
            print("\n📊 Summary:")
            print("  - Received \(receivedCount) events")
            print("  - All from non-muted users ✅")
            
            // Demonstrate relay selection with blocked relays
            print("\n🌐 Relay Selection (blocked relays excluded):")
            print("  - Your relay list would exclude any blocked relays")
            print("  - Outbox operations automatically skip blocked relays")
            
            // Example: Add a user to mute list
            print("\n➕ Example: Adding a User to Mute List")
            if let muteList = try? await createOrUpdateMuteList(
                ndk: ndk,
                signer: signer,
                addPubkey: "newpubkeytomute123"
            ) {
                print("✅ Mute list updated successfully")
            }
            
        } catch {
            print("❌ Error: \(error)")
        }
        
        print("\n✨ Demo completed!")
    }
    
    /// Helper to create or update a mute list
    static func createOrUpdateMuteList(
        ndk: NDK,
        signer: NDKSigner,
        addPubkey: String
    ) async throws -> NDKList {
        // Fetch existing mute list
        let filter = NDKFilter(
            authors: [signer.publicKey],
            kinds: [EventKind.muteList],
            limit: 1
        )
        
        let dataSource = NDKDataSource<NDKEvent>(
            ndk: ndk,
            filter: filter,
            maxAge: 0
        )
        
        let muteList: NDKList
        if let existingEvent = await dataSource.first() {
            muteList = NDKList.from(existingEvent, ndk: ndk)
            print("  - Found existing mute list with \(muteList.userPubkeys.count) entries")
        } else {
            muteList = NDKList(ndk: ndk, kind: EventKind.muteList)
            muteList.title = "Mute List"
            print("  - Creating new mute list")
        }
        
        // Add the new pubkey
        let user = NDKUser(pubkey: addPubkey)
        try await muteList.addItem(user)
        
        // Publish the updated list
        try await muteList.publish()
        print("  - Published updated mute list")
        
        return muteList
    }
}

// Helper extension
extension String {
    static func *(lhs: String, rhs: Int) -> String {
        String(repeating: lhs, count: rhs)
    }
}