import XCTest
import CashuSwift
@testable import NDKSwift

final class NDKCashuWalletProofStateTests: XCTestCase {
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
    
    // MARK: - Proof State Reconciliation Tests
    
    func testProofStateCheckingWithAllUnspent() async throws {
        // Add proofs to wallet
        let proof1 = CashuSwift.Proof(
            keysetID: "test_keyset",
            amount: 100,
            secret: "secret_1",
            C: "C_1"
        )
        let proof2 = CashuSwift.Proof(
            keysetID: "test_keyset",
            amount: 200,
            secret: "secret_2",
            C: "C_2"
        )
        
        let token = CashuSwift.Token(
            proofs: ["https://test.mint": [proof1, proof2]],
            unit: "sat"
        )
        
        var tokenEvent = NDKEvent(ndk: ndk)
        tokenEvent.kind = .cashuToken
        tokenEvent.content = try token.serialize()
        tokenEvent.createdAt = Timestamp.now
        tokenEvent.tags = [
            ["a", "37417:pubkey:wallet_id"],
            ["mint", "https://test.mint"],
            ["proofs", try JSONEncoder().encode([proof1, proof2]).base64EncodedString()]
        ]
        
        try await wallet.processTokenEvent(tokenEvent)
        
        // Verify initial balance
        let balance = await wallet.getBalance()
        XCTAssertEqual(balance, 300)
        
        // Note: Actual proof state checking would require mock mint responses
        // This test verifies the wallet maintains proper state before reconciliation
    }
    
    func testProofStateCheckingWithMixedStates() async throws {
        // Add multiple proofs
        let proofs = (1...5).map { i in
            CashuSwift.Proof(
                keysetID: "test_keyset",
                amount: i * 100,
                secret: "secret_\(i)",
                C: "C_\(i)"
            )
        }
        
        let token = CashuSwift.Token(
            proofs: ["https://test.mint": proofs],
            unit: "sat"
        )
        
        var tokenEvent = NDKEvent(ndk: ndk)
        tokenEvent.kind = .cashuToken
        tokenEvent.content = try token.serialize()
        tokenEvent.createdAt = Timestamp.now
        tokenEvent.tags = [
            ["a", "37417:pubkey:wallet_id"],
            ["mint", "https://test.mint"],
            ["proofs", try JSONEncoder().encode(proofs).base64EncodedString()]
        ]
        
        try await wallet.processTokenEvent(tokenEvent)
        
        // Initial balance should be 1500 (100+200+300+400+500)
        let balance = await wallet.getBalance()
        XCTAssertEqual(balance, 1500)
        
        // Note: Testing actual reconciliation would require:
        // 1. Mock mint server that returns different states for proofs
        // 2. Ability to trigger reconciliation and verify state updates
        // 3. Checking that spent proofs are properly removed
    }
    
    func testProofStateCheckingAcrossMultipleMints() async throws {
        // Add proofs to first mint
        let mint1Proofs = [
            CashuSwift.Proof(
                keysetID: "keyset_1",
                amount: 100,
                secret: "mint1_secret_1",
                C: "mint1_C_1"
            ),
            CashuSwift.Proof(
                keysetID: "keyset_1",
                amount: 200,
                secret: "mint1_secret_2",
                C: "mint1_C_2"
            )
        ]
        
        let token1 = CashuSwift.Token(
            proofs: ["https://mint1.com": mint1Proofs],
            unit: "sat"
        )
        
        var tokenEvent1 = NDKEvent(ndk: ndk)
        tokenEvent1.kind = .cashuToken
        tokenEvent1.content = try token1.serialize()
        tokenEvent1.createdAt = Timestamp.now
        tokenEvent1.tags = [
            ["a", "37417:pubkey:wallet_id"],
            ["mint", "https://mint1.com"],
            ["proofs", try JSONEncoder().encode(mint1Proofs).base64EncodedString()]
        ]
        
        try await wallet.processTokenEvent(tokenEvent1)
        
        // Add proofs to second mint
        let mint2Proofs = [
            CashuSwift.Proof(
                keysetID: "keyset_2",
                amount: 300,
                secret: "mint2_secret_1",
                C: "mint2_C_1"
            )
        ]
        
        let token2 = CashuSwift.Token(
            proofs: ["https://mint2.com": mint2Proofs],
            unit: "sat"
        )
        
        var tokenEvent2 = NDKEvent(ndk: ndk)
        tokenEvent2.kind = .cashuToken
        tokenEvent2.content = try token2.serialize()
        tokenEvent2.createdAt = Timestamp.now
        tokenEvent2.tags = [
            ["a", "37417:pubkey:wallet_id"],
            ["mint", "https://mint2.com"],
            ["proofs", try JSONEncoder().encode(mint2Proofs).base64EncodedString()]
        ]
        
        try await wallet.processTokenEvent(tokenEvent2)
        
        // Total balance should be 600
        let totalBalance = await wallet.getBalance()
        XCTAssertEqual(totalBalance, 600)
        
        // Per-mint balances
        let mint1Balance = await wallet.getBalance(mint: URL(string: "https://mint1.com")!)
        XCTAssertEqual(mint1Balance, 300)
        
        let mint2Balance = await wallet.getBalance(mint: URL(string: "https://mint2.com")!)
        XCTAssertEqual(mint2Balance, 300)
    }
    
