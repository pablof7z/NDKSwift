import Foundation

/// NDK authentication session model
///
/// Represents a user session with all necessary metadata for session management,
/// restoration, and security features. Sessions contain both public metadata
/// (stored with lower security) and private signer data (stored securely).
///
/// ## Security Design
///
/// Sessions separate public metadata from sensitive signer data:
/// - **Public metadata**: Profile info, preferences, last used date
/// - **Private data**: Signer serialization data, stored in Keychain
///
/// ## Usage
///
/// ```swift
/// let session = NDKSession(
///     pubkey: userPubkey,
///     signerType: "privatekey",
///     requiresBiometric: true
/// )
/// ```
public struct NDKSession: Codable, Identifiable, Sendable {
    /// Unique session identifier based on pubkey and signer type
    public let id: String

    /// User's public key (hex format)
    public let pubkey: String

    /// Signer type identifier (used for deserialization)
    /// nil indicates a read-only session without signing capabilities
    public let signerType: String?

    /// When this session was created
    public let createdAt: Date

    /// When this session was last used
    public var lastUsed: Date

    /// Whether this is the currently active session
    public var isActive: Bool

    // MARK: - Security Settings

    /// Whether biometric authentication is required for this session
    public let requiresBiometric: Bool

    /// Auto-lock timeout in seconds (nil = no auto-lock)
    public var autoLockTimeout: TimeInterval?

    /// Whether this session was created with secure enclave
    public let isHardwareBacked: Bool

    // MARK: - Initialization

    /// Initialize a new session
    /// - Parameters:
    ///   - pubkey: User's public key in hex format
    ///   - signerType: Type identifier for the signer
    ///   - requiresBiometric: Whether biometric auth is required
    ///   - isHardwareBacked: Whether signer uses secure enclave
    ///   - autoLockTimeout: Auto-lock timeout in seconds
    public init(
        pubkey: String,
        signerType: String?,
        requiresBiometric: Bool = false,
        isHardwareBacked: Bool = false,
        autoLockTimeout: TimeInterval? = nil
    ) {
        id = "\(pubkey):\(signerType ?? "readonly")"
        self.pubkey = pubkey
        self.signerType = signerType
        createdAt = Date()
        lastUsed = Date()
        isActive = false
        self.requiresBiometric = requiresBiometric
        self.isHardwareBacked = isHardwareBacked
        self.autoLockTimeout = autoLockTimeout
    }

    // MARK: - Computed Properties

    /// NPub representation of the public key
    public var npub: String? {
        try? Bech32.npub(from: pubkey)
    }

    /// Short identifier for UI display
    public var shortIdentifier: String {
        if let npub = npub {
            return StringFormatHelpers.truncate(npub, maxLength: 16)
        } else {
            return StringFormatHelpers.truncate(pubkey, maxLength: 16)
        }
    }

    /// Security level description
    public var securityLevel: String {
        var components: [String] = []

        if isHardwareBacked {
            components.append("Hardware")
        }

        if requiresBiometric {
            components.append("Biometric")
        }

        if autoLockTimeout != nil {
            components.append("Auto-lock")
        }

        return components.isEmpty ? "Standard" : components.joined(separator: ", ")
    }

    /// Whether this is a read-only session (no signer)
    public var isReadOnly: Bool {
        signerType == nil
    }

    /// Whether this session can sign events
    public var canSign: Bool {
        !isReadOnly
    }

    // MARK: - Session Management

    /// Mark this session as active
    public mutating func markAsActive() {
        isActive = true
        lastUsed = Date()
    }

    /// Mark this session as inactive
    public mutating func markAsInactive() {
        isActive = false
    }

    /// Update last used timestamp
    public mutating func updateLastUsed() {
        lastUsed = Date()
    }

    // MARK: - Validation

    /// Validate that the session data is consistent
    /// - Throws: NDKSessionError if validation fails
    public func validate() throws {
        // Validate pubkey format
        guard HexValidator.isValid32ByteHex(pubkey) else {
            throw NDKSessionError.invalidPubkey(pubkey)
        }

        // Validate signer type if present
        if let signerType = signerType, !signerType.hasContent {
            throw NDKSessionError.invalidSignerType(signerType)
        }

        // Validate auto-lock timeout if set
        if let timeout = autoLockTimeout, timeout <= 0 {
            throw NDKSessionError.invalidAutoLockTimeout(timeout)
        }
    }
}

// MARK: - Session Comparison

extension NDKSession: Equatable {
    public static func == (lhs: NDKSession, rhs: NDKSession) -> Bool {
        lhs.id == rhs.id
    }
}

extension NDKSession: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Session Errors

/// Errors that can occur during session operations
public enum NDKSessionError: LocalizedError {
    case invalidPubkey(String)
    case invalidSignerType(String)
    case invalidAutoLockTimeout(TimeInterval)
    case sessionExpired
    case biometricRequired
    case sessionLocked

    public var errorDescription: String? {
        switch self {
        case let .invalidPubkey(pubkey):
            return "Invalid public key format: \(pubkey)"
        case let .invalidSignerType(type):
            return "Invalid signer type: \(type)"
        case let .invalidAutoLockTimeout(timeout):
            return "Auto-lock timeout must be positive: \(timeout)"
        case .sessionExpired:
            return "Session has expired"
        case .biometricRequired:
            return "Biometric authentication is required for this session"
        case .sessionLocked:
            return "Session is locked"
        }
    }
}

// MARK: - Session Collection Helpers

public extension Array where Element == NDKSession {
    /// Get the currently active session
    var activeSession: NDKSession? {
        first { $0.isActive }
    }

    /// Get sessions sorted by last used (most recent first)
    var sortedByLastUsed: [NDKSession] {
        sorted { $0.lastUsed > $1.lastUsed }
    }

    /// Get sessions that require biometric authentication
    var biometricSessions: [NDKSession] {
        filter { $0.requiresBiometric }
    }

    /// Get hardware-backed sessions
    var hardwareBackedSessions: [NDKSession] {
        filter { $0.isHardwareBacked }
    }
}
