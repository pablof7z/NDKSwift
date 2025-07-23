#!/usr/bin/env swift

import Foundation
import NDKSwift

/// Demo of reactive filters that automatically update when follows change
@main
struct ReactiveFilterDemo {
    static func main() async {
        print("🚀 NDKSwift Reactive Filter Demo")
        print("================================\n")
        
        // Create NDK instance
        let ndk = NDK(relays: ["wss://relay.damus.io", "wss://relay.primal.net"])
        
        // Create test signer
        let privateKey = "d7f2e96bb7187bca152a5b60b12a0b0e4fbb3b18b0ba9b256552bcea02adae18"
        let signer = try! NDKPrivateKeySigner(privateKey: privateKey)
        
        print("📝 Starting session with follow list requirement...")
        
        // Start session with follow list requirement
        let sessionData = try! await ndk.startSession(
            signer: signer,
            config: NDKSessionConfiguration(
                dataRequirements: [.followList],
                preloadStrategy: .progressive
            )
        )
        
        print("✅ Session started for pubkey: \(sessionData.pubkey)")
        
        // Wait a moment for initial follow list to load
        try! await Task.sleep(nanoseconds: 2_000_000_000)
        
        // Create reactive filter for text notes from follows
        let notesFilter = ReactiveFilter(
            dependencies: [.followList],
            builder: { sessionData in
                NDKFilter(
                    kinds: [.textNote],
                    authors: Array(sessionData.followList),
                    limit: 20
                )
            }
        )
        
        print("\n📊 Current follow list state:")
        switch sessionData.followListState {
        case .loading:
            print("   ⏳ Loading...")
        case .ready(let follows, let fromCache):
            print("   ✅ Ready with \(follows.count) follows (from cache: \(fromCache))")
        case .updating(let current, let changes):
            print("   🔄 Updating from \(current.count) to \(changes.count) follows")
        case .error(let error):
            print("   ❌ Error: \(error)")
        }
        
        print("\n🔍 Starting reactive subscription for text notes...")
        print("   This will automatically update when follows change!\n")
        
        // Start observing with reactive filter
        Task {
            var noteCount = 0
            for await event in ndk.observe(notesFilter) {
                noteCount += 1
                let preview = String(event.content.prefix(50))
                    .replacingOccurrences(of: "\n", with: " ")
                print("📝 Note #\(noteCount) from \(event.pubkey.prefix(8))...: \(preview)...")
                
                if noteCount >= 10 {
                    print("\n✅ Received 10 notes. Demo complete!")
                    break
                }
            }
        }
        
        // Simulate follow list change after 5 seconds
        Task {
            try! await Task.sleep(nanoseconds: 5_000_000_000)
            
            print("\n🔄 Simulating follow list update...")
            print("   In a real app, this would happen when user follows someone new")
            print("   The subscription will automatically update!\n")
            
            // In a real app, the follow list would update from a new contact list event
            // The reactive filter would automatically swap subscriptions
        }
        
        // Keep running for 10 seconds
        try! await Task.sleep(nanoseconds: 10_000_000_000)
        
        print("\n👋 Demo finished!")
    }
}