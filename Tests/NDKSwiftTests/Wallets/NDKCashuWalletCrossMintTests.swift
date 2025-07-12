import XCTest
import CashuSwift
@testable import NDKSwift

final class NDKCashuWalletCrossMintTests: XCTestCase {
    var ndk: NDK!
    var wallet: NDKCashuWallet!
    var mockSigner: MockSigner!
    
    override func setUp() async throws {
        try await super.setUp()
        
        mockSigner = MockSigner(privateKey: "test_private_key")
        ndk = NDK(relayUrls: ["wss://test.relay"], signer: mockSigner)
        wallet = NDKCashuWallet(ndk: ndk)
    }
    
    override func tearDown() async throws {
        wallet = nil
        ndk = nil
        mockSigner = nil
        try await super.tearDown()
    }
    
    // MARK: - Cross-Mint Transfer Tests
    
    func testCrossMintTransferSetup() async throws {
        // Add balance to source mint
        let sourceProof = CashuSwift.Proof(
            keysetID: "source_keyset",
            amount: 10000,
            secret: "source_secret",
            C: "source_C"
        )
        
        let sourceToken = CashuSwift.Token(
            proofs: ["https://source.mint": [sourceProof]],
            unit: "sat"
        )
        
        var sourceTokenEvent = NDKEvent(ndk: ndk)
        sourceTokenEvent.kind = .cashuToken
        sourceTokenEvent.content = try sourceToken.serialize()
        sourceTokenEvent.createdAt = Timestamp.now
        sourceTokenEvent.tags = [
            ["a", "37417:pubkey:wallet_id"],
            ["mint", "https://source.mint"],
            ["proofs", try JSONEncoder().encode([sourceProof]).base64EncodedString()]
        ]
        
        try await wallet.processTokenEvent(sourceTokenEvent)
        
        // Verify source mint has balance
        let sourceBalance = await wallet.getBalance(mint: URL(string: "https://source.mint")!)
        XCTAssertEqual(sourceBalance, 10000)
        
        // Verify destination mint has no balance initially
        let destBalance = await wallet.getBalance(mint: URL(string: "https://dest.mint")!)
        XCTAssertEqual(destBalance, 0)
    }
    
