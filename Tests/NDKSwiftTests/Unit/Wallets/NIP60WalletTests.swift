import NDKSwiftCashu
@testable import NDKSwiftCore
import XCTest

final class NIP60WalletTests: XCTestCase {
    // MARK: - Initialization Tests

    func testInitializationRequiresSigner() async throws {
        let ndkWithoutSigner = NDK()

        do {
            _ = try NIP60Wallet(ndk: ndkWithoutSigner)
            XCTFail("Should throw error when NDK has no signer")
        } catch let NDKError.notConfigured(message) {
            XCTAssertTrue(message.contains("signer"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testWalletPropertiesInitialize() async throws {
        let signer = try NDKPrivateKeySigner.generate()
        let ndk = NDK(signer: signer)
        let wallet = try NIP60Wallet(ndk: ndk)

        // Test actor-isolated properties by accessing them in async context
        let walletId = await wallet.id
        let displayName = await wallet.displayName

        XCTAssertEqual(walletId, "nip60")
        XCTAssertEqual(displayName, "Cashu Wallet")

        // Test that wallet was initialized properly by testing functionality
        let balance = try await wallet.getBalance()
        XCTAssertEqual(balance, 0)
    }

    // MARK: - P2PK Manager Tests

    func testP2PKManagerGeneratesValidKeys() async throws {
        let signer = try NDKPrivateKeySigner.generate()
        let ndk = NDK(signer: signer)
        let wallet = try NIP60Wallet(ndk: ndk)

        let publicKey = try await wallet.getP2PKPubkey()
        XCTAssertFalse(publicKey.isEmpty)
        XCTAssertEqual(publicKey.count, 132) // 66 bytes hex encoded (uncompressed public key)

        // Verify it's a valid hex string (66 bytes = 132 hex chars)
        XCTAssertTrue(HexValidator.isValidHex(publicKey, expectedByteCount: 66))
    }

    func testP2PKManagerConsistency() async throws {
        let signer = try NDKPrivateKeySigner.generate()
        let ndk = NDK(signer: signer)
        let wallet = try NIP60Wallet(ndk: ndk)

        let key1 = try await wallet.getP2PKPubkey()
        let key2 = try await wallet.getP2PKPubkey()

        // Should return the same key if not rotated
        XCTAssertEqual(key1, key2)
    }

    // MARK: - Mint Manager Tests

    func testMintManagerStartsEmpty() async throws {
        let signer = try NDKPrivateKeySigner.generate()
        let ndk = NDK(signer: signer)
        let wallet = try NIP60Wallet(ndk: ndk)

        // Test that wallet is not available initially (no mints configured)
        let isAvailable = await wallet.isAvailable()
        XCTAssertFalse(isAvailable)
    }

    func testWalletSetup() async throws {
        let signer = try NDKPrivateKeySigner.generate()
        let ndk = NDK(signer: signer)
        let wallet = try NIP60Wallet(ndk: ndk)

        let mintUrls = ["https://mint.example.com"]
        let relays = ["wss://relay.example.com"]

        // Test setup method completes without error
        try await wallet.setup(mints: mintUrls, relays: relays, publishMintList: false)

        // Setup is async and involves publishing events, so we just verify it doesn't throw
        XCTAssertTrue(true)
    }

    // MARK: - Health Monitor Tests

    func testHealthMonitorInitialState() async throws {
        let signer = try NDKPrivateKeySigner.generate()
        let ndk = NDK(signer: signer)
        let wallet = try NIP60Wallet(ndk: ndk)

        // Test that relay health starts empty
        let relayHealth = await wallet.getRelayHealth()
        XCTAssertTrue(relayHealth.isEmpty)
    }

    // MARK: - Transaction History Tests

    func testTransactionHistoryStartsEmpty() async throws {
        let signer = try NDKPrivateKeySigner.generate()
        let ndk = NDK(signer: signer)
        let wallet = try NIP60Wallet(ndk: ndk)

        let transactions = await wallet.getRecentTransactions(limit: 10)
        XCTAssertTrue(transactions.isEmpty)
    }

    // MARK: - Balance Tests

    func testInitialBalance() async throws {
        let signer = try NDKPrivateKeySigner.generate()
        let ndk = NDK(signer: signer)
        let wallet = try NIP60Wallet(ndk: ndk)

        let balance = try await wallet.getBalance()
        XCTAssertEqual(balance, 0)
    }

    func testBalancesByMint() async throws {
        let signer = try NDKPrivateKeySigner.generate()
        let ndk = NDK(signer: signer)
        let wallet = try NIP60Wallet(ndk: ndk)

        let balancesByMint = await wallet.getBalancesByMint()
        XCTAssertTrue(balancesByMint.isEmpty)
    }

    // MARK: - Relay Configuration Tests

    func testWalletHealthCheck() async throws {
        let signer = try NDKPrivateKeySigner.generate()
        let ndk = NDK(signer: signer)
        let wallet = try NIP60Wallet(ndk: ndk)

        // Test that wallet health check can be performed
        let healthStatus = try await wallet.checkWalletHealth()
        XCTAssertNotNil(healthStatus)
    }

    func testNutzapManagement() async throws {
        let signer = try NDKPrivateKeySigner.generate()
        let ndk = NDK(signer: signer)
        let wallet = try NIP60Wallet(ndk: ndk)

        // Test that nutzap methods can be called without errors
        let nutzaps = await wallet.getNutzaps()
        XCTAssertTrue(nutzaps.isEmpty)

        let pendingNutzaps = await wallet.getPendingNutzaps()
        XCTAssertTrue(pendingNutzaps.isEmpty)
    }
}
