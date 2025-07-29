import XCTest
@testable import NDKSwift
import LocalAuthentication

final class NDKAuthErrorHandlerTests: XCTestCase {
    
    // MARK: - NDKAuthError Tests
    
    func testAnalyzeNoActiveSession() {
        let error = NDKAuthError.noActiveSession
        let errorInfo = NDKAuthErrorHandler.analyze(error)
        
        XCTAssertEqual(errorInfo.title, "No Active Session")
        XCTAssertEqual(errorInfo.message, "Please sign in to continue.")
        XCTAssertTrue(errorInfo.isRecoverable)
        XCTAssertEqual(errorInfo.suggestedAction, NDKAuthErrorHandler.ErrorInfo.SuggestedAction.reauthenticate)
    }
    
    func testAnalyzeSessionNotFound() {
        let error = NDKAuthError.sessionNotFound
        let errorInfo = NDKAuthErrorHandler.analyze(error)
        
        XCTAssertEqual(errorInfo.title, "Session Not Found")
        XCTAssertEqual(errorInfo.message, "The requested session could not be found. It may have been deleted.")
        XCTAssertTrue(errorInfo.isRecoverable)
        XCTAssertEqual(errorInfo.suggestedAction, NDKAuthErrorHandler.ErrorInfo.SuggestedAction.reauthenticate)
    }
    
    func testAnalyzeSignerCreationFailed() {
        let underlyingError = NSError(domain: "TestError", code: 1, userInfo: nil)
        let error = NDKAuthError.signerCreationFailed(underlyingError)
        let errorInfo = NDKAuthErrorHandler.analyze(error)
        
        XCTAssertEqual(errorInfo.title, "Authentication Failed")
        XCTAssertEqual(errorInfo.message, "Unable to create authentication credentials. Please try again.")
        XCTAssertTrue(errorInfo.isRecoverable)
        XCTAssertEqual(errorInfo.suggestedAction, NDKAuthErrorHandler.ErrorInfo.SuggestedAction.retry)
    }
    
    func testAnalyzeBiometricAuthenticationFailed() {
        let error = NDKAuthError.biometricAuthenticationFailed
        let errorInfo = NDKAuthErrorHandler.analyze(error)
        
        XCTAssertEqual(errorInfo.title, "Biometric Authentication Failed")
        XCTAssertEqual(errorInfo.message, "Unable to verify your identity. Please try again or use your passcode.")
        XCTAssertTrue(errorInfo.isRecoverable)
        XCTAssertEqual(errorInfo.suggestedAction, NDKAuthErrorHandler.ErrorInfo.SuggestedAction.retry)
    }
    
    func testAnalyzeInvalidSession() {
        let error = NDKAuthError.invalidSession
        let errorInfo = NDKAuthErrorHandler.analyze(error)
        
        XCTAssertEqual(errorInfo.title, "Invalid Session")
        XCTAssertEqual(errorInfo.message, "Your session is no longer valid. Please sign in again.")
        XCTAssertTrue(errorInfo.isRecoverable)
        XCTAssertEqual(errorInfo.suggestedAction, NDKAuthErrorHandler.ErrorInfo.SuggestedAction.reauthenticate)
    }
    
    func testAnalyzeSessionExpired() {
        let error = NDKAuthError.sessionExpired
        let errorInfo = NDKAuthErrorHandler.analyze(error)
        
        XCTAssertEqual(errorInfo.title, "Session Expired")
        XCTAssertEqual(errorInfo.message, "Your session has expired for security reasons. Please sign in again.")
        XCTAssertTrue(errorInfo.isRecoverable)
        XCTAssertEqual(errorInfo.suggestedAction, NDKAuthErrorHandler.ErrorInfo.SuggestedAction.reauthenticate)
    }
    
    func testAnalyzeCorruptedSessionData() {
        let error = NDKAuthError.corruptedSessionData(sessionId: "test-session-id")
        let errorInfo = NDKAuthErrorHandler.analyze(error)
        
        XCTAssertEqual(errorInfo.title, "Corrupted Session Data")
        XCTAssertEqual(errorInfo.message, "The data for this account appears to be corrupted and cannot be recovered. The account will need to be re-added.")
        XCTAssertFalse(errorInfo.isRecoverable)
        XCTAssertEqual(errorInfo.suggestedAction, NDKAuthErrorHandler.ErrorInfo.SuggestedAction.removeAccount)
    }
    
    func testAnalyzeKeychainErrorWithinAuthError() {
        let keychainError = NDKKeychainError.itemNotFound
        let error = NDKAuthError.keychainError(keychainError)
        let errorInfo = NDKAuthErrorHandler.analyze(error)
        
        // Should delegate to keychain error handler
        XCTAssertEqual(errorInfo.title, "Credentials Not Found")
        XCTAssertEqual(errorInfo.message, "Your saved credentials could not be found. Please sign in again.")
        XCTAssertTrue(errorInfo.isRecoverable)
        XCTAssertEqual(errorInfo.suggestedAction, NDKAuthErrorHandler.ErrorInfo.SuggestedAction.reauthenticate)
    }
    
