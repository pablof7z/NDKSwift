@testable import NDKSwiftCore
import XCTest

final class NDKErrorFactoriesTests: XCTestCase {
    func testFailedToFactory() {
        let error = NDKError.failedTo("connect", message: "server unavailable")
        XCTAssertEqual(error.localizedDescription, "Failed to connect: server unavailable")

        let errorWithoutMessage = NDKError.failedTo("parse")
        XCTAssertEqual(errorWithoutMessage.localizedDescription, "Failed to parse")
    }

    func testInvalidDataFormatFactory() {
        let error = NDKError.invalidDataFormat("JSON", details: "missing field")
        XCTAssertEqual(error.localizedDescription, "Invalid JSON: missing field")

        let errorWithoutDetails = NDKError.invalidDataFormat("event")
        XCTAssertEqual(errorWithoutDetails.localizedDescription, "Invalid event")
    }

    func testMissingRequiredFactory() {
        let error = NDKError.missingRequired("signature", in: "event")
        XCTAssertEqual(error.localizedDescription, "Missing required signature in event")

        let errorWithoutContext = NDKError.missingRequired("pubkey")
        XCTAssertEqual(errorWithoutContext.localizedDescription, "Missing required pubkey")
    }

    func testNetworkErrorFactory() {
        let underlyingError = NSError(domain: "TestDomain", code: -1, userInfo: nil)
        let error = NDKError.networkError(for: "wss://relay.test", operation: "connect", error: underlyingError)

        if case let .connectionFailed(relay, message, underlying) = error {
            XCTAssertEqual(relay, "wss://relay.test")
            XCTAssertEqual(message, "Failed to connect")
            XCTAssertNotNil(underlying)
        } else {
            XCTFail("Expected connectionFailed error")
        }
    }

    func testParseErrorFactory() {
        let error = NDKError.parseError(for: "JSON", details: "unexpected character")
        XCTAssertEqual(error.localizedDescription, "Failed to parse JSON: unexpected character")

        let errorWithoutDetails = NDKError.parseError(for: "event")
        XCTAssertEqual(errorWithoutDetails.localizedDescription, "Failed to parse event")
    }

    func testCryptoOperationFactory() {
        let underlyingError = NSError(domain: "CryptoDomain", code: -1, userInfo: nil)

        // Test encryption
        let encryptError = NDKError.cryptoOperation("Encryption", nip: "NIP-04", error: underlyingError)
        if case let .encryptionFailed(message, underlying) = encryptError {
            XCTAssertEqual(message, "Encryption failed (NIP-04)")
            XCTAssertNotNil(underlying)
        } else {
            XCTFail("Expected encryptionFailed error")
        }

        // Test decryption
        let decryptError = NDKError.cryptoOperation("Decryption", nip: nil, error: underlyingError)
        if case let .decryptionFailed(message, underlying) = decryptError {
            XCTAssertEqual(message, "Decryption failed")
            XCTAssertNotNil(underlying)
        } else {
            XCTFail("Expected decryptionFailed error")
        }

        // Test signing
        let signError = NDKError.cryptoOperation("Signing", nip: nil, error: underlyingError)
        if case let .signingFailed(message, underlying) = signError {
            XCTAssertEqual(message, "Signing failed")
            XCTAssertNotNil(underlying)
        } else {
            XCTFail("Expected signingFailed error")
        }

        // Test verification
        let verifyError = NDKError.cryptoOperation("Verification", nip: nil, error: underlyingError)
        if case let .verificationFailed(message, underlying) = verifyError {
            XCTAssertEqual(message, "Verification failed")
            XCTAssertNotNil(underlying)
        } else {
            XCTFail("Expected verificationFailed error")
        }

        // Test key derivation
        let keyError = NDKError.cryptoOperation("Key derivation", nip: nil, error: underlyingError)
        if case let .keyDerivationFailed(message, underlying) = keyError {
            XCTAssertEqual(message, "Key derivation failed")
            XCTAssertNotNil(underlying)
        } else {
            XCTFail("Expected keyDerivationFailed error")
        }

        // Test unknown operation
        let unknownError = NDKError.cryptoOperation("Unknown", nip: nil, error: underlyingError)
        if case let .unknown(message, underlying) = unknownError {
            XCTAssertEqual(message, "Unknown failed")
            XCTAssertNotNil(underlying)
        } else {
            XCTFail("Expected unknown error")
        }
    }

    func testValidationError() {
        let error = NDKError.validationError("Invalid hex format")
        XCTAssertEqual(error.localizedDescription, "Invalid input: Invalid hex format")
    }

    func testConfigurationError() {
        let error = NDKError.configurationError("Missing API key")
        XCTAssertEqual(error.localizedDescription, "Not configured: Missing API key")
    }

    // MARK: - Wallet Error Tests

    func testWalletInsufficientBalance() {
        let error = NDKError.walletInsufficientBalance(amount: 100, available: 50)
        XCTAssertEqual(error.localizedDescription, "Insufficient balance: need 100 sats, have 50 sats")
    }

    func testWalletInvalidProof() {
        let error = NDKError.walletInvalidProof(details: "signature mismatch")
        XCTAssertEqual(error.localizedDescription, "Invalid proof: signature mismatch")
    }

    func testWalletError() {
        let error = NDKError.walletError(message: "Connection failed")
        XCTAssertEqual(error.localizedDescription, "Connection failed")
    }

    func testPaymentFailed() {
        let error = NDKError.paymentFailed(reason: "route not found")
        XCTAssertEqual(error.localizedDescription, "Payment failed: route not found")
    }

    func testNoMintAvailable() {
        let error = NDKError.noMintAvailable("all mints offline")
        XCTAssertEqual(error.localizedDescription, "No mint available: all mints offline")
    }
}
