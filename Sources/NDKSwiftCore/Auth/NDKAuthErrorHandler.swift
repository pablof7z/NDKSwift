import Foundation
import LocalAuthentication

/// Centralized error handler for authentication-related errors
/// Provides user-friendly error messages and proper error type handling
public enum NDKAuthErrorHandler {
    /// Categorizes an error and provides user-friendly messaging
    public struct ErrorInfo {
        public let title: String
        public let message: String
        public let isRecoverable: Bool
        public let suggestedAction: SuggestedAction?

        public enum SuggestedAction: Equatable {
            case retry
            case removeAccount
            case reauthenticate
            case contactSupport
        }
    }

    /// Analyze an error and return appropriate user-facing information
    public static func analyze(_ error: Error) -> ErrorInfo {
        // First check for NDKAuthError
        if let authError = error as? NDKAuthError {
            return handleAuthError(authError)
        }

        // Check for keychain errors
        if let keychainError = error as? NDKKeychainError {
            return handleKeychainError(keychainError)
        }

        // Check for LAError (biometric errors)
        #if !os(watchOS)
            if let laError = error as? LAError {
                return handleBiometricError(laError)
            }
        #endif

        // Check for decoding errors (corrupted data)
        if error is DecodingError {
            return ErrorInfo(
                title: "Data Corruption",
                message: "The session data appears to be corrupted. The account will need to be re-added.",
                isRecoverable: false,
                suggestedAction: .removeAccount
            )
        }

        // Check for network errors
        if let urlError = error as? URLError {
            return handleNetworkError(urlError)
        }

        // Default error handling
        return ErrorInfo(
            title: "Authentication Error",
            message: error.localizedDescription,
            isRecoverable: true,
            suggestedAction: .retry
        )
    }

    // MARK: - Specific Error Handlers

    private static func handleAuthError(_ error: NDKAuthError) -> ErrorInfo {
        switch error {
        case .noActiveSession:
            return ErrorInfo(
                title: "No Active Session",
                message: "Please sign in to continue.",
                isRecoverable: true,
                suggestedAction: .reauthenticate
            )

        case .sessionNotFound:
            return ErrorInfo(
                title: "Session Not Found",
                message: "The requested session could not be found. It may have been deleted.",
                isRecoverable: true,
                suggestedAction: .reauthenticate
            )

        case .signerCreationFailed:
            return ErrorInfo(
                title: "Authentication Failed",
                message: "Unable to create authentication credentials. Please try again.",
                isRecoverable: true,
                suggestedAction: .retry
            )

        case .biometricAuthenticationFailed:
            return ErrorInfo(
                title: "Biometric Authentication Failed",
                message: "Unable to verify your identity. Please try again or use your passcode.",
                isRecoverable: true,
                suggestedAction: .retry
            )

        case let .keychainError(underlyingError):
            // Delegate to keychain error handler
            return analyze(underlyingError)

        case .invalidSession:
            return ErrorInfo(
                title: "Invalid Session",
                message: "Your session is no longer valid. Please sign in again.",
                isRecoverable: true,
                suggestedAction: .reauthenticate
            )

        case .sessionExpired:
            return ErrorInfo(
                title: "Session Expired",
                message: "Your session has expired for security reasons. Please sign in again.",
                isRecoverable: true,
                suggestedAction: .reauthenticate
            )

        case .corruptedSessionData:
            return ErrorInfo(
                title: "Corrupted Session Data",
                message: "The data for this account appears to be corrupted and cannot be recovered. The account will need to be re-added.",
                isRecoverable: false,
                suggestedAction: .removeAccount
            )
        }
    }

