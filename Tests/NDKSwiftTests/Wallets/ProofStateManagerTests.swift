import XCTest
import CashuSwift
@testable import NDKSwift

/// Tests for ProofStateManager - the core component that tracks proof ownership
/// and enables proper del tag generation
final class ProofStateManagerTests: XCTestCase {
    var manager: ProofStateManager!
    
    override func setUp() async throws {
        try await super.setUp()
        manager = ProofStateManager()
    }
    
    override func tearDown() async throws {
        manager = nil
        try await super.tearDown()
    }
    
    // MARK: - Basic Ownership Tests
    
    func testProofOwnershipTracking() async {
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
        
        // Add proofs with ownership
        await manager.addProof(
            proof1,
            mint: "https://mint.example.com",
            state: .available,
            eventId: "event1",
            timestamp: 1000
        )
        
        await manager.addProof(
            proof2,
            mint: "https://mint.example.com",
            state: .available,
            eventId: "event1",
            timestamp: 1000
        )
        
        // Test getOwnerEventIds
        let owners = await manager.getOwnerEventIds(for: [proof1, proof2])
        XCTAssertEqual(owners.count, 1)
        XCTAssertEqual(owners.first, "event1")
    }
    
    func testOwnershipUpdateWithNewerTimestamp() async {
        let proof = CashuSwift.Proof(
            keysetID: "keyset1",
            amount: 10,
            secret: "secret1",
            C: "C1"
        )
        
        // Add proof with initial owner
        await manager.addProof(
            proof,
            mint: "https://mint.example.com",
            state: .available,
            eventId: "event1",
            timestamp: 1000
        )
        
        // Update with newer timestamp - should update ownership
        await manager.addProof(
            proof,
            mint: "https://mint.example.com",
            state: .available,
            eventId: "event2",
            timestamp: 2000
        )
        
        let owners = await manager.getOwnerEventIds(for: [proof])
        XCTAssertEqual(owners.count, 1)
        XCTAssertEqual(owners.first, "event2")
    }
    
    func testOwnershipUpdateWithOlderTimestamp() async {
        let proof = CashuSwift.Proof(
            keysetID: "keyset1",
            amount: 10,
            secret: "secret1",
            C: "C1"
        )
        
        // Add proof with initial owner
        await manager.addProof(
            proof,
            mint: "https://mint.example.com",
            state: .available,
            eventId: "event1",
            timestamp: 2000
        )
        
        // Try to update with older timestamp - should NOT update ownership
        await manager.addProof(
            proof,
            mint: "https://mint.example.com",
            state: .available,
            eventId: "event2",
            timestamp: 1000
        )
        
        let owners = await manager.getOwnerEventIds(for: [proof])
        XCTAssertEqual(owners.count, 1)
        XCTAssertEqual(owners.first, "event1")
    }
    
    // MARK: - Del Tag Scenario Tests
    
    func testGetOwnerEventIdsForPartiallySpentToken() async {
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
        
        // Both proofs initially owned by event1
        await manager.addProof(proof1, mint: "mint1", eventId: "event1", timestamp: 1000)
        await manager.addProof(proof2, mint: "mint1", eventId: "event1", timestamp: 1000)
        
        // Mark proof1 as deleted (spent)
        await manager.markProofsAsDeleted([proof1])
        
        // Get owner for remaining proof
        let owners = await manager.getOwnerEventIds(for: [proof2])
        XCTAssertEqual(owners.count, 1)
        XCTAssertEqual(owners.first, "event1")
        
        // This is the key info needed for del tag: 
        // When creating a new token with proof2, it should include del: ["event1"]
    }
    
    func testMarkProofsOwnedByEventAsDeleted() async {
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
        
        let proof3 = CashuSwift.Proof(
            keysetID: "keyset1",
            amount: 30,
            secret: "secret3",
            C: "C3"
        )
        
        // Add proofs owned by different events
        await manager.addProof(proof1, mint: "mint1", eventId: "event1", timestamp: 1000)
        await manager.addProof(proof2, mint: "mint1", eventId: "event1", timestamp: 1000)
        await manager.addProof(proof3, mint: "mint1", eventId: "event2", timestamp: 2000)
        
        // Mark proofs owned by event1 as deleted
        let deletedProofs = await manager.markProofsOwnedByEventAsDeleted("event1")
        
        XCTAssertEqual(deletedProofs.count, 2)
        XCTAssertTrue(deletedProofs.contains { $0.C == "C1" })
        XCTAssertTrue(deletedProofs.contains { $0.C == "C2" })
        
        // Verify states
        let state1 = await manager.getProofState(for: "C1")
        let state2 = await manager.getProofState(for: "C2")
        let state3 = await manager.getProofState(for: "C3")
        
        XCTAssertEqual(state1, .deleted)
        XCTAssertEqual(state2, .deleted)
        XCTAssertEqual(state3, .available)
    }
    
    // MARK: - State Management Tests
    
    func testProofReservation() async throws {
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
        
        // Add available proofs
        await manager.addProof(proof1, mint: "mint1")
        await manager.addProof(proof2, mint: "mint1")
        
        // Reserve proof1
        try await manager.reserveProofs([proof1])
        
        // Check states
        let state1 = await manager.getProofState(for: "C1")
        let state2 = await manager.getProofState(for: "C2")
        
        XCTAssertEqual(state1, .reserved)
        XCTAssertEqual(state2, .available)
        
        // Available proofs should not include reserved ones
        let available = await manager.getAvailableProofs()
        XCTAssertEqual(available.count, 1)
        XCTAssertEqual(available[0].C, "C2")
    }
    
    func testProofSelectionForAmount() async {
        // Add proofs with different amounts
        let proofs = [
            CashuSwift.Proof(keysetID: "k1", amount: 1, secret: "s1", C: "C1"),
            CashuSwift.Proof(keysetID: "k1", amount: 2, secret: "s2", C: "C2"),
            CashuSwift.Proof(keysetID: "k1", amount: 4, secret: "s3", C: "C3"),
            CashuSwift.Proof(keysetID: "k1", amount: 8, secret: "s4", C: "C4"),
            CashuSwift.Proof(keysetID: "k1", amount: 16, secret: "s5", C: "C5")
        ]
        
        for proof in proofs {
            await manager.addProof(proof, mint: "mint1")
        }
        
        // Select for amount 10 (should get 1 + 2 + 8 = 11)
        let selected = await manager.selectProofs(amount: 10, mint: "mint1")
        
        XCTAssertEqual(selected.count, 3)
        let totalAmount = selected.reduce(0) { $0 + Int64($1.amount) }
        XCTAssertGreaterThanOrEqual(totalAmount, 10)
    }
}