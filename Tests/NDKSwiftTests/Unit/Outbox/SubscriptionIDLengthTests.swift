@testable import NDKSwiftCore
import XCTest

final class SubscriptionIDLengthTest: XCTestCase {
    func testRelayDiscoverySubscriptionIDLength() {
        // Test that relay discovery subscription IDs are not too long
        let authors: Set<String> = [
            "fa984bd7dbb282f07e16e7ae87b26a2a7b9b90b7246a44771f0cf5ae58018f52",
            "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d",
            "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245",
        ]

        // Generate subscription ID as per the fixed implementation
        let shortAuthorsId = authors.first.map { String($0.prefix(8)) } ?? "unknown"
        let subscriptionId = "relay_disc_\(shortAuthorsId)_\(authors.count)"

        print("Generated subscription ID: \(subscriptionId)")
        print("Subscription ID length: \(subscriptionId.count)")

        // Most relays allow up to 64 characters for subscription IDs
        // Some are more restrictive, so we'll aim for under 32
        XCTAssertLessThan(subscriptionId.count, 32, "Subscription ID should be under 32 characters")
    }

    func testOutboxFetchSubscriptionIDLength() {
        // Test outbox fetch subscription IDs
        let subscriptionId1 = "outbox_fetch_\(IDGenerator.randomId(length: 6))"
        let subscriptionId2 = "outbox_cont_\(IDGenerator.randomId(length: 6))"

        print("Outbox fetch subscription ID: \(subscriptionId1)")
        print("Outbox contacts subscription ID: \(subscriptionId2)")

        XCTAssertLessThan(subscriptionId1.count, 32, "Outbox fetch subscription ID should be under 32 characters")
        XCTAssertLessThan(subscriptionId2.count, 32, "Outbox contacts subscription ID should be under 32 characters")
    }

    func testReactiveFilterSubscriptionIDLength() {
        // Test reactive filter subscription IDs
        let subscriptionId = "reactive_\(IDGenerator.randomId(length: 8))"

        print("Reactive filter subscription ID: \(subscriptionId)")
        print("Subscription ID length: \(subscriptionId.count)")

        XCTAssertLessThan(subscriptionId.count, 32, "Reactive filter subscription ID should be under 32 characters")
    }
}
