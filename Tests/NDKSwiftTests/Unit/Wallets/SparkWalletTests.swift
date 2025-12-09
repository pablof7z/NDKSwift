import XCTest
@testable import NDKSwift

// Note: These tests verify SparkWallet's structure and error handling.
// Full integration tests require macOS/iOS where the Breez SDK binary is available.

final class SparkWalletTests: XCTestCase {

    // MARK: - Initialization Tests

    func testSparkWalletInitialization() async {
        let wallet = SparkWallet(apiKey: "test-api-key")

        XCTAssertEqual(wallet.id, "spark_wallet")
        XCTAssertEqual(wallet.displayName, "Spark Wallet")
    }

    func testSparkWalletInitializationWithCustomPath() async {
        let customPath = "/tmp/test_spark_wallet"
        let wallet = SparkWallet(apiKey: "test-api-key", storagePath: customPath)

        XCTAssertEqual(wallet.id, "spark_wallet")
        XCTAssertEqual(wallet.displayName, "Spark Wallet")
    }

    // MARK: - Availability Tests

    func testIsAvailableReturnsFalseWhenNotConnected() async {
        let wallet = SparkWallet(apiKey: "test-api-key")

        let isAvailable = await wallet.isAvailable()

        XCTAssertFalse(isAvailable, "Wallet should not be available when not connected")
    }

    // MARK: - canFulfill Tests

    func testCanFulfillReturnsFalseWhenNotConnected() async {
        let wallet = SparkWallet(apiKey: "test-api-key")
        let request = LightningInvoiceRequest(
            invoice: "lnbc100n1test",
            amountSats: 100,
            recipient: "test@example.com"
        )

        let canFulfill = await wallet.canFulfill(request)

        XCTAssertFalse(canFulfill, "Should not be able to fulfill when not connected")
    }

    // MARK: - fulfill Tests

    func testFulfillThrowsProviderNotAvailableError() async {
        let wallet = SparkWallet(apiKey: "test-api-key")
        let request = LightningInvoiceRequest(
            invoice: "lnbc100n1test",
            amountSats: 100,
            recipient: "test@example.com"
        )

        do {
            _ = try await wallet.fulfill(request)
            XCTFail("Should throw error when not connected")
        } catch let error as PaymentError {
            if case .providerNotAvailable = error {
                XCTAssertEqual(error.errorDescription, "Payment provider is not available")
            } else {
                XCTFail("Expected providerNotAvailable error, got \(error)")
            }
        } catch {
            XCTFail("Should throw PaymentError, got \(error)")
        }
    }

    func testSparkWalletErrorTypesExist() {
        // Verify error types exist with correct descriptions
        XCTAssertEqual(SparkWalletError.unsupportedPaymentType.errorDescription, "Unsupported payment type for Spark wallet")
        XCTAssertEqual(SparkWalletError.notConnected.errorDescription, "Spark wallet is not connected")
    }

    // MARK: - getBalance Tests

    func testGetBalanceReturnsNilWhenNotConnected() async throws {
        let wallet = SparkWallet(apiKey: "test-api-key")

        let balance = try await wallet.getBalance()

        XCTAssertNil(balance, "Balance should be nil when not connected")
    }

    // MARK: - Invoice Creation Tests

    func testCreateInvoiceThrowsNotConnectedError() async {
        let wallet = SparkWallet(apiKey: "test-api-key")

        do {
            _ = try await wallet.createInvoice(amountSats: 1000, description: "Test")
            XCTFail("Should throw error when not connected")
        } catch let error as SparkWalletError {
            XCTAssertEqual(error, .notConnected)
        } catch {
            XCTFail("Should throw SparkWalletError, got \(error)")
        }
    }

    // MARK: - Lightning Address Tests

    func testGetLightningAddressThrowsNotConnectedError() async {
        let wallet = SparkWallet(apiKey: "test-api-key")

        do {
            _ = try await wallet.getLightningAddress()
            XCTFail("Should throw error when not connected")
        } catch let error as SparkWalletError {
            XCTAssertEqual(error, .notConnected)
        } catch {
            XCTFail("Should throw SparkWalletError, got \(error)")
        }
    }

    func testRegisterLightningAddressThrowsNotConnectedError() async {
        let wallet = SparkWallet(apiKey: "test-api-key")

        do {
            try await wallet.registerLightningAddress("test@spark.io")
            XCTFail("Should throw error when not connected")
        } catch let error as SparkWalletError {
            XCTAssertEqual(error, .notConnected)
        } catch {
            XCTFail("Should throw SparkWalletError, got \(error)")
        }
    }

    // MARK: - Wallet Info Tests

    func testGetInfoThrowsNotConnectedError() async {
        let wallet = SparkWallet(apiKey: "test-api-key")

        do {
            _ = try await wallet.getInfo()
            XCTFail("Should throw error when not connected")
        } catch let error as SparkWalletError {
            XCTAssertEqual(error, .notConnected)
        } catch {
            XCTFail("Should throw SparkWalletError, got \(error)")
        }
    }

