import XCTest
import CashuSwift
@testable import NDKSwift

final class NDKCashuWalletTests: XCTestCase {
    var ndk: NDK!
    var wallet: NDKCashuWallet!
    var mockSigner: MockSigner!
    var mockRelay: MockRelay!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Setup mock signer
        mockSigner = MockSigner(privateKey: "test_private_key")
        
        // Setup mock relay
        mockRelay = MockRelay(url: URL(string: "wss://test.relay")!)
        
        // Setup NDK with mock relay
        ndk = NDK(relayUrls: ["wss://test.relay"], signer: mockSigner)
        
        // Create wallet
        wallet = NDKCashuWallet(ndk: ndk)
    }
    
    override func tearDown() async throws {
        wallet = nil
        ndk = nil
        mockSigner = nil
        mockRelay = nil
        try await super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testWalletInitialization() async throws {
        XCTAssertNotNil(wallet)
        XCTAssertEqual(await wallet.getBalance(), 0)
        XCTAssertNotNil(wallet.mintDiscovery)
    }
    
    // MARK: - Token Processing Tests
    
    func testProcessTokenWithValidProofs() async throws {
        // Create mock proofs
        let proof1 = CashuSwift.Proof(
            keysetID: "test_keyset_1",
            amount: 100,
            secret: "test_secret_1",
            C: "test_C_1"
        )
        let proof2 = CashuSwift.Proof(
            keysetID: "test_keyset_1",
            amount: 200,
            secret: "test_secret_2",
            C: "test_C_2"
        )
        
        // Create token
        let token = CashuSwift.Token(
            proofs: ["https://test.mint": [proof1, proof2]],
            unit: "sat"
        )
        
        // Create NIP-60 token event
        var tokenEvent = NDKEvent(ndk: ndk)
        tokenEvent.kind = .cashuToken
        tokenEvent.content = try token.serialize()
        tokenEvent.createdAt = Timestamp.now
        tokenEvent.tags = [
            ["a", "37417:pubkey:wallet_id"],
            ["mint", "https://test.mint"],
            ["proofs", try JSONEncoder().encode([proof1, proof2]).base64EncodedString()]
        ]
        
        // Process the token event
        try await wallet.processTokenEvent(tokenEvent)
        
        // Verify balance
        let balance = await wallet.getBalance()
        XCTAssertEqual(balance, 300)
        
        // Verify mint was added
        let mintBalance = await wallet.getBalance(mint: URL(string: "https://test.mint")!)
        XCTAssertEqual(mintBalance, 300)
    }
    
    func testProcessTokenWithDeletedProofs() async throws {
        // First, add some proofs
        let proof1 = CashuSwift.Proof(
            keysetID: "test_keyset_1",
            amount: 100,
            secret: "test_secret_1",
            C: "test_C_1"
        )
        
        let token = CashuSwift.Token(
            proofs: ["https://test.mint": [proof1]],
            unit: "sat"
        )
        
        var tokenEvent = NDKEvent(ndk: ndk)
        tokenEvent.id = "token_event_1"
        tokenEvent.kind = .cashuToken
        tokenEvent.content = try token.serialize()
        tokenEvent.createdAt = Timestamp.now
        tokenEvent.tags = [
            ["a", "37417:pubkey:wallet_id"],
            ["mint", "https://test.mint"],
            ["proofs", try JSONEncoder().encode([proof1]).base64EncodedString()]
        ]
        
        try await wallet.processTokenEvent(tokenEvent)
        
        // Now create a delete event
        var deleteEvent = NDKEvent(ndk: ndk)
        deleteEvent.kind = .cashuToken
        deleteEvent.content = ""
        deleteEvent.createdAt = Timestamp.now + 1
        deleteEvent.tags = [
            ["a", "37417:pubkey:wallet_id"],
            ["e", "token_event_1", "", "del"]
        ]
        
        try await wallet.processTokenEvent(deleteEvent)
        
        // Verify balance is now 0
        let balance = await wallet.getBalance()
        XCTAssertEqual(balance, 0)
    }
    
    // MARK: - Cross-Mint Transfer Tests
    
    func testCrossMintTransferSuccess() async throws {
        // This test would require mocking the mint interactions
        // For now, we'll test the logic flow
        
        // Add proofs to source mint
        let proof1 = CashuSwift.Proof(
            keysetID: "source_keyset",
            amount: 1000,
            secret: "source_secret",
            C: "source_C"
        )
        
        let token = CashuSwift.Token(
            proofs: ["https://source.mint": [proof1]],
            unit: "sat"
        )
        
        var tokenEvent = NDKEvent(ndk: ndk)
        tokenEvent.kind = .cashuToken
        tokenEvent.content = try token.serialize()
        tokenEvent.createdAt = Timestamp.now
        tokenEvent.tags = [
            ["a", "37417:pubkey:wallet_id"],
            ["mint", "https://source.mint"],
            ["proofs", try JSONEncoder().encode([proof1]).base64EncodedString()]
        ]
        
        try await wallet.processTokenEvent(tokenEvent)
        
        // Verify initial balance
        let initialBalance = await wallet.getBalance()
        XCTAssertEqual(initialBalance, 1000)
        
        // Note: Actual cross-mint transfer would require mock mint servers
        // This test verifies the wallet state management
    }
    
    // MARK: - Proof State Reconciliation Tests
    
    func testProofStateReconciliation() async throws {
        // Add some proofs
        let proof1 = CashuSwift.Proof(
            keysetID: "test_keyset",
            amount: 100,
            secret: "test_secret_1",
            C: "test_C_1"
        )
        let proof2 = CashuSwift.Proof(
            keysetID: "test_keyset",
            amount: 200,
            secret: "test_secret_2",
            C: "test_C_2"
        )
        
        let token = CashuSwift.Token(
            proofs: ["https://test.mint": [proof1, proof2]],
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
            ["proofs", try JSONEncoder().encode([proof1, proof2]).base64EncodedString()]
        ]
        
        try await wallet.processTokenEvent(tokenEvent)
        
        // Initial balance should be 300
        let initialBalance = await wallet.getBalance()
        XCTAssertEqual(initialBalance, 300)
        
        // Note: Testing actual proof state checking would require mock mint responses
        // This test verifies the wallet maintains proper state
    }
    
    // MARK: - Edge Case Tests
    
    func testProcessEmptyToken() async throws {
        let token = CashuSwift.Token(proofs: [:], unit: "sat")
        
        var tokenEvent = NDKEvent(ndk: ndk)
        tokenEvent.kind = .cashuToken
        tokenEvent.content = try token.serialize()
        tokenEvent.createdAt = Timestamp.now
        tokenEvent.tags = [
            ["a", "37417:pubkey:wallet_id"]
        ]
        
        try await wallet.processTokenEvent(tokenEvent)
        
        // Balance should remain 0
        let balance = await wallet.getBalance()
        XCTAssertEqual(balance, 0)
    }
    
    func testProcessDuplicateProofs() async throws {
        let proof = CashuSwift.Proof(
            keysetID: "test_keyset",
            amount: 100,
            secret: "test_secret",
            C: "test_C"
        )
        
        let token = CashuSwift.Token(
            proofs: ["https://test.mint": [proof]],
            unit: "sat"
        )
        
        // Process first token event
        var tokenEvent1 = NDKEvent(ndk: ndk)
        tokenEvent1.id = "event_1"
        tokenEvent1.kind = .cashuToken
        tokenEvent1.content = try token.serialize()
        tokenEvent1.createdAt = Timestamp.now
        tokenEvent1.tags = [
            ["a", "37417:pubkey:wallet_id"],
            ["mint", "https://test.mint"],
            ["proofs", try JSONEncoder().encode([proof]).base64EncodedString()]
        ]
        
        try await wallet.processTokenEvent(tokenEvent1)
        
        // Process second token event with same proof (different event ID)
        var tokenEvent2 = NDKEvent(ndk: ndk)
        tokenEvent2.id = "event_2"
        tokenEvent2.kind = .cashuToken
        tokenEvent2.content = try token.serialize()
        tokenEvent2.createdAt = Timestamp.now + 1
        tokenEvent2.tags = [
            ["a", "37417:pubkey:wallet_id"],
            ["mint", "https://test.mint"],
            ["proofs", try JSONEncoder().encode([proof]).base64EncodedString()]
        ]
        
        try await wallet.processTokenEvent(tokenEvent2)
        
        // Balance should only count the proof once
        let balance = await wallet.getBalance()
        XCTAssertEqual(balance, 100)
    }
    
    func testTokenChainWithSuperseding() async throws {
        // Create initial token
        let proof1 = CashuSwift.Proof(
            keysetID: "test_keyset",
            amount: 100,
            secret: "secret_1",
            C: "C_1"
        )
        
        let token1 = CashuSwift.Token(
            proofs: ["https://test.mint": [proof1]],
            unit: "sat"
        )
        
        var tokenEvent1 = NDKEvent(ndk: ndk)
        tokenEvent1.id = "token_1"
        tokenEvent1.kind = .cashuToken
        tokenEvent1.content = try token1.serialize()
        tokenEvent1.createdAt = Timestamp(100)
        tokenEvent1.tags = [
            ["a", "37417:pubkey:wallet_id"],
            ["mint", "https://test.mint"],
            ["proofs", try JSONEncoder().encode([proof1]).base64EncodedString()]
        ]
        
        try await wallet.processTokenEvent(tokenEvent1)
        
        // Create superseding token
        let proof2 = CashuSwift.Proof(
            keysetID: "test_keyset",
            amount: 50,
            secret: "secret_2",
            C: "C_2"
        )
        
        let token2 = CashuSwift.Token(
            proofs: ["https://test.mint": [proof2]],
            unit: "sat"
        )
        
        var tokenEvent2 = NDKEvent(ndk: ndk)
        tokenEvent2.id = "token_2"
        tokenEvent2.kind = .cashuToken
        tokenEvent2.content = try token2.serialize()
        tokenEvent2.createdAt = Timestamp(200)
        tokenEvent2.tags = [
            ["a", "37417:pubkey:wallet_id"],
            ["mint", "https://test.mint"],
            ["proofs", try JSONEncoder().encode([proof2]).base64EncodedString()],
            ["e", "token_1", "", "del"]  // Supersedes token_1
        ]
        
        try await wallet.processTokenEvent(tokenEvent2)
        
        // Balance should only include proof2 (50)
        let balance = await wallet.getBalance()
        XCTAssertEqual(balance, 50)
    }
    
    // MARK: - Payment Request Tests
    
    func testNutzapPaymentRequestValidation() async throws {
        // Test creating a valid nutzap request
        let mints = [URL(string: "https://test.mint")!]
        let request = NDKNutzapRequest(
            amount: 100,
            pubkey: "recipient_pubkey",
            mints: mints,
            unit: "sat",
            p2pk: "recipient_p2pk_pubkey"
        )
        
        XCTAssertEqual(request.amount, 100)
        XCTAssertEqual(request.pubkey, "recipient_pubkey")
        XCTAssertEqual(request.mints, mints)
        XCTAssertEqual(request.unit, "sat")
        XCTAssertEqual(request.p2pk, "recipient_p2pk_pubkey")
    }
    
    // MARK: - Balance Tests
    
    func testBalanceCalculationWithMultipleMints() async throws {
        // Add proofs to first mint
        let proof1 = CashuSwift.Proof(
            keysetID: "keyset_1",
            amount: 100,
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
        
        // Add proofs to second mint
        let proof2 = CashuSwift.Proof(
            keysetID: "keyset_2",
            amount: 200,
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
        
        // Test total balance
        let totalBalance = await wallet.getBalance()
        XCTAssertEqual(totalBalance, 300)
        
        // Test individual mint balances
        let mint1Balance = await wallet.getBalance(mint: URL(string: "https://mint1.com")!)
        XCTAssertEqual(mint1Balance, 100)
        
        let mint2Balance = await wallet.getBalance(mint: URL(string: "https://mint2.com")!)
        XCTAssertEqual(mint2Balance, 200)
        
        let nonExistentMintBalance = await wallet.getBalance(mint: URL(string: "https://mint3.com")!)
        XCTAssertEqual(nonExistentMintBalance, 0)
    }
}