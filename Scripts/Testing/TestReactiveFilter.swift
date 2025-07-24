#!/usr/bin/env swift

import Foundation
import NDKSwift

// Simple test script to debug reactive filter issue

@main
struct TestReactiveFilter {
    static func main() async {
        // Enable debug logging
        NDKLogger.shared.minimumSeverity = .trace
        
        print("🔍 Testing Reactive Filter Subscriptions")
        print(String(repeating: "=", count: 50))
        
        // Initialize NDK
        let ndk = NDK(
            relayUrls: [
                "wss://relay.primal.net",
                "wss://relay.damus.io"
            ]
        )
        
        // Create a test signer with a known key that has follows
        let signer: NDKSigner
        if let privateKey = ProcessInfo.processInfo.environment["NOSTR_PRIVATE_KEY"] {
            signer = try! NDKPrivateKeySigner(privateKey: privateKey)
            print("✅ Using provided private key")
        } else {
            // Use a test account with known follows
            signer = try! NDKPrivateKeySigner(privateKey: "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef")
            print("🔑 Using test private key")
        }
        
        // Connect to relays
        await ndk.connect()
        print("✅ Connected to relays")
        
        // Wait a moment for connection
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        do {
            // Start session with follow list and mute list
            print("\n📋 Starting session...")
            let sessionData = try await ndk.startSession(
                signer: signer,
                config: NDKSessionConfiguration(
                    dataRequirements: [.followList, .muteList],
                    preloadStrategy: .blocking
                )
            )
            
            print("✅ Session started")
            print("  - Follows: \(sessionData.followList.count)")
            print("  - Mutes: \(sessionData.muteList.count)")
            
            // Create reactive filter
            print("\n📡 Creating reactive filter...")
            let reactiveFilter = ReactiveFilter(
                dependencies: [.followList],
                builder: { sessionData in
                    print("🔨 Building filter with \(sessionData.followList.count) follows")
                    let authors = sessionData.followList.isEmpty ? 
                        ["82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2"] : // jack
                        Array(sessionData.followList.prefix(10))
                    return NDKFilter(
                        authors: authors,
                        kinds: [EventKind.textNote],
                        limit: 5
                    )
                }
            )
            
            print("\n🚀 Starting observation...")
            var eventCount = 0
            
            // Timeout task
            let timeoutTask = Task {
                try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                print("\n⏱️ Timeout reached - no events received")
                exit(0)
            }
            
            // Observe events
            for await event in ndk.observe(reactiveFilter) {
                eventCount += 1
                print("\n📨 Event #\(eventCount) received!")
                print("  - Author: \(event.pubkey.prefix(8))...")
                print("  - Content: \(event.content.prefix(50))...")
                
                if eventCount >= 3 {
                    timeoutTask.cancel()
                    break
                }
            }
            
            print("\n✅ Received \(eventCount) events")
            
        } catch {
            print("❌ Error: \(error)")
        }
        
        print("\n✨ Test completed!")
    }
}