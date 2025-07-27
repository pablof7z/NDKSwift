import XCTest
@testable import NDKSwift

final class NIP60WalletTests: XCTestCase {
    
    // MARK: - Initialization Tests
    
    func testInitializationRequiresSigner() async throws {
        let ndkWithoutSigner = NDK()
        
        do {
            _ = try NIP60Wallet(ndk: ndkWithoutSigner)
            XCTFail("Should throw error when NDK has no signer")
        } catch NDKError.notConfigured(let message) {
            XCTAssertTrue(message.contains("signer"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testWalletPropertiesInitialize() async throws {
        let signer = try NDKPrivateKeySigner.generate()
        let ndk = NDK(signer: signer)
        let wallet = try NIP60Wallet(ndk: ndk)
        
        XCTAssertEqual(wallet.id, "nip60")
        XCTAssertEqual(wallet.displayName, "Cashu Wallet")
        XCTAssertNotNil(wallet.p2pkManager)
        XCTAssertNotNil(wallet.eventManager)
        XCTAssertNotNil(wallet.healthMonitor)
        XCTAssertNotNil(wallet.mints)
        XCTAssertNotNil(wallet.transactionHistory)
    }
    
    // MARK: - P2PK Manager Tests
    
    func testP2PKManagerGeneratesValidKeys() async throws {
        let signer = try NDKPrivateKeySigner.generate()
        let ndk = NDK(signer: signer)
        let wallet = try NIP60Wallet(ndk: ndk)
        
        let publicKey = await wallet.p2pkManager.getCurrentPublicKey()
        XCTAssertFalse(publicKey.isEmpty)
        XCTAssertEqual(publicKey.count, 64) // 32 bytes hex encoded
        
        // Verify it's a valid hex string
        XCTAssertTrue(HexValidator.isValidHexPubkey(publicKey))
    }
    
    func testP2PKManagerConsistency() async throws {
        let signer = try NDKPrivateKeySigner.generate()
        let ndk = NDK(signer: signer)
        let wallet = try NIP60Wallet(ndk: ndk)
        
        let key1 = await wallet.p2pkManager.getCurrentPublicKey()
        let key2 = await wallet.p2pkManager.getCurrentPublicKey()
        
        // Should return the same key if not rotated
        XCTAssertEqual(key1, key2)
    }
    
    // MARK: - Mint Manager Tests
    
    func testMintManagerStartsEmpty() async throws {
        let signer = try NDKPrivateKeySigner.generate()
        let ndk = NDK(signer: signer)
        let wallet = try NIP60Wallet(ndk: ndk)
        
        let mintUrls = await wallet.mints.getMintUrls()
        XCTAssertTrue(mintUrls.isEmpty)
    }
    
    func testMintManagerAddsValidMint() async throws {
        let signer = try NDKPrivateKeySigner.generate()
        let ndk = NDK(signer: signer)
        let wallet = try NIP60Wallet(ndk: ndk)
        
        let mintUrl = "https://mint.example.com"
        let mintInfo = NDKMintInfo(
            mintUrl: mintUrl,
            pubkey: signer.publicKey,
            relays: ["wss://relay.example.com"]
        )
        
        await wallet.mints.addMint(mintInfo)
        
        let mintUrls = await wallet.mints.getMintUrls()
        XCTAssertEqual(mintUrls.count, 1)
        XCTAssertTrue(mintUrls.contains(mintUrl))
    }
    
    // MARK: - Health Monitor Tests
    
    func testHealthMonitorTracksRelayStatus() async throws {
        let signer = try NDKPrivateKeySigner.generate()
        let ndk = NDK(signer: signer)
        let wallet = try NIP60Wallet(ndk: ndk)
        
        let relayUrl = "wss://relay.example.com"
        await wallet.healthMonitor.updateRelayStatus(relayUrl, isHealthy: true)
        
        let status = await wallet.healthMonitor.getRelayStatus(relayUrl)
        XCTAssertTrue(status)
    }
    
    // MARK: - Transaction History Tests
    
    func testTransactionHistoryStartsEmpty() async throws {
        let signer = try NDKPrivateKeySigner.generate()
        let ndk = NDK(signer: signer)
        let wallet = try NIP60Wallet(ndk: ndk)
        
        let transactions = await wallet.transactionHistory.getRecentTransactions(limit: 10)
        XCTAssertTrue(transactions.isEmpty)
    }
    
    // MARK: - Balance Tests
    
    func testBalanceReturnsZeroForUnknownUnit() async throws {
        let signer = try NDKPrivateKeySigner.generate()
        let ndk = NDK(signer: signer)
        let wallet = try NIP60Wallet(ndk: ndk)
        
        let balance = await wallet.balance(for: "unknown_unit")
        XCTAssertEqual(balance, 0)
    }
    
    func testBalanceReturnsZeroInitially() async throws {
        let signer = try NDKPrivateKeySigner.generate()
        let ndk = NDK(signer: signer)
        let wallet = try NIP60Wallet(ndk: ndk)
        
        let balance = await wallet.balance(for: "sat")
        XCTAssertEqual(balance, 0)
    }
    
    // MARK: - Relay Configuration Tests
    
    func testWalletConfigRelaysStartEmpty() async throws {
        let signer = try NDKPrivateKeySigner.generate()
        let ndk = NDK(signer: signer)
        let wallet = try NIP60Wallet(ndk: ndk)
        
        let relays = await wallet.walletConfigRelays
        XCTAssertTrue(relays.isEmpty)
    }
    
    func testWalletRelaysStartEmpty() async throws {
        let signer = try NDKPrivateKeySigner.generate()
        let ndk = NDK(signer: signer)
        let wallet = try NIP60Wallet(ndk: ndk)
        
        let relays = await wallet.walletRelays
        XCTAssertTrue(relays.isEmpty)
    }
}