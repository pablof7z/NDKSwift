import Foundation
import CashuSwift

// MARK: - Core Types

/// Represents a Cashu proof
public struct CashuProof: Codable, Equatable {
    public let id: String      // Keyset ID
    public let amount: Int
    public let secret: String
    public let C: String       // Signature
    public var witness: String? // For P2PK unlocking
    
    // State tracking (not serialized)
    var state: ProofState = .available
    
    enum CodingKeys: String, CodingKey {
        case id, amount, secret, C, witness
    }
    
    public init(id: String, amount: Int, secret: String, C: String, witness: String? = nil) {
        self.id = id
        self.amount = amount
        self.secret = secret
        self.C = C
        self.witness = witness
    }
    
    public static func == (lhs: CashuProof, rhs: CashuProof) -> Bool {
        return lhs.id == rhs.id &&
               lhs.amount == rhs.amount &&
               lhs.secret == rhs.secret &&
               lhs.C == rhs.C &&
               lhs.witness == rhs.witness
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

// MARK: - Extensions for CashuSwift Integration

extension CashuProof {
    /// Convert to CashuSwift Proof format
    func toCashuSwiftProof() -> CashuSwift.Proof {
        return CashuSwift.Proof(
            keysetID: self.id,
            amount: self.amount,
            secret: self.secret,
            C: self.C
        )
    }
}

extension CashuSwift.Proof {
    /// Convert from CashuSwift Proof to our format
    func toNDKProof() -> CashuProof {
        return CashuProof(
            id: self.keysetID,
            amount: self.amount,
            secret: self.secret,
            C: self.C,
            witness: nil
        )
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

extension NDKPaymentMethod {
    /// Nutzap payment method
    public static let nutzap = NDKPaymentMethod(rawValue: "nip61")
}

// MARK: - CashuProof Extensions

extension CashuProof {
    /// Check if this proof is locked to a specific P2PK pubkey
    public func isLockedTo(pubkey: String) -> Bool {
        // Simple check - in a real implementation, this would verify the cryptographic lock
        // For P2PK proofs, the secret would be derived from the pubkey
        return true // Placeholder
    }
    
    /// DLEQ proof data (placeholder)
    public var dleq: DLEQProof? {
        return nil // Placeholder
    }
}

/// DLEQ proof structure (placeholder)
public struct DLEQProof: Codable {
    public let s: String
    public let e: String
}