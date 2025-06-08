import XCTest
@testable import NDKSwift

final class UnifiedErrorsTests: XCTestCase {
    
    func testErrorCategories() {
        // Test validation error
        let validationError = NDKUnifiedError.validation(.invalidPublicKey, context: ["key": "test123"])
        XCTAssertEqual(validationError.category, .validation)
        XCTAssertEqual(validationError.errorCode, "validation.invalid_public_key")
        XCTAssertEqual(validationError.context["key"] as? String, "test123")
        
        // Test crypto error
        let cryptoError = NDKUnifiedError.crypto(.signingFailed, context: ["algorithm": "schnorr"])
        XCTAssertEqual(cryptoError.category, .crypto)
        XCTAssertEqual(cryptoError.errorCode, "crypto.signing_failed")
        
        // Test network error with underlying
        let nsError = NSError(domain: NSURLErrorDomain, code: -1001, userInfo: nil)
        let networkError = NDKUnifiedError.network(.timeout, underlying: nsError)
        XCTAssertEqual(networkError.category, .network)
        XCTAssertNotNil(networkError.underlyingError)
    }
    
    func testErrorDescriptions() {
        // Test basic error
        let error1 = NDKUnifiedError.validation(.invalidSignature)
        XCTAssertEqual(error1.errorDescription, "Invalid signature")
        
        // Test error with context
        let error2 = NDKUnifiedError.network(
            .connectionFailed,
            context: ["relay": "wss://relay.test", "attempt": 3]
        )
        XCTAssertTrue(error2.errorDescription?.contains("relay: wss://relay.test") ?? false)
        XCTAssertTrue(error2.errorDescription?.contains("attempt: 3") ?? false)
        
        // Test error with underlying
        let underlying = NSError(domain: "TestDomain", code: 42, userInfo: [NSLocalizedDescriptionKey: "Test error"])
        let error3 = NDKUnifiedError.storage(.cacheFailed, underlying: underlying)
        XCTAssertTrue(error3.errorDescription?.contains("Test error") ?? false)
    }
    
    func testLegacyErrorConversion() {
        // Test NDKError conversion
        let legacyError1 = NDKError.invalidPublicKey
        let unified1 = legacyError1.unified
        XCTAssertEqual(unified1.category, .validation)
        XCTAssertEqual(unified1.specific.code, "invalid_public_key")
        
        // Test NDKError with message
        let legacyError2 = NDKError.relayConnectionFailed("Connection refused")
        let unified2 = legacyError2.unified
        XCTAssertEqual(unified2.category, .network)
        XCTAssertEqual(unified2.context["message"] as? String, "Connection refused")
        
        // Test timeout
        let legacyError3 = NDKError.timeout
        let unified3 = legacyError3.unified
        XCTAssertEqual(unified3.category, .network)
        XCTAssertEqual(unified3.specific.code, "timeout")
    }
    
    func testErrorMigration() {
        // Test Bech32Error migration
        let bech32Error = Bech32.Bech32Error.invalidChecksum
        let unified1 = ErrorMigration.unify(bech32Error)
        XCTAssertEqual(unified1.category, .validation)
        XCTAssertEqual(unified1.context["encoding"] as? String, "bech32")
        
        // Test CryptoError migration
        let cryptoError = Crypto.CryptoError.signingFailed
        let unified2 = ErrorMigration.unify(cryptoError)
        XCTAssertEqual(unified2.category, .crypto)
        XCTAssertEqual(unified2.specific.code, "signing_failed")
        
        // Test NSError migration
        let nsError = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        let unified3 = ErrorMigration.unify(nsError)
        XCTAssertEqual(unified3.category, .network)
        XCTAssertEqual(unified3.specific.code, "timeout")
        
        // Test unknown error
        let unknownError = NSError(domain: "Unknown", code: 999)
        let unified4 = ErrorMigration.unify(unknownError)
        XCTAssertEqual(unified4.category, .runtime)
        XCTAssertEqual(unified4.specific.code, "unknown")
    }
    
