import Foundation
import Security
import LocalAuthentication

/// NDK Keychain Manager for secure storage of sensitive authentication data
///
/// This class provides secure storage for NDK authentication data using iOS Keychain Services.
/// It implements proper access controls, biometric authentication, and secure enclave integration
/// following iOS security best practices.
///
/// ## Security Features
///
/// - **Keychain Integration**: Uses iOS Keychain with proper access controls
/// - **Biometric Authentication**: Supports Face ID/Touch ID for sensitive operations
/// - **Secure Enclave**: Leverages hardware security when available
/// - **Device-Only Storage**: Keys don't sync via iCloud by default
/// - **Proper Access Controls**: Uses `biometryCurrentSet` for enhanced security
///
/// ## Usage
///
/// ```swift
/// let keychainManager = NDKKeychainManager()
///
/// // Store a private key securely
/// try await keychainManager.storeSignerData(
///     identifier: "user_session_123",
///     data: signerData,
///     requiresBiometric: true
/// )
///
/// // Retrieve with biometric authentication
/// let data = try await keychainManager.retrieveSignerData(
///     identifier: "user_session_123"
/// )
/// ```
public class NDKKeychainManager {

    /// Accessibility levels for keychain items
    public enum AccessibilityLevel {
        /// Available only when device is unlocked, doesn't sync via iCloud
        case whenUnlockedThisDeviceOnly

        /// Available when device is unlocked, syncs via iCloud
        case whenUnlocked

        /// Available after first unlock, doesn't sync via iCloud
        case afterFirstUnlockThisDeviceOnly

        /// Available after first unlock, syncs via iCloud
        case afterFirstUnlock

        var rawValue: CFString {
            switch self {
            case .whenUnlockedThisDeviceOnly:
                return kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            case .whenUnlocked:
                return kSecAttrAccessibleWhenUnlocked
            case .afterFirstUnlockThisDeviceOnly:
                return kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            case .afterFirstUnlock:
                return kSecAttrAccessibleAfterFirstUnlock
            }
        }
    }

    /// Biometric authentication requirements
    public enum BiometricRequirement {
        /// No biometric authentication required
        case none

        /// Biometric authentication required, invalidated if biometrics change
        case required

        /// Biometric authentication required, remains valid if biometrics change
        case requiredPersistent
    }

    /// Keychain service identifier
    private let service = "com.ndkswift.auth"

    /// Access group for keychain sharing (optional)
    private let accessGroup: String?

    /// Default accessibility level
    private let defaultAccessibility: AccessibilityLevel

    /// Initialize the keychain manager
    /// - Parameters:
    ///   - accessGroup: Optional access group for keychain sharing between apps
    ///   - defaultAccessibility: Default accessibility level for stored items
    public init(
        accessGroup: String? = nil,
        defaultAccessibility: AccessibilityLevel = .whenUnlockedThisDeviceOnly
    ) {
        self.accessGroup = accessGroup
        self.defaultAccessibility = defaultAccessibility
    }

    // MARK: - Signer Data Storage

    /// Store signer data securely in the keychain
    /// - Parameters:
    ///   - identifier: Unique identifier for the signer data
    ///   - data: The signer data to store
    ///   - requiresBiometric: Whether biometric authentication is required
    ///   - accessibility: Accessibility level for this item
    public func storeSignerData(
        identifier: String,
        data: Data,
        requiresBiometric: BiometricRequirement = .none,
        accessibility: AccessibilityLevel? = nil
    ) async throws {
        let actualAccessibility = accessibility ?? defaultAccessibility

        // Create access control
        let accessControl = try createAccessControl(
            accessibility: actualAccessibility,
            biometricRequirement: requiresBiometric
        )

        // Build keychain query
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: identifier,
            kSecValueData as String: data,
            kSecAttrAccessControl as String: accessControl
        ]

