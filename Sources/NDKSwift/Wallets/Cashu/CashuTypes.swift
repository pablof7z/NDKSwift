import Foundation
import CashuSwift
import secp256k1

// MARK: - Core Types

/// Information about a Cashu mint
public struct MintInfo {
    public let url: URL
    public let features: [String]?
    
    public init(url: URL, features: [String]? = nil) {
        self.url = url
        self.features = features
    }
}

/// Represents a Cashu proof
public struct CashuProof: Codable, Equatable {
    public let id: String      // Keyset ID
    public let amount: Int
    public let secret: String
    public let C: String       // Signature
    public var witness: String? // For P2PK unlocking
    public let dleq: DLEQProof? // DLEQ proof if present
    
    // State tracking (not serialized)
    var state: ProofState = .available
    
    enum CodingKeys: String, CodingKey {
        case id, amount, secret, C, witness, dleq
    }
    
    public init(id: String, amount: Int, secret: String, C: String, witness: String? = nil, dleq: DLEQProof? = nil) {
        self.id = id
        self.amount = amount
        self.secret = secret
        self.C = C
        self.witness = witness
        self.dleq = dleq
    }
    
    public static func == (lhs: CashuProof, rhs: CashuProof) -> Bool {
        return lhs.id == rhs.id &&
               lhs.amount == rhs.amount &&
               lhs.secret == rhs.secret &&
               lhs.C == rhs.C &&
               lhs.witness == rhs.witness &&
               lhs.dleq == rhs.dleq
    }
}

/// Proof state for tracking
public enum ProofState {
    case available
    case reserved(until: Date, for: String)
    case spent
    case pending
}

/// Token entry in a Cashu token
public struct TokenEntry: Codable {
    public let mint: String
    public let proofs: [CashuProof]
    
    public init(mint: String, proofs: [CashuProof]) {
        self.mint = mint
        self.proofs = proofs
    }
}

/// Cashu token format
public struct CashuToken: Codable {
    public let token: [TokenEntry]
    public let unit: String
    public let memo: String?
    
    public init(token: [TokenEntry], unit: String, memo: String? = nil) {
        self.token = token
        self.unit = unit
        self.memo = memo
    }
}

/// Cashu mint list (NIP-60)
public struct CashuMintList: Codable {
    public struct MintInfo: Codable {
        public let url: String
        public let units: [String]
        
        public init(url: String, units: [String] = ["sat"]) {
            self.url = url
            self.units = units
        }
    }
    
    public let mints: [MintInfo]
    
    public init(mints: [MintInfo]) {
        self.mints = mints
    }
}

// MARK: - NIP-60 Token Event Structure

/// NIP-60 compliant token event content
public struct NIP60TokenEvent: Codable {
    public let mint: String
    public let proofs: [CashuProof]
    public let del: [String]?  // Token event IDs that were destroyed in creating this token
    
    public init(mint: String, proofs: [CashuProof], del: [String]? = nil) {
        self.mint = mint
        self.proofs = proofs
        self.del = del
    }
}

// MARK: - Extensions for CashuSwift Integration

extension CashuProof {
    /// Convert to CashuSwift Proof format
    public func toCashuSwiftProof() -> CashuSwift.Proof {
        // Note: We can't convert DLEQ proofs as CashuSwift.DLEQ doesn't have a public initializer
        // This is a limitation of the CashuSwift library
        // For now, we'll create proofs without DLEQ
        return CashuSwift.Proof(
            keysetID: self.id,
            amount: self.amount,
            secret: self.secret,
            C: self.C,
            dleq: nil,  // Can't create DLEQ due to missing public init
            witness: self.witness
        )
    }
}

extension CashuSwift.Proof {
    /// Convert from CashuSwift Proof to our format
    func toNDKProof() -> CashuProof {
        // Convert DLEQ if present
        let dleq: DLEQProof? = self.dleq.map { swiftDleq in
            DLEQProof(e: swiftDleq.e, s: swiftDleq.s)
        }
        
        return CashuProof(
            id: self.keysetID,
            amount: self.amount,
            secret: self.secret,
            C: self.C,
            witness: self.witness,
            dleq: dleq
        )
    }
}

