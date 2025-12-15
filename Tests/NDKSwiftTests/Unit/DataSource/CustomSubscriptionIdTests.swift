@testable import NDKSwiftCore
import XCTest

final class CustomSubscriptionIdTests: XCTestCase {
    var ndk: NDK!
    var mockRelay: MockRelayWithCapture!

    override func setUp() async throws {
        try await super.setUp()

        // Create signer with test key
        let privateKey = "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"
        let signer = try NDKPrivateKeySigner(privateKey: privateKey)

        // Create NDK instance - will test with direct observation of messages
        ndk = NDK(signer: signer)

        // Create mock relay for capturing messages
        mockRelay = MockRelayWithCapture(url: "wss://test.relay")
    }

    override func tearDown() async throws {
        ndk = nil
        mockRelay = nil
        try await super.tearDown()
    }

    func testCustomSubscriptionIdIsPreserved() async throws {
        // Create a data source with a custom subscription ID
        let customId = "my-custom-subscription-id"
        let filter = NDKFilter(kinds: [1111])

        let dataSource = NDKSubscription<NDKEvent>(
            ndk: ndk,
            filter: filter,
            subscriptionId: customId
        )

        // Wait a bit for the subscription to be created
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Check the captured messages
        let reqMessages = mockRelay.capturedMessages.filter { $0.contains("\"REQ\"") }
        XCTAssertFalse(reqMessages.isEmpty, "Should have sent at least one REQ message")

        // Parse the first REQ message to check the subscription ID
        if let firstReq = reqMessages.first,
           let data = firstReq.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [Any],
           json.count > 1,
           let subscriptionId = json[1] as? String
        {
            XCTAssertEqual(subscriptionId, customId, "Subscription ID should be preserved exactly as provided")
            XCTAssertFalse(subscriptionId.contains("_"), "Custom subscription ID should not have any suffixes added")
        } else {
            XCTFail("Could not parse REQ message")
        }

        // Clean up
        _ = dataSource // Keep reference alive
    }

    func testMultipleCustomSubscriptionIds() async throws {
        // Create multiple data sources with different custom IDs
        let customId1 = "wallet-events"
        let customId2 = "profile-updates"

        let dataSource1 = NDKSubscription<NDKEvent>(
            ndk: ndk,
            filter: NDKFilter(kinds: [EventKind.cashuToken]),
            subscriptionId: customId1
        )

        let dataSource2 = NDKSubscription<NDKEvent>(
            ndk: ndk,
            filter: NDKFilter(kinds: [EventKind.metadata]),
            subscriptionId: customId2
        )

        // Wait for subscriptions
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms

        // Check captured messages
        let reqMessages = mockRelay.capturedMessages.filter { $0.contains("\"REQ\"") }
        XCTAssertGreaterThanOrEqual(reqMessages.count, 2, "Should have sent at least 2 REQ messages")

        // Extract all subscription IDs
        var foundIds: Set<String> = []
        for req in reqMessages {
            if let data = req.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [Any],
               json.count > 1,
               let subscriptionId = json[1] as? String
            {
                foundIds.insert(subscriptionId)
            }
        }

        XCTAssertTrue(foundIds.contains(customId1), "Should find first custom ID")
        XCTAssertTrue(foundIds.contains(customId2), "Should find second custom ID")

        // Clean up
        _ = dataSource1
        _ = dataSource2
    }

    func testNIP60WalletSubscriptionId() async throws {
        // Test NIP-60 wallet specific subscription IDs
        let walletId = "nip60-wallet-events"

        let dataSource = NDKSubscription<NDKEvent>(
            ndk: ndk,
            filter: NDKFilter(kinds: [EventKind.cashuToken, EventKind.nutzap]),
            subscriptionId: walletId
        )

        // Wait for subscription
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Check captured messages
        let reqMessages = mockRelay.capturedMessages.filter { $0.contains("\"REQ\"") }

        if let firstReq = reqMessages.first,
           let data = firstReq.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [Any],
           json.count > 1,
           let subscriptionId = json[1] as? String
        {
            XCTAssertEqual(subscriptionId, walletId, "NIP-60 wallet subscription ID should be preserved")
        }

        // Clean up
        _ = dataSource
    }
}

// Mock relay that captures sent messages
class MockRelayWithCapture: MockRelayProtocol, @unchecked Sendable {
    var capturedMessages: [String] = []

    override func send(_ message: String) async throws {
        capturedMessages.append(message)
        try await super.send(message)
    }
}
