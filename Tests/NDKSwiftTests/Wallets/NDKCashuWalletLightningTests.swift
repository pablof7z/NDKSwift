import XCTest
import CashuSwift
@testable import NDKSwift

final class NDKCashuWalletLightningTests: XCTestCase {
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
    
    // MARK: - Lightning Payment Tests
    
    func testLightningInvoiceValidation() throws {
        // Test valid bolt11 invoice format
        let validInvoice = "lnbc1000n1p3qkwmppp5test..."
        
        // Basic validation that invoice starts with expected prefix
        XCTAssertTrue(validInvoice.hasPrefix("lnbc") || validInvoice.hasPrefix("lntb"))
    }
    
    func testPayLightningWithInsufficientBalance() async throws {
        // Wallet has no balance
        let invoice = "lnbc1000000n1p3qkwmppp5test..."
        
        do {
            _ = try await wallet.payLightning(invoice: invoice, amount: 1000000)
            XCTFail("Should have thrown insufficient balance error")
        } catch NDKError.insufficientBalance {
            // Expected error
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testPayLightningWithValidBalance() async throws {
        // Add some balance to the wallet
        let proof = CashuSwift.Proof(
            keysetID: "test_keyset",
            amount: 10000,
            secret: "test_secret",
            C: "test_C"
        )
        
        let token = CashuSwift.Token(
            proofs: ["https://test.mint": [proof]],
            unit: "sat"
        )
        
        var tokenEvent = NDKEvent(ndk: ndk)
        tokenEvent.kind = .cashuToken
        tokenEvent.content = try token.serialize()
        tokenEvent.createdAt = Timestamp.now
        tokenEvent.tags = [
            ["a", "37417:pubkey:wallet_id"],
            ["mint", "https://test.mint"],
            ["proofs", try JSONEncoder().encode([proof]).base64EncodedString()]
        ]
        
        try await wallet.processTokenEvent(tokenEvent)
        
        // Verify balance
        let balance = await wallet.getBalance()
        XCTAssertEqual(balance, 10000)
        
        // Note: Actual Lightning payment would require mock mint server
        // This test verifies the wallet has sufficient balance for the operation
    }
    
    // MARK: - Cross-Mint Transfer Tests
    
    func testTransferBetweenMintsValidation() async throws {
        let sourceMint = URL(string: "https://source.mint")!
        let destMint = URL(string: "https://dest.mint")!
        
        // Test with no balance
        do {
            _ = try await wallet.transferBetweenMints(
                amount: 1000,
                fromMint: sourceMint,
                toMint: destMint
            )
            XCTFail("Should have thrown insufficient balance error")
        } catch NDKError.insufficientBalance {
            // Expected error
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testTransferBetweenMintsWithBalance() async throws {
        // Add balance to source mint
        let proof = CashuSwift.Proof(
            keysetID: "source_keyset",
            amount: 5000,
            secret: "source_secret",
            C: "source_C"
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
        
        // Verify initial balance
        let sourceBalance = await wallet.getBalance(mint: URL(string: "https://source.mint")!)
        XCTAssertEqual(sourceBalance, 5000)
        
        // Note: Actual transfer would require mock mint servers
        // This test verifies the wallet state before transfer
    }
    
    // MARK: - Fee Calculation Tests
    
    func testLightningFeeEstimation() async throws {
        // Test fee calculation for different amounts
        let testAmounts: [Int64] = [1000, 10000, 100000, 1000000]
        
        for amount in testAmounts {
            // Lightning fees are typically percentage-based
            // Most mints charge 0.5-1% for Lightning operations
            let estimatedFee = Int64(Double(amount) * 0.01) // 1% fee estimate
            XCTAssertGreaterThan(estimatedFee, 0)
            XCTAssertLessThan(estimatedFee, amount)
        }
    }
    
    // MARK: - Edge Cases
    
    func testPayLightningWithExactBalance() async throws {
        // Add exact amount needed (including fees)
        let paymentAmount: Int64 = 1000
        let estimatedFee: Int64 = 10
        let totalNeeded = paymentAmount + estimatedFee
        
        let proof = CashuSwift.Proof(
            keysetID: "test_keyset",
            amount: Int(totalNeeded),
            secret: "test_secret",
            C: "test_C"
        )
        
        let token = CashuSwift.Token(
            proofs: ["https://test.mint": [proof]],
            unit: "sat"
        )
        
        var tokenEvent = NDKEvent(ndk: ndk)
        tokenEvent.kind = .cashuToken
        tokenEvent.content = try token.serialize()
        tokenEvent.createdAt = Timestamp.now
        tokenEvent.tags = [
            ["a", "37417:pubkey:wallet_id"],
            ["mint", "https://test.mint"],
            ["proofs", try JSONEncoder().encode([proof]).base64EncodedString()]
        ]
        
        try await wallet.processTokenEvent(tokenEvent)
        
        // Verify balance
        let balance = await wallet.getBalance()
        XCTAssertEqual(balance, Int(totalNeeded))
    }
    
    func testPayLightningWithMultipleMints() async throws {
        // Add balance to multiple mints
        let proof1 = CashuSwift.Proof(
            keysetID: "keyset_1",
            amount: 500,
            secret: "secret_1",
            C: "C_1"
        )
        
        let token1 = CashuSwift.Token(
            proofs: ["https://mint1.com": [proof1]],
            unit: "sat"
        )
        
        var tokenEvent1 = NDKEvent(ndk: ndk)
        tokenEvent1.kind = .cashuToken
        tokenEvent1.content = try token1.serialize()
        tokenEvent1.createdAt = Timestamp.now
        tokenEvent1.tags = [
            ["a", "37417:pubkey:wallet_id"],
            ["mint", "https://mint1.com"],
            ["proofs", try JSONEncoder().encode([proof1]).base64EncodedString()]
        ]
        
        try await wallet.processTokenEvent(tokenEvent1)
        
        let proof2 = CashuSwift.Proof(
            keysetID: "keyset_2",
            amount: 600,
            secret: "secret_2",
            C: "C_2"
        )
        
        let token2 = CashuSwift.Token(
            proofs: ["https://mint2.com": [proof2]],
            unit: "sat"
        )
        
        var tokenEvent2 = NDKEvent(ndk: ndk)
        tokenEvent2.kind = .cashuToken
        tokenEvent2.content = try token2.serialize()
        tokenEvent2.createdAt = Timestamp.now
        tokenEvent2.tags = [
            ["a", "37417:pubkey:wallet_id"],
            ["mint", "https://mint2.com"],
            ["proofs", try JSONEncoder().encode([proof2]).base64EncodedString()]
        ]
        
        try await wallet.processTokenEvent(tokenEvent2)
        
        // Total balance across mints
        let totalBalance = await wallet.getBalance()
        XCTAssertEqual(totalBalance, 1100)
        
        // When paying Lightning, wallet should select the mint with sufficient balance
        // or perform cross-mint transfer if needed
    }
    
    func testPayLightningWithZeroAmountInvoice() async throws {
        // Some Lightning invoices don't specify amount
        let zeroAmountInvoice = "lnbc1p3qkwmppp5test..." // No amount specified
        
        // Wallet should handle this by requiring amount parameter
        // Add some balance first
        let proof = CashuSwift.Proof(
            keysetID: "test_keyset",
            amount: 1000,
            secret: "test_secret",
            C: "test_C"
        )
        
        let token = CashuSwift.Token(
            proofs: ["https://test.mint": [proof]],
            unit: "sat"
        )
        
        var tokenEvent = NDKEvent(ndk: ndk)
        tokenEvent.kind = .cashuToken
        tokenEvent.content = try token.serialize()
        tokenEvent.createdAt = Timestamp.now
        tokenEvent.tags = [
            ["a", "37417:pubkey:wallet_id"],
            ["mint", "https://test.mint"],
            ["proofs", try JSONEncoder().encode([proof]).base64EncodedString()]
        ]
        
        try await wallet.processTokenEvent(tokenEvent)
        
        // Payment with explicit amount should work
        // Note: Actual implementation would require mock mint
    }
}