@testable import NDKSwift
import XCTest

final class NDKSubscriptionThreadSafetyTests: XCTestCase {
    func testConcurrentRelayAccessDoesNotCrash() async throws {
        // This test verifies the fix for the race condition in activeRelays
        // Previously, concurrent access to the activeRelays Set would cause crashes

        let ndk = NDK()

        // Add test relays
        _ = await ndk.relayPool.addRelay(url: "wss://relay1.example.com")
        _ = await ndk.relayPool.addRelay(url: "wss://relay2.example.com")
        _ = await ndk.relayPool.addRelay(url: "wss://relay3.example.com")

        // Run multiple iterations to increase chances of hitting race condition
        for iteration in 0 ..< 50 {
            let filters = [NDKFilter(kinds: [1], authors: ["test\(iteration)"])]
            let subscription = NDKSubscription(filters: filters, ndk: ndk)

            // Create concurrent tasks
            let startTask = Task {
                // This will add relays to activeRelays via queryRelays()
                subscription.start()
            }

            let closeTask = Task {
                // Small delay to ensure start() begins first
                try await Task.sleep(nanoseconds: 1_000_000) // 1ms
                // This will iterate over activeRelays
                subscription.close()
            }

            // Wait for both tasks to complete
            await startTask.value
            await closeTask.value
        }

        // If we reach here without crashing, the test passes
        XCTAssertTrue(true, "Concurrent access completed without crashes")
    }

    func testMultipleSubscriptionsWithSharedRelays() async throws {
        // Test multiple subscriptions being created and closed concurrently
        let ndk = NDK()

        // Add shared relays
        let relayUrls = [
            "wss://relay1.example.com",
            "wss://relay2.example.com",
            "wss://relay3.example.com",
        ]

        for url in relayUrls {
            _ = await ndk.relayPool.addRelay(url: url)
        }

        // Create multiple subscriptions concurrently
        await withTaskGroup(of: Void.self) { group in
            for i in 0 ..< 10 {
                group.addTask {
                    let filters = [NDKFilter(kinds: [1], authors: ["user\(i)"])]
                    let subscription = NDKSubscription(filters: filters, ndk: ndk)

                    // Start and immediately close
                    subscription.start()

                    // Random delay
                    try? await Task.sleep(nanoseconds: UInt64.random(in: 1_000_000 ... 5_000_000))

                    subscription.close()
                }
            }
        }

        XCTAssertTrue(true, "Multiple concurrent subscriptions handled successfully")
    }

    func testRapidStartStopCycles() async throws {
        // Test rapid start/stop cycles on the same subscription
        let ndk = NDK()
        _ = await ndk.relayPool.addRelay(url: "wss://test.relay.com")

        let filters = [NDKFilter(kinds: [1])]
        let subscription = NDKSubscription(filters: filters, ndk: ndk)

        // Perform rapid start/stop cycles concurrently
        await withTaskGroup(of: Void.self) { group in
            // Start tasks
            for _ in 0 ..< 5 {
                group.addTask {
                    subscription.start()
                }
            }

            // Close tasks
            for _ in 0 ..< 5 {
                group.addTask {
                    subscription.close()
                }
            }
        }

        // Final close to ensure clean state
        subscription.close()

        XCTAssertTrue(subscription.isClosed, "Subscription should be closed")
    }
}
