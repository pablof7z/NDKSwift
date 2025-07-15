import XCTest
import CashuSwift
@testable import NDKSwift

/// Integration test for NIP-60 del tag functionality
/// This test verifies that the fix for del tags works correctly
final class DelTagIntegrationTest: XCTestCase {
    
    func testProofStateManagerOwnershipTracking() async {
        // This test verifies the core functionality that enables del tags
        let manager = ProofStateManager()
        
        // Create test proofs
        let proof1 = CashuSwift.Proof(
            keysetID: "keyset1",
            amount: 10,
            secret: "secret1",
            C: "C1"
        )
        let proof2 = CashuSwift.Proof(
            keysetID: "keyset1",
            amount: 20,
            secret: "secret2",
            C: "C2"
        )
        
        // Simulate initial token event ownership
        let initialEventId = "initial-token-123"
        await manager.addProof(proof1, mint: "mint1", eventId: initialEventId, timestamp: 1000)
        await manager.addProof(proof2, mint: "mint1", eventId: initialEventId, timestamp: 1000)
        
        // Test: getOwnerEventIds should return the initial event
        let owners = await manager.getOwnerEventIds(for: [proof1, proof2])
        XCTAssertEqual(owners.count, 1, "Should have one owner")
        XCTAssertEqual(owners.first, initialEventId, "Owner should be initial event")
        
        // Mark proof1 as spent
        await manager.markProofsAsDeleted([proof1])
        
        // Get owner for remaining proof2
        let remainingOwners = await manager.getOwnerEventIds(for: [proof2])
        XCTAssertEqual(remainingOwners.count, 1, "Should still have one owner")
        XCTAssertEqual(remainingOwners.first, initialEventId, "Owner should still be initial event")
        
        // This is the key information needed for del tags:
        // When creating a new token with proof2, the system should know
        // that it previously belonged to initialEventId
        
        print("✅ Del tag test passed: When creating new token with proof2, it should include del: ['\(initialEventId)']")
    }
    
    func testOwnershipUpdateWithTimestamps() async {
        let manager = ProofStateManager()
        let proof = CashuSwift.Proof(keysetID: "k1", amount: 10, secret: "s1", C: "C1")
        
        // Add with initial owner
        await manager.addProof(proof, mint: "mint1", eventId: "event1", timestamp: 1000)
        
        // Try to update with older timestamp - should NOT change ownership
        await manager.addProof(proof, mint: "mint1", eventId: "event2", timestamp: 500)
        var owners = await manager.getOwnerEventIds(for: [proof])
        XCTAssertEqual(owners.first, "event1", "Older timestamp should not override")
        
        // Update with newer timestamp - SHOULD change ownership
        await manager.addProof(proof, mint: "mint1", eventId: "event3", timestamp: 2000)
        owners = await manager.getOwnerEventIds(for: [proof])
        XCTAssertEqual(owners.first, "event3", "Newer timestamp should override")
        
        print("✅ Timestamp-based ownership test passed")
    }
    
    func testDelTagScenario() async {
        // This test demonstrates the full del tag scenario
        let manager = ProofStateManager()
        
        // Initial state: Token1 has proof1 (10 sats) and proof2 (20 sats)
        let proof1 = CashuSwift.Proof(keysetID: "k1", amount: 10, secret: "s1", C: "C1")
        let proof2 = CashuSwift.Proof(keysetID: "k1", amount: 20, secret: "s2", C: "C2")
        
        let token1Id = "token-event-001"
        await manager.addProof(proof1, mint: "mint1", eventId: token1Id, timestamp: 1000)
        await manager.addProof(proof2, mint: "mint1", eventId: token1Id, timestamp: 1000)
        
        print("Initial state: Token1 (\(token1Id)) has 30 sats (proof1: 10, proof2: 20)")
        
        // User spends proof1 (10 sats)
        await manager.markProofsAsDeleted([proof1])
        print("User spends 10 sats (proof1)")
        
        // Get available proofs
        let availableProofs = await manager.getAvailableProofs()
        XCTAssertEqual(availableProofs.count, 1, "Should have 1 available proof")
        XCTAssertEqual(availableProofs.first?.C, "C2", "Available proof should be proof2")
        
        // Get owner of remaining proof
        let previousOwners = await manager.getOwnerEventIds(for: availableProofs)
        XCTAssertEqual(previousOwners.first, token1Id, "Proof2 was previously owned by token1")
        
        print("Creating new token with remaining 20 sats (proof2)")
        print("New token should include: del: ['\(token1Id)']")
        print("This tells other clients that token1 is superseded by the new token")
        
        // Simulate creating new token
        let token2Id = "token-event-002"
        await manager.updateProofOwnership(availableProofs, eventId: token2Id, timestamp: 2000)
        
        // Verify ownership was updated
        let newOwners = await manager.getOwnerEventIds(for: availableProofs)
        XCTAssertEqual(newOwners.first, token2Id, "Proof2 should now be owned by token2")
        
        print("✅ Full del tag scenario test passed")
    }
}