    // MARK: - Reconciliation Edge Cases
    
    func testReconciliationWithPartiallySpentTokenEvent() async throws {
        // Create a token event with multiple proofs
        let proof1 = CashuSwift.Proof(
            keysetID: "test_keyset",
            amount: 100,
            secret: "secret_1",
            C: "C_1"
        )
        let proof2 = CashuSwift.Proof(
            keysetID: "test_keyset",
            amount: 200,
            secret: "secret_2",
            C: "C_2"
        )
        let proof3 = CashuSwift.Proof(
            keysetID: "test_keyset",
            amount: 300,
            secret: "secret_3",
            C: "C_3"
        )
        
        let token = CashuSwift.Token(
            proofs: ["https://test.mint": [proof1, proof2, proof3]],
            unit: "sat"
        )
        
        var tokenEvent = NDKEvent(ndk: ndk)
        tokenEvent.id = "original_token_event"
        tokenEvent.kind = .cashuToken
        tokenEvent.content = try token.serialize()
        tokenEvent.createdAt = Timestamp.now
        tokenEvent.tags = [
            ["a", "37417:pubkey:wallet_id"],
            ["mint", "https://test.mint"],
            ["proofs", try JSONEncoder().encode([proof1, proof2, proof3]).base64EncodedString()]
        ]
        
        try await wallet.processTokenEvent(tokenEvent)
        
        // Initial balance should be 600
        let initialBalance = await wallet.getBalance()
        XCTAssertEqual(initialBalance, 600)
        
        // In a real scenario, reconciliation would:
        // 1. Discover proof1 is spent
        // 2. Create a new token event with only proof2 and proof3
        // 3. Delete the original token event
        // 4. Update balance to 500
    }
    
    func testReconciliationWithAllProofsSpent() async throws {
        // Add a single proof
        let proof = CashuSwift.Proof(
            keysetID: "test_keyset",
            amount: 1000,
            secret: "secret_spent",
            C: "C_spent"
        )
        
        let token = CashuSwift.Token(
            proofs: ["https://test.mint": [proof]],
            unit: "sat"
        )
        
        var tokenEvent = NDKEvent(ndk: ndk)
        tokenEvent.id = "spent_token_event"
        tokenEvent.kind = .cashuToken
        tokenEvent.content = try token.serialize()
        tokenEvent.createdAt = Timestamp.now
        tokenEvent.tags = [
            ["a", "37417:pubkey:wallet_id"],
            ["mint", "https://test.mint"],
            ["proofs", try JSONEncoder().encode([proof]).base64EncodedString()]
        ]
        
        try await wallet.processTokenEvent(tokenEvent)
        
        // Initial balance
        let initialBalance = await wallet.getBalance()
        XCTAssertEqual(initialBalance, 1000)
        
        // In real reconciliation:
        // 1. Discover all proofs are spent
        // 2. Delete the token event
        // 3. Create spending history event
        // 4. Balance becomes 0
    }
    
    func testReconciliationWithNetworkError() async throws {
        // Add proofs
        let proof = CashuSwift.Proof(
            keysetID: "test_keyset",
            amount: 500,
            secret: "secret_network_test",
            C: "C_network_test"
        )
        
        let token = CashuSwift.Token(
            proofs: ["https://unreachable.mint": [proof]],
            unit: "sat"
        )
        
        var tokenEvent = NDKEvent(ndk: ndk)
        tokenEvent.kind = .cashuToken
        tokenEvent.content = try token.serialize()
        tokenEvent.createdAt = Timestamp.now
        tokenEvent.tags = [
            ["a", "37417:pubkey:wallet_id"],
            ["mint", "https://unreachable.mint"],
            ["proofs", try JSONEncoder().encode([proof]).base64EncodedString()]
        ]
        
        try await wallet.processTokenEvent(tokenEvent)
        
        // Balance should still be tracked
        let balance = await wallet.getBalance()
        XCTAssertEqual(balance, 500)
        
        // Reconciliation should:
        // 1. Attempt to check with mint
        // 2. Handle network error gracefully
        // 3. Continue with other mints
        // 4. Not modify state for unreachable mint
    }
    
    // MARK: - Periodic Check Tests
    
    func testPeriodicProofStateCheckInitialization() async throws {
        // Test that periodic checking can be started
        // In a real test, we'd need to mock Task.sleep and verify execution
        
        // Start periodic checking with short interval for testing
        let checkTask = Task {
            await wallet.startPeriodicProofStateCheck(interval: 1.0)
        }
        
        // Let it run briefly
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Cancel the task
        checkTask.cancel()
        
        // Verify task was cancelled properly
        let result = await checkTask.result
        XCTAssertThrowsError(try result.get()) { error in
            XCTAssertTrue(error is CancellationError)
        }
    }
    
