import CashuSwift

/// Calculates the token changes needed based on a wallet state change
actor WalletStateCalculator {
    
    /// Calculate which tokens need to be created/deleted based on proof changes
    static func calculateNewState(
        stateChange: WalletStateChange,
        proofStateManager: ProofStateManager
    ) async -> WalletTokenChange {
        // Track proofs that need to be destroyed
        let destroyProofCs = Set(stateChange.destroy.map { $0.C })
        
        // Track tokens that need to be deleted
        var tokensToDelete = Set<String>()
        
        // Track all proofs that need to be saved
        var proofsToSave = [CashuSwift.Proof]()
        
        // Add all new proofs from store
        proofsToSave.append(contentsOf: stateChange.store)
        
        // Find tokens affected by destroyed proofs
        for proof in stateChange.destroy {
            if let ownerEventId = await proofStateManager.getOwnerEventId(for: proof) {
                tokensToDelete.insert(ownerEventId)
            }
        }
        
        // For each token being deleted, we need to save any proofs that aren't being destroyed
        for tokenId in tokensToDelete {
            let tokenProofs = await proofStateManager.getAvailableProofsForEvent(tokenId)
            
            for proof in tokenProofs {
                // Only save proofs that aren't being destroyed
                if !destroyProofCs.contains(proof.C) {
                    proofsToSave.append(proof)
                }
            }
        }
        
        return WalletTokenChange(
            deletedTokenIds: tokensToDelete,
            saveProofs: proofsToSave
        )
    }
}