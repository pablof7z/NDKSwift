#!/usr/bin/env swift

import Foundation
import NDKSwift

// Test core iOS app functionality
print("🧪 Testing iOS App Core Functionality")
print(String(repeating: "=", count: 40))

// Test 1: Account creation
print("\n1️⃣ Testing account creation...")
do {
    let signer = try NDKPrivateKeySigner.generate()
    let npub = try signer.npub
    print("✅ Account created: \(npub)")
} catch {
    print("❌ Account creation failed: \(error)")
}

// Test 2: NDK initialization and relay connection
print("\n2️⃣ Testing NDK and relay connection...")
let ndk = NDK()
_ = ndk.addRelay("wss://relay.primal.net")

Task {
    await ndk.connect()
    print("✅ Connected to relay")
    
    // Test 3: Subscription
    print("\n3️⃣ Testing subscription...")
    let filter = NDKFilter(kinds: [1])
    let subscription = ndk.subscribe(filters: [filter])
    
    // Start subscription and collect a few events
    await subscription.start()
    
    var eventCount = 0
    let maxEvents = 5
    
    do {
        for try await event in subscription {
            eventCount += 1
            print("📨 Received event \(eventCount): \(event.id ?? "no-id")")
            
            if eventCount >= maxEvents {
                break
            }
        }
    } catch {
        print("❌ Subscription error: \(error)")
    }
    
    await subscription.close()
    print("✅ Subscription test completed, received \(eventCount) events")
    
    // Test 4: Publishing
    print("\n4️⃣ Testing event publishing...")
    let testSigner = try? NDKPrivateKeySigner.generate()
    ndk.signer = testSigner
    
    let event = NDKEvent(content: "iOS app test event - \(Date())")
    event.ndk = ndk
    
    do {
        try await event.sign()
        let publishedRelays = try await ndk.publish(event)
        print("✅ Event published to \(publishedRelays.count) relay(s)")
        print("📝 Event ID: \(event.id ?? "unknown")")
    } catch {
        print("❌ Publishing failed: \(error)")
    }
    
    // Disconnect
    await ndk.disconnect()
    print("\n✨ All tests completed!")
    
    exit(0)
}

// Keep script running
RunLoop.main.run()