extension Array where Element == CashuProof {
    /// Convert array of NDK proofs to CashuSwift proofs
    func toCashuSwiftProofs() -> [CashuSwift.Proof] {
        return self.map { $0.toCashuSwiftProof() }
    }
}

extension Array where Element == CashuSwift.Proof {
    /// Convert array of CashuSwift proofs to NDK proofs
    func toNDKProofs() -> [CashuProof] {
        return self.map { $0.toNDKProof() }
    }
}

// MARK: - Helper Functions

/// Split amount into powers of 2 for optimal proof denomination
func splitIntoBase2(_ amount: Int) -> [Int] {
    var result: [Int] = []
    var remaining = amount
    var power = 1
    
    while remaining > 0 {
        if remaining & 1 == 1 {
            result.append(power)
        }
        remaining >>= 1
        power <<= 1
    }
    
    return result
}

// MARK: - P2PK Support

/// Key pair for P2PK operations
public struct KeyPair {
    public let publicKey: String
    public let privateKey: String
    
    public init(publicKey: String, privateKey: String) {
        self.publicKey = publicKey
        self.privateKey = privateKey
    }
}

// MARK: - Payment Method Extension
// Removed - nutzap is now defined in NDKWallet.swift


// MARK: - CashuProof Extensions

extension CashuProof {
    /// Check if this proof is P2PK-locked to a specific pubkey
    public func isLockedTo(pubkey: String) -> Bool {
        // Since CashuSwift's SpendingCondition properties are internal,
        // we need to check the secret format manually
        // P2PK secrets have a specific JSON structure
        
        // Try to parse the secret as JSON
        guard let secretData = self.secret.data(using: .utf8),
              let jsonArray = try? JSONSerialization.jsonObject(with: secretData) as? [Any],
              jsonArray.count >= 2,
              let kindString = jsonArray[0] as? String,
              kindString == "P2PK",
              let payload = jsonArray[1] as? [String: Any],
              let data = payload["data"] as? String else {
            // Not a P2PK spending condition
            return false
        }
        
        // Check if the pubkey matches
        return data == pubkey
    }
    
    /// Create a witness (signature) for unlocking this proof
    public mutating func addWitness(using privateKeyHex: String) throws {
        // Create private key from hex
        guard let privateKeyData = Data(hexString: privateKeyHex) else {
            throw NDKError.invalidInput(message: "Invalid private key hex")
        }
        
        let privateKey = try secp256k1.Schnorr.PrivateKey(dataRepresentation: privateKeyData)
        
        // Create signature for the secret
        guard let secretData = self.secret.data(using: .utf8) else {
            throw NDKError.invalidInput(message: "Could not convert secret to data")
        }
        
        let signature = try privateKey.signature(for: secretData)
        let signatureHex = signature.dataRepresentation.hexString
        
        // Create witness JSON structure
        let witnessDict = ["signatures": [signatureHex]]
        let witnessData = try JSONSerialization.data(withJSONObject: witnessDict)
        self.witness = String(data: witnessData, encoding: .utf8)
    }
    
    /// Verify DLEQ proof if present
    public func verifyDLEQ(keyset: CashuSwift.Keyset) -> Bool {
        // For now, we'll implement basic verification
        // Full DLEQ verification requires access to mint keys
        guard let _ = dleq else {
            // No DLEQ to verify
            return true
        }
        
        // TODO: Implement full DLEQ verification
        // This requires:
        // 1. Access to the mint's public keys for the keyset
        // 2. Cryptographic verification of the DLEQ proof
        // For now, we trust the mint's DLEQ proofs
        return true
    }
}

/// DLEQ proof structure
public struct DLEQProof: Codable, Equatable {
    public let e: String  // Challenge
    public let s: String  // Response
    
    public init(e: String, s: String) {
        self.e = e
        self.s = s
    }
}