import Foundation
import secp256k1

/// Manages P2PK keys for Cashu wallet operations
public actor P2PKManager {
    // MARK: - Properties
    
    private var currentKeypair: (privateKey: String, publicKey: String)?
    private var keyCreatedAt: Date?
    
    // MARK: - Key Management
    
    /// Get or create P2PK keypair
    func getOrCreateKeypair() async throws -> (privateKey: String, publicKey: String) {
        if let existing = currentKeypair {
            return existing
        }
        
        // Generate new Schnorr keypair
        let privateKey = try secp256k1.Schnorr.PrivateKey()
        let publicKey = privateKey.publicKey
        
        let keypair = (
            privateKey: privateKey.dataRepresentation.hexString,
            publicKey: publicKey.dataRepresentation.hexString
        )
        
        currentKeypair = keypair
        keyCreatedAt = Date()
        
        return keypair
    }
    
    /// Get or create private key
    func getOrCreatePrivateKey() async throws -> String {
        let (privateKey, _) = try await getOrCreateKeypair()
        return privateKey
    }
    
    /// Get Cashu-formatted public key (with "02" prefix)
    func getCashuPublicKey() async throws -> String {
        let (_, pubkey) = try await getOrCreateKeypair()
        return "02" + pubkey
    }
    
    /// Create P2PK witness signature
    func createWitness(for secret: String) async throws -> String {
        let (privateKeyHex, _) = try await getOrCreateKeypair()
        
        // Convert hex private key back to PrivateKey object
        guard let privateKeyData = Data(hexString: privateKeyHex) else {
            throw NDKError.invalidDataFormat("P2PK private key", details: "Invalid hex format")
        }
        let privateKey = try secp256k1.Schnorr.PrivateKey(dataRepresentation: privateKeyData)
        
        // Create message to sign (secret)
        guard let messageData = secret.data(using: .utf8) else {
            throw NDKError.validationError("Invalid secret for P2PK signing")
        }
        
        // Sign the secret - using same pattern as Crypto.swift
        var messageBytes = Array(messageData)
        let signature = try privateKey.signature(message: &messageBytes, auxiliaryRand: nil)
        
        return signature.dataRepresentation.hexString
    }
    
    /// Set keypair (for restoration from backup)
    func setKeypair(privateKey: String, publicKey: String) throws {
        // Validate keys
        guard let privateKeyData = Data(hexString: privateKey),
              privateKeyData.count == 32 else {
            throw NDKError.invalidDataFormat("P2PK private key", details: "Must be 32 bytes")
        }
        
        guard let publicKeyData = Data(hexString: publicKey),
              publicKeyData.count == 32 else {
            throw NDKError.invalidDataFormat("P2PK public key", details: "Must be 32 bytes")
        }
        
        currentKeypair = (privateKey, publicKey)
        keyCreatedAt = Date()
    }
    
    /// Restore keypair from private key only (derives public key)
    public func restoreFromPrivateKey(_ privateKeyHex: String) throws {
        guard let privateKeyData = Data(hexString: privateKeyHex),
              privateKeyData.count == 32 else {
            throw NDKError.invalidDataFormat("P2PK private key", details: "Must be 32 bytes")
        }
        
        // Derive public key from private key
        let privateKey = try secp256k1.Schnorr.PrivateKey(dataRepresentation: privateKeyData)
        let publicKey = privateKey.publicKey
        
        currentKeypair = (
            privateKey: privateKeyHex,
            publicKey: publicKey.dataRepresentation.hexString
        )
        keyCreatedAt = Date()
    }
    
    /// Export keypair for backup
    func exportKeypair() async throws -> (privateKey: String, publicKey: String) {
        guard let keypair = currentKeypair else {
            throw NDKError.notConfigured("No P2PK keypair available")
        }
        return keypair
    }
    
    /// Clear stored keypair
    func clearKeypair() {
        currentKeypair = nil
        keyCreatedAt = nil
    }
}

