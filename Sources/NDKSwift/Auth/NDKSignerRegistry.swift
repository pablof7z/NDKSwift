import Foundation

/// Registry for managing signer types and providing serialization utilities
///
/// All NDKSigner implementations now include serialization capabilities built-in.
/// This registry maintains a mapping of signer type identifiers to their corresponding
/// classes, enabling dynamic signer creation during deserialization.
///
/// ## Usage Example
///
/// ```swift
/// // Serialize a signer for storage
/// let data = try await signer.serialize()
/// try await keychainManager.storeSignerData(identifier: "session_123", data: data)
///
/// // Deserialize a signer from storage
/// let data = try await keychainManager.retrieveSignerData(identifier: "session_123")
/// let signer = try NDKSignerRegistry.shared.createSigner(from: data, ndk: ndk)
/// ```
///
/// ## Security Considerations
///
/// Implementations should:
/// - Only serialize necessary data for reconstruction
/// - Avoid storing sensitive data in plaintext
/// - Use secure serialization formats (like JSON with specific keys)
/// - Validate data integrity during deserialization

public class NDKSignerRegistry {
    /// Shared registry instance
    public static let shared = NDKSignerRegistry()
    
    /// Thread-safe storage for registered signer types
    private var registeredSigners: [String: any NDKSigner.Type] = [:]
    private let queue = DispatchQueue(label: "com.ndkswift.signerregistry", attributes: .concurrent)
    
    private init() {
        // Register built-in signer types
        registerBuiltInSigners()
    }
    
    /// Register a signer type with the registry
    /// - Parameter signerType: The signer type to register
    public func register<T: NDKSigner>(_ signerType: T.Type) {
        queue.async(flags: .barrier) { [weak self] in
            self?.registeredSigners[T.signerType] = signerType
        }
    }
    
    /// Get a registered signer type by identifier
    /// - Parameter identifier: The signer type identifier
    /// - Returns: The signer type, or nil if not found
    public func getSignerType(for identifier: String) -> (any NDKSigner.Type)? {
        return queue.sync {
            registeredSigners[identifier]
        }
    }
    
    /// Create a signer instance from serialized data
    /// - Parameters:
    ///   - data: The serialized signer data
    ///   - ndk: Optional NDK instance for signers that need it
    /// - Returns: A reconstructed signer instance
    /// - Throws: Deserialization errors if the data is invalid or the signer type is not registered
    public func createSigner(from data: Data, ndk: NDK? = nil) throws -> any NDKSigner {
        
        // Parse the outer container to get the signer type
        let container: SignerContainer
        do {
            container = try JSONCoding.decode(SignerContainer.self, from: data)
        } catch {
            
            throw error
        }
        
        
        // Get the registered signer type
        guard let signerType = getSignerType(for: container.type) else {
            throw NDKSignerRegistryError.unknownSignerType(container.type)
        }
        
        // Extract the payload data
        let payloadData = try JSONCoding.encode(container.payload)
        
        // Deserialize the signer
        return try signerType.deserialize(payloadData, ndk: ndk)
    }
    
    /// Get all registered signer type identifiers
    /// - Returns: Array of registered signer type identifiers
    public func getRegisteredSignerTypes() -> [String] {
        return queue.sync {
            Array(registeredSigners.keys)
        }
    }
    
    /// Register built-in signer types
    private func registerBuiltInSigners() {
        
        // Register NDKPrivateKeySigner
        register(NDKPrivateKeySigner.self)
        
        // Register NDKBunkerSigner
        register(NDKBunkerSigner.self)
        
        // Future signers will be registered here automatically
    }
}

// MARK: - Serialization Container

/// Container for serialized signer data
///
/// This structure wraps the serialized signer data with its type identifier,
/// enabling the registry to determine which signer class to use for deserialization.
struct SignerContainer: Codable {
    /// The signer type identifier
    let type: String
    
    /// The serialized signer payload
    let payload: [String: AnyCodable]
}

// Using AnyCodable from NWCTypes.swift

// MARK: - Registry Errors

/// Errors that can occur during signer registry operations
public enum NDKSignerRegistryError: LocalizedError {
    case unknownSignerType(String)
    case serializationError(String)
    case deserializationError(String)
    case invalidData
    
    public var errorDescription: String? {
        switch self {
        case .unknownSignerType(let type):
            return "Unknown signer type: \(type)"
        case .serializationError(let message):
            return "Serialization error: \(message)"
        case .deserializationError(let message):
            return "Deserialization error: \(message)"
        case .invalidData:
            return "Invalid serialized data"
        }
    }
}

// MARK: - Signer Serialization Helpers

/// Helper functions for signer serialization
public enum NDKSignerSerialization {
    /// Create a serialized signer container
    /// - Parameters:
    ///   - type: The signer type identifier
    ///   - payload: The signer payload data
    /// - Returns: Serialized container data
    public static func createContainer(type: String, payload: [String: Any]) throws -> Data {
        let container = SignerContainer(
            type: type,
            payload: payload.mapValues { AnyCodable($0) }
        )
        return try JSONCoding.encode(container)
    }
    
    /// Extract payload from serialized container
    /// - Parameter data: The serialized container data
    /// - Returns: The signer type and payload
    public static func extractPayload(from data: Data) throws -> (type: String, payload: [String: Any]) {
        let container = try JSONCoding.decode(SignerContainer.self, from: data)
        let payload = container.payload.mapValues { $0.value }
        return (type: container.type, payload: payload)
    }
}