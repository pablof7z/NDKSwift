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



/// Token entry in a Cashu token
public struct TokenEntry: Codable {
    public let mint: String
    public let proofs: [CashuSwift.Proof]
    
    public init(mint: String, proofs: [CashuSwift.Proof]) {
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
    public let proofs: [CashuSwift.Proof]
    public let del: [String]?  // Token event IDs that were destroyed in creating this token
    
    public init(mint: String, proofs: [CashuSwift.Proof], del: [String]? = nil) {
        self.mint = mint
        self.proofs = proofs
        self.del = del
    }
}

// MARK: - Extensions for CashuSwift Integration

extension CashuSwift.Proof {
    
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


