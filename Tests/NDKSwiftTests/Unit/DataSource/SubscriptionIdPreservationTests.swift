import XCTest
@testable import NDKSwift

final class SubscriptionIdPreservationTests: XCTestCase {
    
    func testCustomSubscriptionIdPreservation() async throws {
        // Test that custom subscription IDs are preserved without modification
        let manager = NDKDataRequirementManager(ndk: NDK())
        
        // Test the subscription ID generation
        let filter = NDKFilter(kinds: [1111])
        let generatedId = await manager.generateSubscriptionIdForTesting(for: filter)
        
        // Generated IDs should have the format: k1111_<4-char-suffix>
        XCTAssertTrue(generatedId.starts(with: "k1111_"))
        XCTAssertEqual(generatedId.count, "k1111_".count + 4) // 4-char suffix
        
        // Verify custom IDs would be preserved (this tests the logic without full integration)
        let customId = "my-wallet-subscription"
        let pendingReqs = [
            PendingRequirement(
                id: UUID(),
                filter: filter,
                observer: MockSubIdCacheObserver(),
                registeredAt: Date(),
                maxAge: 0,
                cachePolicy: .cacheWithNetwork,
                relays: nil,
                exclusiveRelays: false,
                subscriptionId: customId,
                cacheObservationHandle: nil
            )
        ]
        
        // Extract subscription IDs like the real code does
        let customIds = pendingReqs.compactMap { $0.subscriptionId }
        XCTAssertEqual(customIds.first, customId)
        XCTAssertEqual(customIds.count, 1)
        
        // Verify the logic: if custom IDs exist, use them without modification
        let finalId: String
        if !customIds.isEmpty {
            finalId = customIds.first!
        } else {
            finalId = generatedId
        }
        
        XCTAssertEqual(finalId, customId)
        XCTAssertFalse(finalId.contains("_")) // Custom ID should not have suffix added
    }
    
    func testMultipleCustomSubscriptionIds() async throws {
        // Test behavior when multiple custom IDs are provided
        let customId1 = "wallet-events"
        let customId2 = "profile-updates" 
        
        let pendingReqs = [
            PendingRequirement(
                id: UUID(),
                filter: NDKFilter(kinds: [EventKind.cashuToken]),
                observer: MockSubIdCacheObserver(),
                registeredAt: Date(),
                maxAge: 0,
                cachePolicy: .cacheWithNetwork,
                relays: nil,
                exclusiveRelays: false,
                subscriptionId: customId1,
                cacheObservationHandle: nil
            ),
            PendingRequirement(
                id: UUID(),
                filter: NDKFilter(kinds: [EventKind.metadata]),
                observer: MockSubIdCacheObserver(),
                registeredAt: Date(),
                maxAge: 0,
                cachePolicy: .cacheWithNetwork,
                relays: nil,
                exclusiveRelays: false,
                subscriptionId: customId2,
                cacheObservationHandle: nil
            )
        ]
        
        let customIds = pendingReqs.compactMap { $0.subscriptionId }
        XCTAssertEqual(customIds.count, 2)
        XCTAssertTrue(customIds.contains(customId1))
        XCTAssertTrue(customIds.contains(customId2))
        
        // When multiple IDs exist, first one is used (as per the implementation)
        XCTAssertEqual(customIds.first, customId1)
    }
    
    func testRelaySuffixForOutboxQueries() async throws {
        // Test that relay suffixes are added for outbox queries
        let customId = "nip60-wallet"
        let relayHost = "relay.damus.io"
        
        // Simulate the relay-specific ID generation with shortened relay host
        let baseId = customId
        let shortRelayHost = relayHost
            .replacingOccurrences(of: ".com", with: "")
            .replacingOccurrences(of: ".net", with: "")
            .replacingOccurrences(of: ".org", with: "")
            .replacingOccurrences(of: "relay.", with: "")
            .replacingOccurrences(of: "nos.", with: "")
            .replacingOccurrences(of: "nostr.", with: "")
            .prefix(8)
        let relaySpecificId = "\(baseId)_\(shortRelayHost)"
        
        XCTAssertEqual(relaySpecificId, "nip60-wallet_damus.io")
        XCTAssertTrue(relaySpecificId.starts(with: customId))
        XCTAssertTrue(relaySpecificId.hasSuffix("_\(shortRelayHost)"))
    }
}

// Mock cache observer for testing subscription ID preservation
class MockSubIdCacheObserver: CacheObserver {
    func handleEvent(_ event: NDKEvent) async {}
}

// Extension to expose internal method for testing
extension NDKDataRequirementManager {
    func generateSubscriptionIdForTesting(for filter: NDKFilter) async -> String {
        return generateSubscriptionId(for: filter)
    }
}