    // MARK: - NDKKeychainError Tests
    
    func testAnalyzeKeychainStorageError() {
        let error = NDKKeychainError.storageError(status: -25299)
        let errorInfo = NDKAuthErrorHandler.analyze(error)
        
        XCTAssertEqual(errorInfo.title, "Storage Error")
        XCTAssertEqual(errorInfo.message, "Failed to save credentials securely (code: -25299). Please try again.")
        XCTAssertTrue(errorInfo.isRecoverable)
        XCTAssertEqual(errorInfo.suggestedAction, NDKAuthErrorHandler.ErrorInfo.SuggestedAction.retry)
    }
    
    func testAnalyzeKeychainRetrievalError() {
        let error = NDKKeychainError.retrievalError(status: -25300)
        let errorInfo = NDKAuthErrorHandler.analyze(error)
        
        XCTAssertEqual(errorInfo.title, "Retrieval Error")
        XCTAssertEqual(errorInfo.message, "Failed to retrieve credentials (code: -25300). Please sign in again.")
        XCTAssertTrue(errorInfo.isRecoverable)
        XCTAssertEqual(errorInfo.suggestedAction, NDKAuthErrorHandler.ErrorInfo.SuggestedAction.reauthenticate)
    }
    
    func testAnalyzeKeychainDeletionError() {
        let error = NDKKeychainError.deletionError(status: -25244)
        let errorInfo = NDKAuthErrorHandler.analyze(error)
        
        XCTAssertEqual(errorInfo.title, "Deletion Error")
        XCTAssertEqual(errorInfo.message, "Failed to remove credentials (code: -25244). Please try again.")
        XCTAssertTrue(errorInfo.isRecoverable)
        XCTAssertEqual(errorInfo.suggestedAction, NDKAuthErrorHandler.ErrorInfo.SuggestedAction.retry)
    }
    
    func testAnalyzeKeychainAccessControlError() {
        let error = NDKKeychainError.accessControlError(error: nil)
        let errorInfo = NDKAuthErrorHandler.analyze(error)
        
        XCTAssertEqual(errorInfo.title, "Access Control Error")
        XCTAssertEqual(errorInfo.message, "Unable to configure secure access. Please try again.")
        XCTAssertTrue(errorInfo.isRecoverable)
        XCTAssertEqual(errorInfo.suggestedAction, NDKAuthErrorHandler.ErrorInfo.SuggestedAction.retry)
    }
    
    func testAnalyzeKeychainItemNotFound() {
        let error = NDKKeychainError.itemNotFound
        let errorInfo = NDKAuthErrorHandler.analyze(error)
        
        XCTAssertEqual(errorInfo.title, "Credentials Not Found")
        XCTAssertEqual(errorInfo.message, "Your saved credentials could not be found. Please sign in again.")
        XCTAssertTrue(errorInfo.isRecoverable)
        XCTAssertEqual(errorInfo.suggestedAction, NDKAuthErrorHandler.ErrorInfo.SuggestedAction.reauthenticate)
    }
    
    func testAnalyzeKeychainInvalidData() {
        let error = NDKKeychainError.invalidData
        let errorInfo = NDKAuthErrorHandler.analyze(error)
        
        XCTAssertEqual(errorInfo.title, "Invalid Credentials")
        XCTAssertEqual(errorInfo.message, "The stored credentials are invalid. Please sign in again.")
        XCTAssertTrue(errorInfo.isRecoverable)
        XCTAssertEqual(errorInfo.suggestedAction, NDKAuthErrorHandler.ErrorInfo.SuggestedAction.reauthenticate)
    }
    
    func testAnalyzeKeychainUserCancelled() {
        let error = NDKKeychainError.userCancelled
        let errorInfo = NDKAuthErrorHandler.analyze(error)
        
        XCTAssertEqual(errorInfo.title, "Authentication Cancelled")
        XCTAssertEqual(errorInfo.message, "You cancelled the authentication.")
        XCTAssertTrue(errorInfo.isRecoverable)
        XCTAssertNil(errorInfo.suggestedAction)
    }
    
    func testAnalyzeKeychainAuthenticationFailed() {
        let error = NDKKeychainError.authenticationFailed
        let errorInfo = NDKAuthErrorHandler.analyze(error)
        
        XCTAssertEqual(errorInfo.title, "Authentication Failed")
        XCTAssertEqual(errorInfo.message, "Unable to access secure storage. Please try again.")
        XCTAssertTrue(errorInfo.isRecoverable)
        XCTAssertEqual(errorInfo.suggestedAction, NDKAuthErrorHandler.ErrorInfo.SuggestedAction.retry)
    }
    