    // MARK: - State Consistency Tests
    
    func testProofStateConsistencyAfterMultipleOperations() async throws {
        // Add initial proofs
        let proof1 = CashuSwift.Proof(
            keysetID: "test_keyset",
            amount: 1000,
            secret: "consistency_secret_1",
            C: "consistency_C_1"
        )
        
        let token1 = CashuSwift.Token(
            proofs: ["https://test.mint": [proof1]],
            unit: "sat"
        )
        
        var tokenEvent1 = NDKEvent(ndk: ndk)
        tokenEvent1.id = "event_1"
        tokenEvent1.kind = .cashuToken
        tokenEvent1.content = try token1.serialize()
        tokenEvent1.createdAt = Timestamp(100)
        tokenEvent1.tags = [
            ["a", "37417:pubkey:wallet_id"],
            ["mint", "https://test.mint"],
            ["proofs", try JSONEncoder().encode([proof1]).base64EncodedString()]
        ]
        
        try await wallet.processTokenEvent(tokenEvent1)
        
        // Add more proofs
        let proof2 = CashuSwift.Proof(
            keysetID: "test_keyset",
            amount: 500,
            secret: "consistency_secret_2",
            C: "consistency_C_2"
        )
        
        let token2 = CashuSwift.Token(
            proofs: ["https://test.mint": [proof2]],
            unit: "sat"
        )
        
        var tokenEvent2 = NDKEvent(ndk: ndk)
        tokenEvent2.id = "event_2"
        tokenEvent2.kind = .cashuToken
        tokenEvent2.content = try token2.serialize()
        tokenEvent2.createdAt = Timestamp(200)
        tokenEvent2.tags = [
            ["a", "37417:pubkey:wallet_id"],
            ["mint", "https://test.mint"],
            ["proofs", try JSONEncoder().encode([proof2]).base64EncodedString()]
        ]
        
        try await wallet.processTokenEvent(tokenEvent2)
        
        // Create superseding event
        let proof3 = CashuSwift.Proof(
            keysetID: "test_keyset",
            amount: 250,
            secret: "consistency_secret_3",
            C: "consistency_C_3"
        )
        
        let token3 = CashuSwift.Token(
            proofs: ["https://test.mint": [proof3]],
            unit: "sat"
        )
        
        var tokenEvent3 = NDKEvent(ndk: ndk)
        tokenEvent3.id = "event_3"
        tokenEvent3.kind = .cashuToken
        tokenEvent3.content = try token3.serialize()
        tokenEvent3.createdAt = Timestamp(300)
        tokenEvent3.tags = [
            ["a", "37417:pubkey:wallet_id"],
            ["mint", "https://test.mint"],
            ["proofs", try JSONEncoder().encode([proof3]).base64EncodedString()],
            ["e", "event_1", "", "del"] // Supersedes event_1
        ]
        
        try await wallet.processTokenEvent(tokenEvent3)
        
        // Final balance should be 750 (500 from event_2 + 250 from event_3)
        // event_1 should be ignored due to del tag
        let finalBalance = await wallet.getBalance()
        XCTAssertEqual(finalBalance, 750)
    }
    
    func testProofStateWithConcurrentUpdates() async throws {
        // Test concurrent proof state updates
        let proofs = (1...10).map { i in
            CashuSwift.Proof(
                keysetID: "test_keyset",
                amount: i * 10,
                secret: "concurrent_secret_\(i)",
                C: "concurrent_C_\(i)"
            )
        }
        
        // Create multiple token events concurrently
        await withTaskGroup(of: Void.self) { group in
            for (index, proof) in proofs.enumerated() {
                group.addTask {
                    let token = CashuSwift.Token(
                        proofs: ["https://test.mint": [proof]],
                        unit: "sat"
                    )
                    
                    var tokenEvent = NDKEvent(ndk: self.ndk)
                    tokenEvent.id = "concurrent_event_\(index)"
                    tokenEvent.kind = .cashuToken
                    tokenEvent.content = try! token.serialize()
                    tokenEvent.createdAt = Timestamp.now + Timestamp(index)
                    tokenEvent.tags = [
                        ["a", "37417:pubkey:wallet_id"],
                        ["mint", "https://test.mint"],
                        ["proofs", try! JSONEncoder().encode([proof]).base64EncodedString()]
                    ]
                    
                    try? await self.wallet.processTokenEvent(tokenEvent)
                }
            }
        }
        
        // Verify final balance is sum of all proofs
        let expectedBalance = proofs.reduce(0) { $0 + Int64($1.amount) }
        let actualBalance = await wallet.getBalance()
        XCTAssertEqual(actualBalance, expectedBalance)
    }
}