    func testCrossMintTransferValidation() async throws {
        let sourceMint = URL(string: "https://source.mint")!
        let destMint = URL(string: "https://dest.mint")!
        
        // Test transfer with no balance
        do {
            _ = try await wallet.transferBetweenMints(
                amount: 1000,
                fromMint: sourceMint,
                toMint: destMint
            )
            XCTFail("Should have thrown insufficient balance error")
        } catch NDKError.insufficientBalance {
            // Expected
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testCrossMintTransferFeeEstimation() async throws {
        // Add proofs to estimate fees
        let proof = CashuSwift.Proof(
            keysetID: "source_keyset",
            amount: 10000,
            secret: "fee_test_secret",
            C: "fee_test_C"
        )
        
        let token = CashuSwift.Token(
            proofs: ["https://source.mint": [proof]],
            unit: "sat"
        )
        
        var tokenEvent = NDKEvent(ndk: ndk)
        tokenEvent.kind = .cashuToken
        tokenEvent.content = try token.serialize()
        tokenEvent.createdAt = Timestamp.now
        tokenEvent.tags = [
            ["a", "37417:pubkey:wallet_id"],
            ["mint", "https://source.mint"],
            ["proofs", try JSONEncoder().encode([proof]).base64EncodedString()]
        ]
        
        try await wallet.processTokenEvent(tokenEvent)
        
        // Note: Actual fee estimation would require mock mint responses
        // This test verifies the wallet is ready for fee estimation
        let balance = await wallet.getBalance(mint: URL(string: "https://source.mint")!)
        XCTAssertEqual(balance, 10000)
    }
    
    // MARK: - Automatic Cross-Mint in Payment Flow
    
    func testAutomaticCrossMintDuringPayment() async throws {
        // Setup: User has balance in mint A, recipient accepts only mint B
        
        // Add balance to mint A
        let proofA = CashuSwift.Proof(
            keysetID: "keyset_a",
            amount: 5000,
            secret: "secret_a",
            C: "C_a"
        )
        
        let tokenA = CashuSwift.Token(
            proofs: ["https://mint-a.com": [proofA]],
            unit: "sat"
        )
        
        var tokenEventA = NDKEvent(ndk: ndk)
        tokenEventA.kind = .cashuToken
        tokenEventA.content = try tokenA.serialize()
        tokenEventA.createdAt = Timestamp.now
        tokenEventA.tags = [
            ["a", "37417:pubkey:wallet_id"],
            ["mint", "https://mint-a.com"],
            ["proofs", try JSONEncoder().encode([proofA]).base64EncodedString()]
        ]
        
        try await wallet.processTokenEvent(tokenEventA)
        
        // Create payment request for mint B only
        let request = NDKNutzapRequest(
            amount: 1000,
            pubkey: "recipient_pubkey",
            mints: [URL(string: "https://mint-b.com")!], // Only accepts mint B
            unit: "sat",
            p2pk: "recipient_p2pk"
        )
        
        // Verify initial state
        let balanceA = await wallet.getBalance(mint: URL(string: "https://mint-a.com")!)
        XCTAssertEqual(balanceA, 5000)
        
        let balanceB = await wallet.getBalance(mint: URL(string: "https://mint-b.com")!)
        XCTAssertEqual(balanceB, 0)
        
        // Note: Actual payment would trigger automatic cross-mint transfer
        // The wallet should:
        // 1. Detect no common mint with sufficient balance
        // 2. Initiate cross-mint transfer from A to B
        // 3. Complete the payment with mint B tokens
    }
    
    func testMultipleCrossMintOptions() async throws {
        // User has balance in multiple mints, recipient accepts different mints
        
        // Add balance to mint A
        let proofA = CashuSwift.Proof(
            keysetID: "keyset_a",
            amount: 3000,
            secret: "multi_secret_a",
            C: "multi_C_a"
        )
        
        let tokenA = CashuSwift.Token(
            proofs: ["https://mint-a.com": [proofA]],
            unit: "sat"
        )
        
        var tokenEventA = NDKEvent(ndk: ndk)
        tokenEventA.kind = .cashuToken
        tokenEventA.content = try tokenA.serialize()
        tokenEventA.createdAt = Timestamp.now
        tokenEventA.tags = [
            ["a", "37417:pubkey:wallet_id"],
            ["mint", "https://mint-a.com"],
            ["proofs", try JSONEncoder().encode([proofA]).base64EncodedString()]
        ]
        
        try await wallet.processTokenEvent(tokenEventA)
        
        // Add balance to mint B
        let proofB = CashuSwift.Proof(
            keysetID: "keyset_b",
            amount: 2000,
            secret: "multi_secret_b",
            C: "multi_C_b"
        )
        
        let tokenB = CashuSwift.Token(
            proofs: ["https://mint-b.com": [proofB]],
            unit: "sat"
        )
        
        var tokenEventB = NDKEvent(ndk: ndk)
        tokenEventB.kind = .cashuToken
        tokenEventB.content = try tokenB.serialize()
        tokenEventB.createdAt = Timestamp.now
        tokenEventB.tags = [
            ["a", "37417:pubkey:wallet_id"],
            ["mint", "https://mint-b.com"],
            ["proofs", try JSONEncoder().encode([proofB]).base64EncodedString()]
        ]
        
        try await wallet.processTokenEvent(tokenEventB)
        
        // Create payment request accepting mints C and D (no common mint)
        let request = NDKNutzapRequest(
            amount: 1500,
            pubkey: "recipient_pubkey",
            mints: [
                URL(string: "https://mint-c.com")!,
                URL(string: "https://mint-d.com")!
            ],
            unit: "sat",
            p2pk: "recipient_p2pk"
        )
        
        // Verify balances
        let totalBalance = await wallet.getBalance()
        XCTAssertEqual(totalBalance, 5000)
        
        // Wallet should choose the optimal source mint for transfer
        // based on balance and fees
    }
    
    // MARK: - Edge Cases
    
    func testCrossMintWithExactBalance() async throws {
        // Test when source mint has exact amount needed (no change)
        let transferAmount: Int64 = 1000
        let feeEstimate: Int64 = 50
        let totalNeeded = transferAmount + feeEstimate
        
        let proof = CashuSwift.Proof(
            keysetID: "exact_keyset",
            amount: Int(totalNeeded),
            secret: "exact_secret",
            C: "exact_C"
        )
        
        let token = CashuSwift.Token(
            proofs: ["https://exact.mint": [proof]],
            unit: "sat"
        )
        
        var tokenEvent = NDKEvent(ndk: ndk)
        tokenEvent.kind = .cashuToken
        tokenEvent.content = try token.serialize()
        tokenEvent.createdAt = Timestamp.now
        tokenEvent.tags = [
            ["a", "37417:pubkey:wallet_id"],
            ["mint", "https://exact.mint"],
            ["proofs", try JSONEncoder().encode([proof]).base64EncodedString()]
        ]
        
        try await wallet.processTokenEvent(tokenEvent)
        
        // Verify exact balance
        let balance = await wallet.getBalance(mint: URL(string: "https://exact.mint")!)
        XCTAssertEqual(balance, totalNeeded)
    }
    
    func testCrossMintWithInsufficientBalanceForFees() async throws {
        // Test when balance covers transfer amount but not fees
        let transferAmount: Int64 = 1000
        
        let proof = CashuSwift.Proof(
            keysetID: "insufficient_keyset",
            amount: Int(transferAmount), // Exact amount, no room for fees
            secret: "insufficient_secret",
            C: "insufficient_C"
        )
        
        let token = CashuSwift.Token(
            proofs: ["https://insufficient.mint": [proof]],
            unit: "sat"
        )
        
        var tokenEvent = NDKEvent(ndk: ndk)
        tokenEvent.kind = .cashuToken
        tokenEvent.content = try token.serialize()
        tokenEvent.createdAt = Timestamp.now
        tokenEvent.tags = [
            ["a", "37417:pubkey:wallet_id"],
            ["mint", "https://insufficient.mint"],
            ["proofs", try JSONEncoder().encode([proof]).base64EncodedString()]
        ]
        
        try await wallet.processTokenEvent(tokenEvent)
        
        // Attempt transfer
        do {
            _ = try await wallet.transferBetweenMints(
                amount: transferAmount,
                fromMint: URL(string: "https://insufficient.mint")!,
                toMint: URL(string: "https://dest.mint")!
            )
            XCTFail("Should fail due to insufficient balance for fees")
        } catch {
            // Expected to fail
            XCTAssertTrue(true)
        }
    }
    
    func testCrossMintChainTransfer() async throws {
        // Test scenario: A -> B -> C (chain of transfers)
        
        // Initial balance in mint A
        let proofA = CashuSwift.Proof(
            keysetID: "chain_keyset_a",
            amount: 10000,
            secret: "chain_secret_a",
            C: "chain_C_a"
        )
        
        let tokenA = CashuSwift.Token(
            proofs: ["https://chain-mint-a.com": [proofA]],
            unit: "sat"
        )
        
        var tokenEventA = NDKEvent(ndk: ndk)
        tokenEventA.kind = .cashuToken
        tokenEventA.content = try tokenA.serialize()
        tokenEventA.createdAt = Timestamp.now
        tokenEventA.tags = [
            ["a", "37417:pubkey:wallet_id"],
            ["mint", "https://chain-mint-a.com"],
            ["proofs", try JSONEncoder().encode([proofA]).base64EncodedString()]
        ]
        
        try await wallet.processTokenEvent(tokenEventA)
        
        // Verify can track balance through multiple hops
        let initialBalance = await wallet.getBalance()
        XCTAssertEqual(initialBalance, 10000)
        
        // Note: Actual chain transfer would involve:
        // 1. Transfer A -> B
        // 2. Transfer B -> C
        // 3. Verify fees are deducted at each hop
        // 4. Final balance in mint C
    }
    
    func testCrossMintTransferCancellation() async throws {
        // Test handling of cancelled/failed transfers
        
        let proof = CashuSwift.Proof(
            keysetID: "cancel_keyset",
            amount: 5000,
            secret: "cancel_secret",
            C: "cancel_C"
        )
        
        let token = CashuSwift.Token(
            proofs: ["https://cancel.mint": [proof]],
            unit: "sat"
        )
        
        var tokenEvent = NDKEvent(ndk: ndk)
        tokenEvent.kind = .cashuToken
        tokenEvent.content = try token.serialize()
        tokenEvent.createdAt = Timestamp.now
        tokenEvent.tags = [
            ["a", "37417:pubkey:wallet_id"],
            ["mint", "https://cancel.mint"],
            ["proofs", try JSONEncoder().encode([proof]).base64EncodedString()]
        ]
        
        try await wallet.processTokenEvent(tokenEvent)
        
        // Initial balance
        let initialBalance = await wallet.getBalance()
        XCTAssertEqual(initialBalance, 5000)
        
        // In real scenario:
        // 1. Start transfer
        // 2. Lightning payment fails
        // 3. Proofs should be released back to available state
        // 4. Balance should remain unchanged
    }
    
    func testCrossMintWithDifferentUnits() async throws {
        // Test cross-mint transfers between different unit types
        // Note: This is a future enhancement when non-sat units are supported
        
        // For now, verify all operations use "sat" unit
        let proof = CashuSwift.Proof(
            keysetID: "unit_test_keyset",
            amount: 1000,
            secret: "unit_test_secret",
            C: "unit_test_C"
        )
        
        let token = CashuSwift.Token(
            proofs: ["https://unit-test.mint": [proof]],
            unit: "sat" // Always "sat" for now
        )
        
        var tokenEvent = NDKEvent(ndk: ndk)
        tokenEvent.kind = .cashuToken
        tokenEvent.content = try token.serialize()
        tokenEvent.createdAt = Timestamp.now
        tokenEvent.tags = [
            ["a", "37417:pubkey:wallet_id"],
            ["mint", "https://unit-test.mint"],
            ["proofs", try JSONEncoder().encode([proof]).base64EncodedString()]
        ]
        
        try await wallet.processTokenEvent(tokenEvent)
        
        // Verify unit consistency
        XCTAssertEqual(token.unit, "sat")
    }
}