    func testSyncThrowsNotConnectedError() async {
        let wallet = SparkWallet(apiKey: "test-api-key")

        do {
            try await wallet.sync()
            XCTFail("Should throw error when not connected")
        } catch let error as SparkWalletError {
            XCTAssertEqual(error, .notConnected)
        } catch {
            XCTFail("Should throw SparkWalletError, got \(error)")
        }
    }

    // MARK: - Error Tests

    func testSparkWalletErrorDescriptions() {
        let errors: [(SparkWalletError, String)] = [
            (.notConnected, "Spark wallet is not connected"),
            (.alreadyConnected, "Spark wallet is already connected"),
            (.unsupportedPaymentType, "Unsupported payment type for Spark wallet"),
            (.invalidMnemonic, "Invalid mnemonic phrase"),
            (.connectionFailed("Network error"), "Failed to connect to Spark network: Network error")
        ]

        for (error, expectedDescription) in errors {
            XCTAssertEqual(error.errorDescription, expectedDescription)
        }
    }

    func testSparkWalletErrorEquality() {
        XCTAssertEqual(SparkWalletError.notConnected, SparkWalletError.notConnected)
        XCTAssertEqual(SparkWalletError.alreadyConnected, SparkWalletError.alreadyConnected)
        XCTAssertEqual(SparkWalletError.unsupportedPaymentType, SparkWalletError.unsupportedPaymentType)
        XCTAssertEqual(SparkWalletError.invalidMnemonic, SparkWalletError.invalidMnemonic)

        // Connection failed with same reason should be equal
        XCTAssertEqual(
            SparkWalletError.connectionFailed("reason"),
            SparkWalletError.connectionFailed("reason")
        )

        // Connection failed with different reasons should not be equal
        XCTAssertNotEqual(
            SparkWalletError.connectionFailed("reason1"),
            SparkWalletError.connectionFailed("reason2")
        )
    }

    // MARK: - SparkWalletInfo Tests

    func testSparkWalletInfoInitialization() {
        let info = SparkWalletInfo(
            balanceSats: 50000,
            pendingReceiveSats: 1000,
            pendingSendSats: 500,
            sparkAddress: "sp1qtest123"
        )

        XCTAssertEqual(info.balanceSats, 50000)
        XCTAssertEqual(info.pendingReceiveSats, 1000)
        XCTAssertEqual(info.pendingSendSats, 500)
        XCTAssertEqual(info.sparkAddress, "sp1qtest123")
    }

    func testSparkWalletInfoWithNilAddress() {
        let info = SparkWalletInfo(
            balanceSats: 25000,
            pendingReceiveSats: 0,
            pendingSendSats: 0,
            sparkAddress: nil
        )

        XCTAssertEqual(info.balanceSats, 25000)
        XCTAssertNil(info.sparkAddress)
    }

    // MARK: - SparkWalletEvent Tests

    func testSparkWalletEventTypes() {
        // Test that all event types exist and can be created
        let events: [SparkWalletEvent] = [
            .connected,
            .disconnected,
            .synced,
            .paymentSucceeded(amountSats: 1000),
            .paymentFailed(reason: "Insufficient funds"),
            .paymentPending(amountSats: 500)
        ]

        XCTAssertEqual(events.count, 6)

        // Verify payment events carry correct data
        if case .paymentSucceeded(let amount) = events[3] {
            XCTAssertEqual(amount, 1000)
        } else {
            XCTFail("Expected paymentSucceeded event")
        }

        if case .paymentFailed(let reason) = events[4] {
            XCTAssertEqual(reason, "Insufficient funds")
        } else {
            XCTFail("Expected paymentFailed event")
        }

        if case .paymentPending(let amount) = events[5] {
            XCTAssertEqual(amount, 500)
        } else {
            XCTFail("Expected paymentPending event")
        }
    }

    // MARK: - Protocol Conformance Tests

    func testSparkWalletConformsToNDKPaymentProvider() {
        // Verify SparkWallet can be used as NDKPaymentProvider
        let wallet = SparkWallet(apiKey: "test-api-key")
        let provider: NDKPaymentProvider = wallet

        XCTAssertEqual(provider.id, "spark_wallet")
        XCTAssertEqual(provider.displayName, "Spark Wallet")
    }

    // MARK: - Event Stream Tests

    func testEventStreamIsAvailable() async {
        let wallet = SparkWallet(apiKey: "test-api-key")

        // Verify the events property exists and is accessible
        let _ = wallet.events

        // This just verifies the stream is created properly
        // Actual event testing would require connecting to a real wallet
    }
}

// MARK: - SparkWalletError Equatable Conformance

extension SparkWalletError: Equatable {
    public static func == (lhs: SparkWalletError, rhs: SparkWalletError) -> Bool {
        switch (lhs, rhs) {
        case (.notConnected, .notConnected):
            return true
        case (.alreadyConnected, .alreadyConnected):
            return true
        case (.unsupportedPaymentType, .unsupportedPaymentType):
            return true
        case (.invalidMnemonic, .invalidMnemonic):
            return true
        case (.connectionFailed(let lhsReason), .connectionFailed(let rhsReason)):
            return lhsReason == rhsReason
        default:
            return false
        }
    }
}
