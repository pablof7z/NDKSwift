import XCTest
import CashuSwift
@testable import NDKSwift

final class NDKCashuWalletTests: XCTestCase {
    var ndk: NDK!
    var wallet: NDKCashuWallet!
    var testWrapper: TestableWalletWrapper!
    var mockSigner: MockSigner!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Setup mock signer with a valid 32-byte hex private key
        mockSigner = MockSigner(privateKey: "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef")
        
        // Setup NDK
        ndk = NDK(relayUrls: ["wss://test.relay"], signer: mockSigner)
        
        // Create testable wallet wrapper
        testWrapper = TestableWalletWrapper(ndk: ndk)
        wallet = testWrapper.wallet
    }
    
    override func tearDown() async throws {
        wallet = nil
        testWrapper = nil
        ndk = nil
        mockSigner = nil
        try await super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testWalletInitialization() async throws {
        XCTAssertNotNil(wallet)
        let balance = try await wallet.getBalance()
        XCTAssertEqual(balance, 0)
    }
    
    // MARK: - Balance Tests
    
    func testGetBalanceEmpty() async throws {
        let balance = try await wallet.getBalance()
        XCTAssertEqual(balance, 0)
    }
    
    func testGetBalanceWithProofs() async throws {
        // Add test mint
        let mintURL = "https://test.mint"
        try await testWrapper.addTestMint(url: URL(string: mintURL)!)
        
        // Add test proofs
        let proofs = CashuTestHelpers.createProofs(amounts: [100, 200, 500])
        try await testWrapper.addTestProofs(proofs, mintURL: mintURL)
        
        // Check balance
        let balance = try await wallet.getBalance()
        XCTAssertEqual(balance, 800) // 100 + 200 + 500
        
        // Check per-mint balance
        let mintBalance = try await wallet.getBalance(mint: URL(string: mintURL)!)
        XCTAssertEqual(mintBalance, 800)
    }
    
    // MARK: - Mint Management Tests
    
    func testAddMint() async throws {
        let mintURL = URL(string: "https://example.mint")!
        
        // Add mint using test wrapper
        try await testWrapper.addTestMint(url: mintURL)
        
        // Verify mint was added
        let mint = await wallet.getMint(for: mintURL)
        XCTAssertNotNil(mint)
        XCTAssertEqual(mint?.url, mintURL)
    }
    
    func testRemoveMint() async throws {
        let mintURL = URL(string: "https://example.mint")!
        
        // Add mint
        try await testWrapper.addTestMint(url: mintURL)
        
        // Verify mint was added
        let mintBefore = await wallet.getMint(for: mintURL)
        XCTAssertNotNil(mintBefore)
        
        // Remove mint
        try await wallet.removeMint(url: mintURL)
        
        // Verify mint was removed
        let mintAfter = await wallet.getMint(for: mintURL)
        XCTAssertNil(mintAfter)
        
        // Note: Testing proof removal would require deeper integration
        // with the wallet's internal state management
    }
    
    // MARK: - Token Processing Tests
    
    func testReceiveProofs() async throws {
        let mintURL = "https://test.mint"
        try await testWrapper.addTestMint(url: URL(string: mintURL)!)
        
        // Create and receive proofs
        let proofs = CashuTestHelpers.createProofs(amounts: [64, 32, 16, 8])
        try await wallet.receive(proofs: proofs)
        
        // Verify balance
        let balance = try await wallet.getBalance()
        XCTAssertEqual(balance, 120) // 64 + 32 + 16 + 8
    }
    
    // MARK: - Send Tests
    
    func testSendWithSufficientBalance() async throws {
        let mintURL = URL(string: "https://test.mint")!
        try await testWrapper.addTestMint(url: mintURL)
        
        // Add proofs
        let proofs = CashuTestHelpers.createProofs(amounts: [100, 50, 25])
        try await testWrapper.addTestProofs(proofs, mintURL: mintURL.absoluteString)
        
        // Verify initial balance
        let initialBalance = try await wallet.getBalance()
        XCTAssertEqual(initialBalance, 175)
        
        // Note: Actual send operation would require mocking CashuSwift.swap
        // For now, we're testing the wallet state management
    }
    
    // MARK: - Error Handling Tests
    
    func testInsufficientBalanceError() async throws {
        let mintURL = URL(string: "https://test.mint")!
        try await testWrapper.addTestMint(url: mintURL)
        
        // Try to send without balance
        do {
            _ = try await wallet.send(amount: 1000, to: "recipientPubkey", mint: mintURL)
            XCTFail("Should have thrown insufficient balance error")
        } catch NDKError.insufficientBalance {
            // Expected error
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testNoMintError() async throws {
        // Try to send without any mints configured
        do {
            _ = try await wallet.send(amount: 100, to: "recipientPubkey", mint: URL(string: "https://unknown.mint")!)
            XCTFail("Should have thrown no mint available error")
        } catch NDKError.noMintAvailable {
            // Expected error
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    // MARK: - Multi-Mint Tests
    
    func testMultipleMints() async throws {
        let mint1URL = URL(string: "https://mint1.example")!
        let mint2URL = URL(string: "https://mint2.example")!
        
        // Add multiple mints
        try await testWrapper.addTestMint(url: mint1URL)
        try await testWrapper.addTestMint(url: mint2URL)
        
        // Add proofs to different mints
        let proofs1 = CashuTestHelpers.createProofs(
            amounts: [100, 50],
            mint: mint1URL.absoluteString
        )
        let proofs2 = CashuTestHelpers.createProofs(
            amounts: [200, 100],
            mint: mint2URL.absoluteString
        )
        
        try await testWrapper.addTestProofs(proofs1, mintURL: mint1URL.absoluteString)
        try await testWrapper.addTestProofs(proofs2, mintURL: mint2URL.absoluteString)
        
        // Check total balance
        let totalBalance = try await wallet.getBalance()
        XCTAssertEqual(totalBalance, 450) // 100 + 50 + 200 + 100
        
        // Check per-mint balances
        let mint1Balance = try await wallet.getBalance(mint: mint1URL)
        XCTAssertEqual(mint1Balance, 150)
        
        let mint2Balance = try await wallet.getBalance(mint: mint2URL)
        XCTAssertEqual(mint2Balance, 300)
    }
}