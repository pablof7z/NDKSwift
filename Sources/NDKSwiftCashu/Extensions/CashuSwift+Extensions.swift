import CashuSwift
import NDKSwiftCore

// MARK: - CashuSwift Helper Functions

/// Helper functions for working with CashuSwift types
public enum CashuHelpers {
    /// Checks if a proof is locked to a specific public key using P2PK
    /// This uses CashuSwift's built-in check function to verify locks
    /// - Parameters:
    ///   - proof: The proof to check
    ///   - pubkey: The hex-encoded public key to check against
    /// - Returns: true if the proof is locked to the specified pubkey, false otherwise
    public static func isProofLockedTo(proof: CashuSwift.Proof, pubkey: String) -> Bool {
        // Use CashuSwift's check function to verify the lock
        do {
            let result = try CashuSwift.check(all: [proof], lockedTo: pubkey)
            return result == .match
        } catch {
            // If check fails, the proof is not locked to this pubkey
            return false
        }
    }

    /// Filter proofs that are locked to a specific public key
    /// - Parameters:
    ///   - proofs: Array of proofs to filter
    ///   - pubkey: The hex-encoded public key to check against
    /// - Returns: Array of proofs locked to the specified pubkey
    public static func filterProofsLockedTo(proofs: [CashuSwift.Proof], pubkey: String) -> [CashuSwift.Proof] {
        return proofs.filter { proof in
            isProofLockedTo(proof: proof, pubkey: pubkey)
        }
    }
}