    func testAnalyzeKeychainBiometricNotAvailable() {
        let error = NDKKeychainError.biometricNotAvailable
        let errorInfo = NDKAuthErrorHandler.analyze(error)
        
        XCTAssertEqual(errorInfo.title, "Biometrics Unavailable")
        XCTAssertEqual(errorInfo.message, "Biometric authentication is not available on this device.")
        XCTAssertTrue(errorInfo.isRecoverable)
        XCTAssertNil(errorInfo.suggestedAction)
    }
    
    func testAnalyzeKeychainBiometricNotEnrolled() {
        let error = NDKKeychainError.biometricNotEnrolled
        let errorInfo = NDKAuthErrorHandler.analyze(error)
        
        XCTAssertEqual(errorInfo.title, "Biometrics Not Set Up")
        XCTAssertEqual(errorInfo.message, "Please set up Face ID or Touch ID in Settings to use biometric authentication.")
        XCTAssertTrue(errorInfo.isRecoverable)
        XCTAssertNil(errorInfo.suggestedAction)
    }
    
    // MARK: - LAError Tests
    
    #if !os(watchOS)
    func testAnalyzeLAErrorAuthenticationFailed() {
        let error = LAError(.authenticationFailed)
        let errorInfo = NDKAuthErrorHandler.analyze(error)
        
        XCTAssertEqual(errorInfo.title, "Authentication Failed")
        XCTAssertEqual(errorInfo.message, "Face ID or Touch ID authentication failed. Please try again.")
        XCTAssertTrue(errorInfo.isRecoverable)
        XCTAssertEqual(errorInfo.suggestedAction, NDKAuthErrorHandler.ErrorInfo.SuggestedAction.retry)
    }
    
    func testAnalyzeLAErrorUserCancel() {
        let error = LAError(.userCancel)
        let errorInfo = NDKAuthErrorHandler.analyze(error)
        
        XCTAssertEqual(errorInfo.title, "Authentication Cancelled")
        XCTAssertEqual(errorInfo.message, "You cancelled the authentication.")
        XCTAssertTrue(errorInfo.isRecoverable)
        XCTAssertNil(errorInfo.suggestedAction)
    }
    
    func testAnalyzeLAErrorUserFallback() {
        let error = LAError(.userFallback)
        let errorInfo = NDKAuthErrorHandler.analyze(error)
        
        XCTAssertEqual(errorInfo.title, "Use Passcode")
        XCTAssertEqual(errorInfo.message, "Please enter your device passcode to continue.")
        XCTAssertTrue(errorInfo.isRecoverable)
        XCTAssertNil(errorInfo.suggestedAction)
    }
    
    func testAnalyzeLAErrorSystemCancel() {
        let error = LAError(.systemCancel)
        let errorInfo = NDKAuthErrorHandler.analyze(error)
        
        XCTAssertEqual(errorInfo.title, "Authentication Interrupted")
        XCTAssertEqual(errorInfo.message, "Authentication was cancelled by the system. Please try again.")
        XCTAssertTrue(errorInfo.isRecoverable)
        XCTAssertEqual(errorInfo.suggestedAction, NDKAuthErrorHandler.ErrorInfo.SuggestedAction.retry)
    }
    
    func testAnalyzeLAErrorPasscodeNotSet() {
        let error = LAError(.passcodeNotSet)
        let errorInfo = NDKAuthErrorHandler.analyze(error)
        
        XCTAssertEqual(errorInfo.title, "Passcode Not Set")
        XCTAssertEqual(errorInfo.message, "Please set up a device passcode in Settings to use this feature.")
        XCTAssertFalse(errorInfo.isRecoverable)
        XCTAssertNil(errorInfo.suggestedAction)
    }
    
    func testAnalyzeLAErrorBiometryNotAvailable() {
        let error = LAError(.biometryNotAvailable)
        let errorInfo = NDKAuthErrorHandler.analyze(error)
        
        XCTAssertEqual(errorInfo.title, "Biometrics Unavailable")
        XCTAssertEqual(errorInfo.message, "Face ID or Touch ID is not available on this device.")
        XCTAssertFalse(errorInfo.isRecoverable)
        XCTAssertNil(errorInfo.suggestedAction)
    }
    
    func testAnalyzeLAErrorBiometryNotEnrolled() {
        let error = LAError(.biometryNotEnrolled)
        let errorInfo = NDKAuthErrorHandler.analyze(error)
        
        XCTAssertEqual(errorInfo.title, "Biometrics Not Set Up")
        XCTAssertEqual(errorInfo.message, "Please set up Face ID or Touch ID in Settings to use biometric authentication.")
        XCTAssertFalse(errorInfo.isRecoverable)
        XCTAssertNil(errorInfo.suggestedAction)
    }
    
