import XCTest
@testable import NDKSwift
import CashuSwift

final class WalletStateCalculatorTests: XCTestCase {
    
    var proofStateManager: ProofStateManager!
    
    override func setUp() async throws {
        proofStateManager = ProofStateManager()
    }
    
    func testEmptyStateChange() async throws {
        // Given
        let stateChange = WalletStateChange(
            store: [],
            destroy: [],
            mint: "https://mint.example.com",
            memo: nil
        )
        
        // When
        let tokenChange = await WalletStateCalculator.calculateNewState(
            stateChange: stateChange,
            proofStateManager: proofStateManager
        )
        
        // Then
        XCTAssertTrue(tokenChange.deletedTokenIds.isEmpty)
        XCTAssertTrue(tokenChange.saveProofs.isEmpty)
    }
    
    func testStoreOnlyDoesNotDeleteTokens() async throws {
        // Given - existing token with one proof
        let existingProof = createMockProof(amount: 100, C: "existing")
        await proofStateManager.addProof(existingProof, mint: "https://mint.example.com")
        await proofStateManager.updateProofOwnership([existingProof], eventId: "token1", timestamp: 1000)
        
        // New proof to add
        let newProof = createMockProof(amount: 50, C: "new")
        
        let stateChange = WalletStateChange(
            store: [newProof],
            destroy: [],
            mint: "https://mint.example.com",
            memo: "Deposit"
        )
        
        // When
        let tokenChange = await WalletStateCalculator.calculateNewState(
            stateChange: stateChange,
            proofStateManager: proofStateManager
        )
        
        // Then
        XCTAssertTrue(tokenChange.deletedTokenIds.isEmpty, "No tokens should be deleted for deposit")
        XCTAssertEqual(tokenChange.saveProofs.count, 1)
        XCTAssertEqual(tokenChange.saveProofs.first?.C, "new")
    }
    
    func testDestroyProofsDeletesToken() async throws {
        // Given - token with two proofs
        let proof1 = createMockProof(amount: 100, C: "proof1")
        let proof2 = createMockProof(amount: 50, C: "proof2")
        
        await proofStateManager.addProof(proof1, mint: "https://mint.example.com")
        await proofStateManager.addProof(proof2, mint: "https://mint.example.com")
        await proofStateManager.updateProofOwnership([proof1, proof2], eventId: "token1", timestamp: 1000)
        
        // Destroy one proof, keep the other
        let stateChange = WalletStateChange(
            store: [],
            destroy: [proof1],
            mint: "https://mint.example.com",
            memo: "Partial spend"
        )
        
        // When
        let tokenChange = await WalletStateCalculator.calculateNewState(
            stateChange: stateChange,
            proofStateManager: proofStateManager
        )
        
        // Then
        XCTAssertEqual(tokenChange.deletedTokenIds, ["token1"])
        XCTAssertEqual(tokenChange.saveProofs.count, 1)
        XCTAssertEqual(tokenChange.saveProofs.first?.C, "proof2", "Unspent proof should be saved")
    }
    
    func testMixedOperationWithChange() async throws {
        // Given - existing proofs
        let proof1 = createMockProof(amount: 100, C: "proof1")
        let proof2 = createMockProof(amount: 50, C: "proof2")
        
        await proofStateManager.addProof(proof1, mint: "https://mint.example.com")
        await proofStateManager.addProof(proof2, mint: "https://mint.example.com")
        await proofStateManager.updateProofOwnership([proof1, proof2], eventId: "token1", timestamp: 1000)
        
        // Change from spending
        let changeProof = createMockProof(amount: 25, C: "change")
        
        let stateChange = WalletStateChange(
            store: [changeProof],
            destroy: [proof1, proof2],
            mint: "https://mint.example.com",
            memo: "Spend with change"
        )
        
        // When
        let tokenChange = await WalletStateCalculator.calculateNewState(
            stateChange: stateChange,
            proofStateManager: proofStateManager
        )
        
        // Then
        XCTAssertEqual(tokenChange.deletedTokenIds, ["token1"])
        XCTAssertEqual(tokenChange.saveProofs.count, 1)
        XCTAssertEqual(tokenChange.saveProofs.first?.C, "change")
    }
    
    func testMultipleTokensAffected() async throws {
        // Given - two tokens
        let token1Proof = createMockProof(amount: 100, C: "token1proof")
        let token2Proof = createMockProof(amount: 50, C: "token2proof")
        
        await proofStateManager.addProof(token1Proof, mint: "https://mint.example.com")
        await proofStateManager.addProof(token2Proof, mint: "https://mint.example.com")
        await proofStateManager.updateProofOwnership([token1Proof], eventId: "token1", timestamp: 1000)
        await proofStateManager.updateProofOwnership([token2Proof], eventId: "token2", timestamp: 1000)
        
        // Destroy both
        let stateChange = WalletStateChange(
            store: [],
            destroy: [token1Proof, token2Proof],
            mint: "https://mint.example.com",
            memo: "Spend all"
        )
        
        // When
        let tokenChange = await WalletStateCalculator.calculateNewState(
            stateChange: stateChange,
            proofStateManager: proofStateManager
        )
        
        // Then
        XCTAssertEqual(tokenChange.deletedTokenIds, ["token1", "token2"])
        XCTAssertTrue(tokenChange.saveProofs.isEmpty)
    }
    
    // MARK: - Helper
    
    private func createMockProof(amount: Int64, C: String) -> CashuSwift.Proof {
        return CashuSwift.Proof(
            keysetID: "test-keyset",
            amount: Int(amount),
            secret: "secret-\(C)",
            C: C
        )
    }
}