    func testRecoverableErrors() {
        var recoveryExecuted = false
        
        let error = NDKUnifiedError.network(.connectionFailed)
        let recoverable = error.withRecovery([
            ErrorRecovery(action: "Retry connection") {
                recoveryExecuted = true
            },
            ErrorRecovery(action: "Use different relay") {
                // Different recovery action
            }
        ])
        
        XCTAssertEqual(recoverable.recoverySuggestions.count, 2)
        XCTAssertTrue(recoverable.errorDescription?.contains("Recovery options:") ?? false)
        XCTAssertTrue(recoverable.errorDescription?.contains("1. Retry connection") ?? false)
        XCTAssertTrue(recoverable.errorDescription?.contains("2. Use different relay") ?? false)
        
        // Test recovery execution
        Task {
            try await recoverable.recoverySuggestions[0].handler()
            XCTAssertTrue(recoveryExecuted)
        }
    }
    
    func testErrorContext() {
        // Test adding context
        let error = NDKUnifiedError.validation(.invalidInput)
        let errorWithContext = error
            .withContext("field", "email")
            .withContext("value", "invalid@")
        
        XCTAssertEqual(errorWithContext.context["field"] as? String, "email")
        XCTAssertEqual(errorWithContext.context["value"] as? String, "invalid@")
        
        // Test context provider
        struct TestProvider: ErrorContextProvider {
            var errorContext: [String: Any] {
                ["source": "test", "timestamp": Date()]
            }
        }
        
        let provider = TestProvider()
        let errorWithProviderContext = error.withContext(from: provider)
        XCTAssertEqual(errorWithProviderContext.context["source"] as? String, "test")
        XCTAssertNotNil(errorWithProviderContext.context["timestamp"])
    }
    
    func testNDKResult() async {
        // Test success case
        let success: NDKResult<Int> = .success(42)
        let mapped = await success.asyncMap { value in
            value * 2
        }
        
        switch mapped {
        case let .success(value):
            XCTAssertEqual(value, 84)
        case .failure:
            XCTFail("Should not fail")
        }
        
        // Test failure case
        let failure: NDKResult<Int> = .failure(.validation(.invalidInput))
        let mappedFailure = await failure.asyncMap { value in
            value * 2
        }
        
        switch mappedFailure {
        case .success:
            XCTFail("Should not succeed")
        case let .failure(error):
            XCTAssertEqual(error.category, .validation)
        }
        
        // Test recovery
        let recoverableFailure: NDKResult<String> = .failure(.network(.timeout))
        let recovered = await recoverableFailure.recover(from: .network) {
            "Recovered value"
        }
        
        switch recovered {
        case let .success(value):
            XCTAssertEqual(value, "Recovered value")
        case .failure:
            XCTFail("Should have recovered")
        }
    }
    
    func testThrowUnified() {
        // Test throwing unified error
        XCTAssertThrowsError(try NDKUnifiedError.throwUnified {
            throw NDKError.invalidPublicKey
        }) { error in
            guard let unified = error as? NDKUnifiedError else {
                XCTFail("Should be unified error")
                return
            }
            XCTAssertEqual(unified.category, .validation)
        }
        
        // Test async throwing
        let expectation = expectation(description: "Async throw")
        
        Task {
            do {
                _ = try await NDKUnifiedError.throwUnifiedAsync {
                    throw Crypto.CryptoError.signingFailed
                }
                XCTFail("Should have thrown")
            } catch let error as NDKUnifiedError {
                XCTAssertEqual(error.category, .crypto)
                expectation.fulfill()
            } catch {
                XCTFail("Wrong error type")
            }
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testSpecificErrorCodes() {
        // Ensure all error codes are unique
        var seenCodes = Set<String>()
        
        let allErrors: [NDKUnifiedError.SpecificError] = [
            .invalidPublicKey, .invalidPrivateKey, .invalidEventID,
            .invalidSignature, .invalidInput, .invalidFilter,
            .signingFailed, .verificationFailed, .encryptionFailed,
            .decryptionFailed, .keyDerivationFailed,
            .connectionFailed, .connectionLost, .timeout,
            .serverError, .unauthorized,
            .cacheFailed, .diskFull, .fileNotFound, .corruptedData,
            .invalidMessage, .unsupportedVersion, .subscriptionFailed,
            .notConfigured, .invalidConfiguration,
            .notImplemented, .cancelled, .unknown
        ]
        
        for error in allErrors {
            XCTAssertFalse(seenCodes.contains(error.code), "Duplicate error code: \(error.code)")
            seenCodes.insert(error.code)
        }
    }
}