    func testAnalyzeLAErrorBiometryLockout() {
        let error = LAError(.biometryLockout)
        let errorInfo = NDKAuthErrorHandler.analyze(error)
        
        XCTAssertEqual(errorInfo.title, "Biometrics Locked")
        XCTAssertEqual(errorInfo.message, "Too many failed attempts. Please use your device passcode.")
        XCTAssertTrue(errorInfo.isRecoverable)
        XCTAssertNil(errorInfo.suggestedAction)
    }
    #endif
    
    // MARK: - Network Error Tests
    
    func testAnalyzeURLErrorNotConnectedToInternet() {
        let error = URLError(.notConnectedToInternet)
        let errorInfo = NDKAuthErrorHandler.analyze(error)
        
        XCTAssertEqual(errorInfo.title, "No Internet Connection")
        XCTAssertEqual(errorInfo.message, "Please check your internet connection and try again.")
        XCTAssertTrue(errorInfo.isRecoverable)
        XCTAssertEqual(errorInfo.suggestedAction, NDKAuthErrorHandler.ErrorInfo.SuggestedAction.retry)
    }
    
    func testAnalyzeURLErrorTimedOut() {
        let error = URLError(.timedOut)
        let errorInfo = NDKAuthErrorHandler.analyze(error)
        
        XCTAssertEqual(errorInfo.title, "Request Timed Out")
        XCTAssertEqual(errorInfo.message, "The request took too long. Please try again.")
        XCTAssertTrue(errorInfo.isRecoverable)
        XCTAssertEqual(errorInfo.suggestedAction, NDKAuthErrorHandler.ErrorInfo.SuggestedAction.retry)
    }
    
    func testAnalyzeURLErrorCannotFindHost() {
        let error = URLError(.cannotFindHost)
        let errorInfo = NDKAuthErrorHandler.analyze(error)
        
        XCTAssertEqual(errorInfo.title, "Connection Failed")
        XCTAssertEqual(errorInfo.message, "Unable to connect to the server. Please try again later.")
        XCTAssertTrue(errorInfo.isRecoverable)
        XCTAssertEqual(errorInfo.suggestedAction, NDKAuthErrorHandler.ErrorInfo.SuggestedAction.retry)
    }
    
    func testAnalyzeURLErrorCannotConnectToHost() {
        let error = URLError(.cannotConnectToHost)
        let errorInfo = NDKAuthErrorHandler.analyze(error)
        
        XCTAssertEqual(errorInfo.title, "Connection Failed")
        XCTAssertEqual(errorInfo.message, "Unable to connect to the server. Please try again later.")
        XCTAssertTrue(errorInfo.isRecoverable)
        XCTAssertEqual(errorInfo.suggestedAction, NDKAuthErrorHandler.ErrorInfo.SuggestedAction.retry)
    }
    
    func testAnalyzeURLErrorGeneric() {
        let error = URLError(.badServerResponse)
        let errorInfo = NDKAuthErrorHandler.analyze(error)
        
        XCTAssertEqual(errorInfo.title, "Network Error")
        XCTAssertEqual(errorInfo.message, "A network error occurred. Please try again.")
        XCTAssertTrue(errorInfo.isRecoverable)
        XCTAssertEqual(errorInfo.suggestedAction, NDKAuthErrorHandler.ErrorInfo.SuggestedAction.retry)
    }
    
    // MARK: - Other Error Tests
    
    func testAnalyzeDecodingError() {
        // Create a simple decoding error
        struct TestData: Decodable {
            let value: String
        }
        let json = Data("{}".utf8)
        
        do {
            _ = try JSONDecoder().decode(TestData.self, from: json)
            XCTFail("Expected decoding error")
        } catch {
            let errorInfo = NDKAuthErrorHandler.analyze(error)
            
            XCTAssertEqual(errorInfo.title, "Data Corruption")
            XCTAssertEqual(errorInfo.message, "The session data appears to be corrupted. The account will need to be re-added.")
            XCTAssertFalse(errorInfo.isRecoverable)
            XCTAssertEqual(errorInfo.suggestedAction, NDKAuthErrorHandler.ErrorInfo.SuggestedAction.removeAccount)
        }
    }
    
    func testAnalyzeGenericError() {
        struct CustomError: Error, LocalizedError {
            var errorDescription: String? { "Custom error message" }
        }
        
        let error = CustomError()
        let errorInfo = NDKAuthErrorHandler.analyze(error)
        
        XCTAssertEqual(errorInfo.title, "Authentication Error")
        XCTAssertEqual(errorInfo.message, "Custom error message")
        XCTAssertTrue(errorInfo.isRecoverable)
        XCTAssertEqual(errorInfo.suggestedAction, NDKAuthErrorHandler.ErrorInfo.SuggestedAction.retry)
    }
}