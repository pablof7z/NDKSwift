import Foundation
import NDKSwiftCore
import secp256k1

/// Manages P2PK keys for Cashu wallet operations
public actor P2PKManager {
    // MARK: - Properties

    private var currentKeypair: (privateKey: String, pubkey: String)?
    private var keyCreatedAt: Date?

    // MARK: - Key Management

    /// Get or create P2PK keypair
    func getOrCreateKeypair() async throws -> (privateKey: String, pubkey: String) {
        if let existing = currentKeypair {
            return existing
        }

        // Generate new Schnorr keypair
        let privateKey = try secp256k1.Schnorr.PrivateKey()
        let publicKey = privateKey.publicKey

        let keypair = (
            privateKey: privateKey.dataRepresentation.hexString,
            pubkey: publicKey.dataRepresentation.hexString
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
        return "\(NostrConstants.cashuCompressedKeyPrefix)\(pubkey)"
    }

    /// Create P2PK witness signature
    func createWitness(for secret: String) async throws -> String {
        let (privateKeyHex, _) = try await getOrCreateKeypair()

        // Convert hex private key back to PrivateKey object
        let privateKeyData = try HexValidator.validate32ByteHex(privateKeyHex)
        let privateKey = try secp256k1.Schnorr.PrivateKey(dataRepresentation: privateKeyData)

        // Create message to sign (secret)
        let messageData = try GuardHelpers.unwrap(
            secret.data(using: .utf8),
            error: NDKError.validationError(ErrorMessageConstants.invalid("secret for P2PK signing"))
        )

        // Sign the secret - using same pattern as Crypto.swift
        var messageBytes = Array(messageData)
        let signature = try privateKey.signature(message: &messageBytes, auxiliaryRand: nil)

        return signature.dataRepresentation.hexString
    }

    /// Set keypair (for restoration from backup)
    func setKeypair(privateKey: String, pubkey: String) throws {
        // Validate keys
        guard HexValidator.isValid32ByteHex(privateKey) else {
            throw NDKError.invalidDataFormat("private key", details: "Must be 32-byte hex string")
        }
        guard HexValidator.isValid32ByteHex(pubkey) else {
            throw NDKError.invalidDataFormat("public key", details: "Must be 32-byte hex string")
        }

        currentKeypair = (privateKey, pubkey)
        keyCreatedAt = Date()
    }

    /// Restore keypair from private key only (derives public key)
    public func restoreFromPrivateKey(_ privateKeyHex: String) throws {
        let privateKeyData = try HexValidator.validate32ByteHex(privateKeyHex)

        // Derive public key from private key
        let privateKey = try secp256k1.Schnorr.PrivateKey(dataRepresentation: privateKeyData)
        let publicKey = privateKey.publicKey

        currentKeypair = (
            privateKey: privateKeyHex,
            pubkey: publicKey.dataRepresentation.hexString
        )
        keyCreatedAt = Date()
    }

    /// Clear stored keypair
    func clearKeypair() {
        currentKeypair = nil
        keyCreatedAt = nil
    }
}