    private static func handleKeychainError(_ error: NDKKeychainError) -> ErrorInfo {
        switch error {
        case let .storageError(status):
            return ErrorInfo(
                title: "Storage Error",
                message: "Failed to save credentials securely (code: \(status)). Please try again.",
                isRecoverable: true,
                suggestedAction: .retry
            )

        case let .retrievalError(status):
            return ErrorInfo(
                title: "Retrieval Error",
                message: "Failed to retrieve credentials (code: \(status)). Please sign in again.",
                isRecoverable: true,
                suggestedAction: .reauthenticate
            )

        case let .deletionError(status):
            return ErrorInfo(
                title: "Deletion Error",
                message: "Failed to remove credentials (code: \(status)). Please try again.",
                isRecoverable: true,
                suggestedAction: .retry
            )

        case .accessControlError:
            return ErrorInfo(
                title: "Access Control Error",
                message: "Unable to configure secure access. Please try again.",
                isRecoverable: true,
                suggestedAction: .retry
            )

        case .itemNotFound:
            return ErrorInfo(
                title: "Credentials Not Found",
                message: "Your saved credentials could not be found. Please sign in again.",
                isRecoverable: true,
                suggestedAction: .reauthenticate
            )

        case .invalidData:
            return ErrorInfo(
                title: "Invalid Credentials",
                message: "The stored credentials are invalid. Please sign in again.",
                isRecoverable: true,
                suggestedAction: .reauthenticate
            )

        case .userCancelled:
            return ErrorInfo(
                title: "Authentication Cancelled",
                message: "You cancelled the authentication.",
                isRecoverable: true,
                suggestedAction: nil
            )

        case .authenticationFailed:
            return ErrorInfo(
                title: "Authentication Failed",
                message: "Unable to access secure storage. Please try again.",
                isRecoverable: true,
                suggestedAction: .retry
            )

        case .biometricNotAvailable:
            return ErrorInfo(
                title: "Biometrics Unavailable",
                message: "Biometric authentication is not available on this device.",
                isRecoverable: true,
                suggestedAction: nil
            )

        case .biometricNotEnrolled:
            return ErrorInfo(
                title: "Biometrics Not Set Up",
                message: "Please set up Face ID or Touch ID in Settings to use biometric authentication.",
                isRecoverable: true,
                suggestedAction: nil
            )
        }
    }

    #if !os(watchOS)
        private static func handleBiometricError(_ error: LAError) -> ErrorInfo {
            let errorMappings: [LAError.Code: (title: String, message: String, isRecoverable: Bool, suggestedAction: ErrorInfo.SuggestedAction?)] = [
                .authenticationFailed: (
                    "Authentication Failed",
                    "Face ID or Touch ID authentication failed. Please try again.",
                    true,
                    .retry
                ),
                .userCancel: (
                    "Authentication Cancelled",
                    "You cancelled the authentication.",
                    true,
                    nil
                ),
                .userFallback: (
                    "Use Passcode",
                    "Please enter your device passcode to continue.",
                    true,
                    nil
                ),
                .systemCancel: (
                    "Authentication Interrupted",
                    "Authentication was cancelled by the system. Please try again.",
                    true,
                    .retry
                ),
                .passcodeNotSet: (
                    "Passcode Not Set",
                    "Please set up a device passcode in Settings to use this feature.",
                    false,
                    nil
                ),
                .biometryNotAvailable: (
                    "Biometrics Unavailable",
                    "Face ID or Touch ID is not available on this device.",
                    false,
                    nil
                ),
                .biometryNotEnrolled: (
                    "Biometrics Not Set Up",
                    "Please set up Face ID or Touch ID in Settings to use biometric authentication.",
                    false,
                    nil
                ),
                .biometryLockout: (
                    "Biometrics Locked",
                    "Too many failed attempts. Please use your device passcode.",
                    true,
                    nil
                ),
            ]

            if let mapping = errorMappings[error.code] {
                return ErrorInfo(
                    title: mapping.title,
                    message: mapping.message,
                    isRecoverable: mapping.isRecoverable,
                    suggestedAction: mapping.suggestedAction
                )
            } else {
                return ErrorInfo(
                    title: ErrorMessageConstants.Messages.authenticationFailed,
                    message: error.localizedDescription,
                    isRecoverable: true,
                    suggestedAction: .retry
                )
            }
        }
    #endif

    private static func handleNetworkError(_ error: URLError) -> ErrorInfo {
        switch error.code {
        case .notConnectedToInternet:
            return ErrorInfo(
                title: "No Internet Connection",
                message: "Please check your internet connection and try again.",
                isRecoverable: true,
                suggestedAction: .retry
            )

        case .timedOut:
            return ErrorInfo(
                title: "Request Timed Out",
                message: "The request took too long. Please try again.",
                isRecoverable: true,
                suggestedAction: .retry
            )

        case .cannotFindHost, .cannotConnectToHost:
            return ErrorInfo(
                title: "Connection Failed",
                message: "Unable to connect to the server. Please try again later.",
                isRecoverable: true,
                suggestedAction: .retry
            )

        default:
            return ErrorInfo(
                title: "Network Error",
                message: "A network error occurred. Please try again.",
                isRecoverable: true,
                suggestedAction: .retry
            )
        }
    }
}