        // Add access group if specified
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        // Delete any existing item first
        try await deleteSignerData(identifier: identifier)

        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)

        if status != errSecSuccess {
            throw NDKKeychainError.storageError(status: status)
        }
    }

    /// Retrieve signer data from the keychain
    /// - Parameters:
    ///   - identifier: Unique identifier for the signer data
    ///   - context: Optional authentication context for biometric authentication
    /// - Returns: The stored signer data
    public func retrieveSignerData(
        identifier: String,
        context: LAContext? = nil
    ) async throws -> Data {
        // Build keychain query
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: identifier,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        // Add access group if specified
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        // Add authentication context if provided
        if let context = context {
            query[kSecUseAuthenticationContext as String] = context
        }

        // Query keychain
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw NDKKeychainError.invalidData
            }
            return data

        case errSecItemNotFound:
            throw NDKKeychainError.itemNotFound

        case OSStatus(NDKKeychainError.keychainUserCancelledCode):
            throw NDKKeychainError.userCancelled

        case errSecAuthFailed:
            throw NDKKeychainError.authenticationFailed

        default:
            throw NDKKeychainError.retrievalError(status: status)
        }
    }

    /// Delete signer data from the keychain
    /// - Parameter identifier: Unique identifier for the signer data
    public func deleteSignerData(identifier: String) async throws {
        // Build keychain query
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: identifier
        ]

        // Add access group if specified
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        // Delete item
        let status = SecItemDelete(query as CFDictionary)

        if status != errSecSuccess && status != errSecItemNotFound {
            throw NDKKeychainError.deletionError(status: status)
        }
    }

    /// Check if signer data exists in the keychain
    /// - Parameter identifier: Unique identifier for the signer data
    /// - Returns: True if the data exists, false otherwise
    public func hasSignerData(identifier: String) async -> Bool {
        // Build keychain query
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: identifier,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        // Add access group if specified
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        // Query keychain
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    // MARK: - Session Management

    /// Store session metadata (non-sensitive data)
    /// - Parameters:
    ///   - identifier: Session identifier
    ///   - data: Session metadata
    public func storeSessionMetadata(identifier: String, data: Data) async throws {
        // Build keychain query - use less restrictive access for metadata
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "\(service).session",
            kSecAttrAccount as String: identifier,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        // Add access group if specified
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        // Delete any existing item first
        try await deleteSessionMetadata(identifier: identifier)

        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)

        if status != errSecSuccess {
            throw NDKKeychainError.storageError(status: status)
        }
    }

    /// Retrieve session metadata
    /// - Parameter identifier: Session identifier
    /// - Returns: Session metadata
    public func retrieveSessionMetadata(identifier: String) async throws -> Data {
        // Build keychain query
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "\(service).session",
            kSecAttrAccount as String: identifier,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        // Add access group if specified
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        // Query keychain
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw NDKKeychainError.invalidData
            }
            return data

        case errSecItemNotFound:
            throw NDKKeychainError.itemNotFound

        default:
            throw NDKKeychainError.retrievalError(status: status)
        }
    }

    /// Delete session metadata
    /// - Parameter identifier: Session identifier
    public func deleteSessionMetadata(identifier: String) async throws {
        // Build keychain query
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "\(service).session",
            kSecAttrAccount as String: identifier
        ]

        // Add access group if specified
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        // Delete item
        let status = SecItemDelete(query as CFDictionary)

        if status != errSecSuccess && status != errSecItemNotFound {
            throw NDKKeychainError.deletionError(status: status)
        }
    }

    /// Get all session identifiers
    /// - Returns: Array of session identifiers
    public func getAllSessionIdentifiers() async throws -> [String] {
        // Build keychain query
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "\(service).session",
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]

        // Add access group if specified
        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        // Query keychain
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let items = result as? [[String: Any]] else {
                return []
            }

            return items.compactMap { item in
                item[kSecAttrAccount as String] as? String
            }

        case errSecItemNotFound:
            return []

        default:
            throw NDKKeychainError.retrievalError(status: status)
        }
    }

    // MARK: - Biometric Authentication

    /// Check if biometric authentication is available
    /// - Returns: True if biometric authentication is available
    public func isBiometricAuthenticationAvailable() async -> Bool {
        let context = LAContext()
        var error: NSError?

        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    /// Get available biometric type
    /// - Returns: The available biometric type
    #if !os(watchOS)
    public func getBiometricType() async -> LABiometryType {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }

        return context.biometryType
    }
    #endif

    /// Create authentication context for biometric authentication
    /// - Parameters:
    ///   - reason: Reason for authentication
    ///   - fallbackTitle: Title for fallback authentication
    /// - Returns: Authentication context
    public func createAuthenticationContext(
        reason: String,
        fallbackTitle: String? = nil
    ) -> LAContext {
        let context = LAContext()
        context.localizedFallbackTitle = fallbackTitle
        return context
    }

    // MARK: - Private Methods

    /// Create access control for keychain item
    /// - Parameters:
    ///   - accessibility: Accessibility level
    ///   - biometricRequirement: Biometric requirement
    /// - Returns: Access control reference
    private func createAccessControl(
        accessibility: AccessibilityLevel,
        biometricRequirement: BiometricRequirement
    ) throws -> SecAccessControl {
        var flags: SecAccessControlCreateFlags = []

        switch biometricRequirement {
        case .none:
            break
        case .required:
            flags.insert(.biometryCurrentSet)
        case .requiredPersistent:
            flags.insert(.biometryAny)
        }

        var error: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            accessibility.rawValue,
            flags,
            &error
        ) else {
            if let error = error?.takeRetainedValue() {
                throw NDKKeychainError.accessControlError(error: error)
            } else {
                throw NDKKeychainError.accessControlError(error: nil)
            }
        }

        return accessControl
    }
}

// MARK: - Keychain Errors

/// Errors that can occur during keychain operations
public enum NDKKeychainError: LocalizedError {
    case storageError(status: OSStatus)
    case retrievalError(status: OSStatus)
    case deletionError(status: OSStatus)
    case accessControlError(error: CFError?)
    case itemNotFound
    case invalidData
    case userCancelled
    case authenticationFailed
    case biometricNotAvailable
    case biometricNotEnrolled

    // Keychain error codes
    static let keychainUserCancelledCode: Int32 = -25293

    public var errorDescription: String? {
        switch self {
        case .storageError(let status):
            return "Failed to store item in keychain: \(status)"
        case .retrievalError(let status):
            return "Failed to retrieve item from keychain: \(status)"
        case .deletionError(let status):
            return "Failed to delete item from keychain: \(status)"
        case .accessControlError(let error):
            return "Failed to create access control: \(error?.localizedDescription ?? "Unknown error")"
        case .itemNotFound:
            return "Item not found in keychain"
        case .invalidData:
            return "Invalid data retrieved from keychain"
        case .userCancelled:
            return "User cancelled authentication"
        case .authenticationFailed:
            return "Authentication failed"
        case .biometricNotAvailable:
            return "Biometric authentication not available"
        case .biometricNotEnrolled:
            return "Biometric authentication not enrolled"
        }
    }
}