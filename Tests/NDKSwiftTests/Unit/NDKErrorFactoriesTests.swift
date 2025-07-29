import XCTest
@testable import NDKSwift

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
        
        if case .connectionFailed(let relay, let message, let underlying) = error {
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
        if case .encryptionFailed(let message, let underlying) = encryptError {
            XCTAssertEqual(message, "Encryption failed (NIP-04)")
            XCTAssertNotNil(underlying)
        } else {
            XCTFail("Expected encryptionFailed error")
        }
        
        // Test decryption
        let decryptError = NDKError.cryptoOperation("Decryption", nip: nil, error: underlyingError)
        if case .decryptionFailed(let message, let underlying) = decryptError {
            XCTAssertEqual(message, "Decryption failed")
            XCTAssertNotNil(underlying)
        } else {
            XCTFail("Expected decryptionFailed error")
        }
        
        // Test signing
        let signError = NDKError.cryptoOperation("Signing", nip: nil, error: underlyingError)
        if case .signingFailed(let message, let underlying) = signError {
            XCTAssertEqual(message, "Signing failed")
            XCTAssertNotNil(underlying)
        } else {
            XCTFail("Expected signingFailed error")
        }
        
        // Test verification
        let verifyError = NDKError.cryptoOperation("Verification", nip: nil, error: underlyingError)
        if case .verificationFailed(let message, let underlying) = verifyError {
            XCTAssertEqual(message, "Verification failed")
            XCTAssertNotNil(underlying)
        } else {
            XCTFail("Expected verificationFailed error")
        }
        
        // Test key derivation
        let keyError = NDKError.cryptoOperation("Key derivation", nip: nil, error: underlyingError)
        if case .keyDerivationFailed(let message, let underlying) = keyError {
            XCTAssertEqual(message, "Key derivation failed")
            XCTAssertNotNil(underlying)
        } else {
            XCTFail("Expected keyDerivationFailed error")
        }
        
        // Test unknown operation
        let unknownError = NDKError.cryptoOperation("Unknown", nip: nil, error: underlyingError)
        if case .unknown(let message, let underlying) = unknownError {
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
    
    // MARK: - Wallet Error Factory Tests
    
    func testWalletInsufficientBalance() {
        let errorWithAvailable = NDKError.walletInsufficientBalance(amount: 100, available: 50)
        XCTAssertEqual(errorWithAvailable.localizedDescription, "Wallet error: Insufficient balance: requested 100 sats, available: 50 sats")
        
        let errorWithoutAvailable = NDKError.walletInsufficientBalance(amount: 100)
        if case .insufficientBalance(let amount) = errorWithoutAvailable {
            XCTAssertEqual(amount, 100)
        } else {
            XCTFail("Expected insufficientBalance error")
        }
    }
    
    func testWalletMintError() {
        let error = NDKError.walletMintError("https://mint.test", operation: "swap", details: "timeout")
        XCTAssertEqual(error.localizedDescription, "Wallet error: Mint https://mint.test swap failed: timeout")
        
        let errorWithoutDetails = NDKError.walletMintError("https://mint.test", operation: "connect")
        XCTAssertEqual(errorWithoutDetails.localizedDescription, "Wallet error: Mint https://mint.test connect failed")
    }
    
    func testWalletPaymentFailed() {
        let errorWithInvoice = NDKError.walletPaymentFailed(reason: "route not found", invoice: "lnbc123...")
        XCTAssertEqual(errorWithInvoice.localizedDescription, "Payment failed: Payment failed for invoice lnbc123...: route not found")
        
        let errorWithoutInvoice = NDKError.walletPaymentFailed(reason: "insufficient funds")
        XCTAssertEqual(errorWithoutInvoice.localizedDescription, "Payment failed: Payment failed: insufficient funds")
    }
    
    func testWalletInvalidProof() {
        let errorWithDetails = NDKError.walletInvalidProof(details: "signature mismatch")
        XCTAssertEqual(errorWithDetails.localizedDescription, "Invalid proof: signature mismatch")
        
        let errorWithoutDetails = NDKError.walletInvalidProof()
        XCTAssertEqual(errorWithoutDetails.localizedDescription, "Invalid proof")
    }
    
    func testWalletNoMintAvailable() {
        let errorWithReason = NDKError.walletNoMintAvailable(reason: "all mints offline")
        XCTAssertEqual(errorWithReason.localizedDescription, "No mint available: all mints offline")
        
        let errorWithoutReason = NDKError.walletNoMintAvailable()
        XCTAssertEqual(errorWithoutReason.localizedDescription, "No mint available")
    }
}