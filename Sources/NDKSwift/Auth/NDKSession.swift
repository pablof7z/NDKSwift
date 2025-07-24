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
    public let signerType: String
    
    /// When this session was created
    public let createdAt: Date
    
    /// When this session was last used
    public var lastUsed: Date
    
    /// Whether this is the currently active session
    public var isActive: Bool
    
    // MARK: - Profile Metadata
    
    /// User's avatar URL
    public var avatarURL: URL?
    
    /// User's NIP-05 identifier
    public var nip05: String?
    
    /// User's about/bio text
    public var about: String?
    
    /// User's display name from profile metadata
    public var profileName: String?
    
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
        signerType: String,
        requiresBiometric: Bool = false,
        isHardwareBacked: Bool = false,
        autoLockTimeout: TimeInterval? = nil
    ) {
        self.id = "\(pubkey):\(signerType)"
        self.pubkey = pubkey
        self.signerType = signerType
        self.createdAt = Date()
        self.lastUsed = Date()
        self.isActive = false
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
            return String(npub.prefix(16)) + "..."
        } else {
            return String(pubkey.prefix(16)) + "..."
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
    
    /// Update profile metadata from NDKUserProfile
    /// - Parameter profile: The user profile to update from
    public mutating func updateProfile(_ profile: NDKUserProfile) {
        profileName = profile.name
        about = profile.about
        nip05 = profile.nip05
        
        if let picture = profile.picture, let url = URL(string: picture) {
            avatarURL = url
        }
    }
    
    // MARK: - Validation
    
    /// Validate that the session data is consistent
    /// - Throws: NDKSessionError if validation fails
    public func validate() throws {
        // Validate pubkey format
        guard HexValidator.isValid32ByteHex(pubkey) else {
            throw NDKSessionError.invalidPubkey(pubkey)
        }
        
        // Validate signer type
        guard ValidationHelpers.hasContent(signerType) else {
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
        case .invalidPubkey(let pubkey):
            return "Invalid public key format: \(pubkey)"
        case .invalidSignerType(let type):
            return "Invalid signer type: \(type)"
        case .invalidAutoLockTimeout(let timeout):
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

extension Array where Element == NDKSession {
    /// Get the currently active session
    public var activeSession: NDKSession? {
        first { $0.isActive }
    }
    
    /// Get sessions sorted by last used (most recent first)
    public var sortedByLastUsed: [NDKSession] {
        sorted { $0.lastUsed > $1.lastUsed }
    }
    
    /// Get sessions that require biometric authentication
    public var biometricSessions: [NDKSession] {
        filter { $0.requiresBiometric }
    }
    
    /// Get hardware-backed sessions
    public var hardwareBackedSessions: [NDKSession] {
        filter { $0.isHardwareBacked }
    }
}