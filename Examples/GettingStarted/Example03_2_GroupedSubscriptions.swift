import Foundation
import NDKSwift

/// Example 03.2: Grouped Subscriptions
/// This example validates that subscriptions that can be grouped together
/// don't get mixed results. It creates two observers for kind:0 (metadata)
/// events from different pubkeys and ensures each observer only receives
/// the results it was expecting.

enum Example03_2_GroupedSubscriptions {
    static func run() async throws {
        // Disable verbose logging for cleaner output
        NDKLogger.setLogLevel(.error)

        print("=== Example 03.2: Grouped Subscriptions ===")
        print("Testing that grouped subscriptions don't mix results...")

        // Create NDK instance with multiple relays for better coverage
        let ndk = NDK(relayUrls: [
            "wss://relay.primal.net",
            "wss://relay.damus.io",
            "wss://nos.lol",
        ])

        // Connect to relays
        await ndk.connect()
        print("✓ Connected to relays")

        // Wait for connection to stabilize
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

        // Define two different pubkeys to observe
        let jackPubkey = "82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2" // Jack Dorsey
        let fiatjafPubkey = "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d" // fiatjaf

        print("\n📝 Creating two observers for metadata (kind:0) events:")
        print("   Observer 1: Jack Dorsey (\(String(jackPubkey.prefix(8)))...)")
        print("   Observer 2: fiatjaf (\(String(fiatjafPubkey.prefix(8)))...)")

        // Create filters for each observer
        let filter1 = NDKFilter(authors: [jackPubkey], kinds: [0])
        let filter2 = NDKFilter(authors: [fiatjafPubkey], kinds: [0])

        // Create observers
        let observer1 = ndk.subscribe(filter: filter1, cachePolicy: .networkOnly)
        let observer2 = ndk.subscribe(filter: filter2, cachePolicy: .networkOnly)

        // Track events received by each observer
        // Note: In a production test, consider using an actor for thread-safe access
        // to these arrays when collecting from concurrent tasks
        var observer1Events: [NDKEvent] = []
        var observer2Events: [NDKEvent] = []

        // Create collection tasks
        let task1 = Task {
            for await event in observer1.events {
                observer1Events.append(event)
                print("\n🔵 Observer 1 received event:")
                print("   Author: \(String(event.pubkey.prefix(8)))...")
                print("   Kind: \(event.kind)")
                print("   Content length: \(event.content.count) bytes")

                // Collect up to 1 event
                if observer1Events.count >= 1 {
                    break
                }
            }
        }

        let task2 = Task {
            for await event in observer2.events {
                observer2Events.append(event)
                print("\n🟢 Observer 2 received event:")
                print("   Author: \(String(event.pubkey.prefix(8)))...")
                print("   Kind: \(event.kind)")
                print("   Content length: \(event.content.count) bytes")

                // Collect up to 1 event
                if observer2Events.count >= 1 {
                    break
                }
            }
        }

        // Wait for events or timeout
        print("\nWaiting for events (5 seconds max)...")

        // Create a timeout task
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
        }

        // Wait for either completion or timeout
        await withTaskGroup(of: Void.self) { group in
            group.addTask { _ = await task1.result }
            group.addTask { _ = await task2.result }
            group.addTask { _ = try? await timeoutTask.value }

            // Cancel remaining tasks after first completion
            await group.next()
            group.cancelAll()
        }

        // Cancel any remaining tasks
        task1.cancel()
        task2.cancel()
        timeoutTask.cancel()

        // Validate results
        print("\n=== Validation Results ===")

        var allTestsPassed = true

        // Check Observer 1
        print("\n🔵 Observer 1 (Jack Dorsey):")
        print("   Events received: \(observer1Events.count)")

        if observer1Events.count > 0 {
            let correctEvents = observer1Events.filter { $0.pubkey == jackPubkey }
            let wrongEvents = observer1Events.filter { $0.pubkey != jackPubkey }

            print("   ✓ Correct author: \(correctEvents.count)")
            print("   ✗ Wrong author: \(wrongEvents.count)")

            if wrongEvents.count > 0 {
                print("   ❌ ERROR: Observer 1 received events from wrong author!")
                for event in wrongEvents {
                    print("      - Got event from: \(event.pubkey)")
                }
                allTestsPassed = false
            } else if correctEvents.count > 0 {
                print("   ✅ All events from correct author!")
            }
        } else {
            print("   ⚠️  No events received (relay might not have Jack's metadata)")
        }

        // Check Observer 2
        print("\n🟢 Observer 2 (fiatjaf):")
        print("   Events received: \(observer2Events.count)")

        if observer2Events.count > 0 {
            let correctEvents = observer2Events.filter { $0.pubkey == fiatjafPubkey }
            let wrongEvents = observer2Events.filter { $0.pubkey != fiatjafPubkey }

            print("   ✓ Correct author: \(correctEvents.count)")
            print("   ✗ Wrong author: \(wrongEvents.count)")

            if wrongEvents.count > 0 {
                print("   ❌ ERROR: Observer 2 received events from wrong author!")
                for event in wrongEvents {
                    print("      - Got event from: \(event.pubkey)")
                }
                allTestsPassed = false
            } else if correctEvents.count > 0 {
                print("   ✅ All events from correct author!")
            }
        } else {
            print("   ⚠️  No events received (relay might not have fiatjaf's metadata)")
        }

        // Overall result
        print("\n=== Test Summary ===")
        if allTestsPassed {
            if observer1Events.count > 0 || observer2Events.count > 0 {
                print("✅ Test PASSED: Each observer only received events from their specified author")
            } else {
                print("⚠️  Test INCONCLUSIVE: No events received from either author")
                print("   (This might be normal if the relays don't have these metadata events)")
            }
        } else {
            print("❌ Test FAILED: Observers received mixed results!")
        }

        print("\n📊 Statistics:")
        print("   Total events for Observer 1: \(observer1Events.count)")
        print("   Total events for Observer 2: \(observer2Events.count)")
        print("   Cross-contamination detected: \(!allTestsPassed)")

        // Disconnect
        await ndk.disconnect()
        print("\n✓ Example completed")
    }
}
