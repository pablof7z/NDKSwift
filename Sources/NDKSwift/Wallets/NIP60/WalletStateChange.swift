import CashuSwift

/// Represents a change to wallet state - what proofs to store, destroy, or reserve
public struct WalletStateChange {
    /// Proofs to be added to the wallet
    public let store: [CashuSwift.Proof]

    /// Proofs to be removed from the wallet
    public let destroy: [CashuSwift.Proof]

    /// The mint this change applies to
    public let mint: String

    /// Optional memo describing the change
    public let memo: String?

    public init(
        store: [CashuSwift.Proof] = [],
        destroy: [CashuSwift.Proof] = [],
        mint: String,
        memo: String? = nil
    ) {
        self.store = store
        self.destroy = destroy
        self.mint = mint
        self.memo = memo
    }
}

/// Represents the token changes needed to reflect a wallet state change
public struct WalletTokenChange {
    /// Token event IDs to be deleted
    public let deletedTokenIds: Set<String>

    /// Proofs to be saved in new token events
    public let saveProofs: [CashuSwift.Proof]

    /// Initialize a new wallet token change
    /// - Parameters:
    ///   - deletedTokenIds: Set of token event IDs that should be deleted
    ///   - saveProofs: Proofs that should be saved in new token events
    public init(deletedTokenIds: Set<String>, saveProofs: [CashuSwift.Proof]) {
        self.deletedTokenIds = deletedTokenIds
        self.saveProofs = saveProofs
    }
}