import Foundation
import CashuSwift

/// Functions for handling payment operations (Lightning, cross-mint transfers, and direct token transfers)
public enum Payment {
    
    // MARK: - Lightning Payments
    
    /// Pay a Lightning invoice from the wallet
    public static func payLightning(
        wallet: NIP60Wallet,
        invoice: String,
        amount: Int64,
        mints: [String: CashuSwift.Mint],
        proofStateManager: ProofStateManager,
        eventManager: WalletEventManager,
        signer: NDKSigner
    ) async throws -> (preimage: String, feePaid: Int64?) {
        // For now, use the provided amount
        let invoiceAmount = amount
        
        // Find a mint that can handle this payment
        for (mintURL, mint) in mints {
            let mintBalance = await proofStateManager.getBalance(mint: mintURL)
            
            // Skip if insufficient balance (with buffer for fees)
            if mintBalance < invoiceAmount + 1000 { // 1000 sat fee buffer
                continue
            }
            
            do {
                return try await payLightningFromMint(
                    wallet: wallet,
                    invoice: invoice,
                    amount: invoiceAmount,
                    mintURL: mintURL,
                    mint: mint,
                    proofStateManager: proofStateManager,
                    eventManager: eventManager,
                    signer: signer
                )
            } catch {
                // Try next mint if this one fails
                print("Failed to pay from mint \(mintURL): \(error)")
                continue
            }
        }
        
        throw NDKError.insufficientBalance(amount: invoiceAmount)
    }
    
    /// Pay Lightning invoice from a specific mint
    private static func payLightningFromMint(
        wallet: NIP60Wallet,
        invoice: String,
        amount: Int64,
        mintURL: String,
        mint: CashuSwift.Mint,
        proofStateManager: ProofStateManager,
        eventManager: WalletEventManager,
        signer: NDKSigner
    ) async throws -> (preimage: String, feePaid: Int64?) {
        // Create melt quote request
        let quoteRequest = CashuSwift.Bolt11.RequestMeltQuote(
            unit: "sat",
            request: invoice,
            options: nil
        )
        
        // Get melt quote from mint
        let quote = try await CashuSwift.getQuote(
            mint: mint,
            quoteRequest: quoteRequest
        ) as! CashuSwift.Bolt11.MeltQuote
        
        // Get available proofs for this mint
        let availableProofs = await proofStateManager.getAvailableProofs(mint: mintURL)
        
        // Calculate total amount needed (invoice amount + fees)
        let lightningFee = Int64(quote.feeReserve)
        let inputFee = try CashuSwift.calculateFee(for: availableProofs, of: mint)
        let totalNeeded = amount + lightningFee + Int64(inputFee)
        
        // Select proofs to cover the payment
        let selectedProofs = await proofStateManager.selectProofs(amount: totalNeeded, mint: mintURL)
        guard !selectedProofs.isEmpty else {
            throw NDKError.insufficientBalance(amount: totalNeeded)
        }
        
        // Reserve proofs for this operation
        try await proofStateManager.reserveProofs(selectedProofs)
        
        do {
            // Generate blank outputs for potential change
            let (outputs, blindingFactors, secrets) = try CashuSwift.generateBlankOutputs(
                quote: quote,
                proofs: selectedProofs,
                mint: mint,
                unit: "sat",
                seed: nil
            )
            
            let blankOutputs = (
                outputs: outputs,
                blindingFactors: blindingFactors,
                secrets: secrets
            )
            
            // Execute the melt operation
            let (paid, change, dleqValid) = try await CashuSwift.melt(
                with: quote,
                mint: mint,
                proofs: selectedProofs,
                blankOutputs: blankOutputs
            )
            
            // Check if payment was successful
            guard paid else {
                throw NDKError.paymentFailed(reason: "Lightning payment was not successful")
            }
            
            guard dleqValid else {
                throw NDKError.invalidProof("DLEQ verification failed")
            }
            
            // Mark used proofs as deleted
            await proofStateManager.markProofsAsDeleted(selectedProofs)
            
            // Add change proofs if any
            if let changeProofs = change {
                for proof in changeProofs {
                    await proofStateManager.addProof(proof, mint: mintURL)
                }
            }
            
            // Update wallet state
            let stateChange = WalletStateChange(
                store: change ?? [],
                destroy: selectedProofs,
                mint: mintURL,
                memo: "Lightning payment"
            )
            let newEventIds = try await wallet.update(stateChange: stateChange)
            
            // Create spending history
            try await eventManager.createSpendingHistoryEvent(
                direction: .out,
                amount: amount,
                memo: "Lightning payment",
                destroyedEventIds: nil,
                createdEventIds: newEventIds,
                redeemedEventId: nil,
                signer: signer
            )
            
            let actualFeePaid = lightningFee + Int64(inputFee)
            return (preimage: quote.quote, feePaid: actualFeePaid)
            
        } catch {
            // Release reservation on failure
            await proofStateManager.releaseProofs(selectedProofs)
            throw error
        }
    }
    
    // MARK: - Cross-Mint Transfers
    
    /// Transfer tokens between mints using Lightning as a bridge
    public static func transferBetweenMints(
        wallet: NIP60Wallet,
        from sourceMintURL: URL,
        to destinationMintURL: URL,
        amount: Int64,
        mints: [String: CashuSwift.Mint],
        proofStateManager: ProofStateManager,
        eventManager: WalletEventManager,
        signer: NDKSigner
    ) async throws -> PaymentTransferResult {
        // Validate mints exist
        guard mints[sourceMintURL.absoluteString] != nil else {
            throw NDKError.invalidRequest("Source mint not found in wallet")
        }
        guard let destinationMint = mints[destinationMintURL.absoluteString] else {
            throw NDKError.invalidRequest("Destination mint not found in wallet")
        }
        
        // Step 1: Create Lightning invoice at destination mint
        let mintQuoteRequest = CashuSwift.Bolt11.RequestMintQuote(
            unit: "sat",
            amount: Int(amount)
        )
        
        let mintQuote = try await CashuSwift.getQuote(
            mint: destinationMint,
            quoteRequest: mintQuoteRequest
        ) as! CashuSwift.Bolt11.MintQuote
        
        let invoice = mintQuote.request
        
        // Step 2: Pay invoice from source mint
        let (preimage, feePaid) = try await payLightning(
            wallet: wallet,
            invoice: invoice,
            amount: amount,
            mints: mints,
            proofStateManager: proofStateManager,
            eventManager: eventManager,
            signer: signer
        )
        
        // Step 3: Mint new tokens at destination
        let (newProofs, validDLEQ) = try await CashuSwift.issue(
            for: mintQuote,
            with: destinationMint,
            seed: nil
        )
        
        // Verify DLEQ if available
        if !validDLEQ {
            throw NDKError.invalidProof("DLEQ verification failed")
        }
        
        // Step 4: Update wallet state with new proofs
        for proof in newProofs {
            await proofStateManager.addProof(proof, mint: destinationMintURL.absoluteString)
        }
        
        let stateChange = WalletStateChange(
            store: newProofs,
            destroy: [],
            mint: destinationMintURL.absoluteString,
            memo: "Cross-mint transfer"
        )
        _ = try await wallet.update(stateChange: stateChange)
        
        return PaymentTransferResult(
            proofs: newProofs,
            feePaid: feePaid ?? 0,
            preimage: preimage
        )
    }
    
    // MARK: - Direct Token Transfers
    
    /// Send P2PK-locked proofs to a recipient
    public static func sendP2PK(
        wallet: NIP60Wallet,
        amount: Int64,
        to recipientP2PK: String,
        mint mintURL: URL,
        mints: [String: CashuSwift.Mint],
        proofStateManager: ProofStateManager,
        signer: NDKSigner
    ) async throws -> (proofs: [CashuSwift.Proof], change: [CashuSwift.Proof]?) {
        // Get the mint
        guard let mint = mints[mintURL.absoluteString] else {
            throw NDKError.noMintAvailable("Mint not found: \(mintURL)")
        }
        
        // Get available proofs for fee calculation
        let availableProofs = await proofStateManager.getAvailableProofs(mint: mintURL.absoluteString)
        
        // Select proofs for the amount (with some extra for fees)
        let inputFee = try CashuSwift.calculateFee(for: availableProofs, of: mint)
        let totalNeeded = amount + Int64(inputFee)
        
        let selectedProofs = await proofStateManager.selectProofs(amount: totalNeeded, mint: mintURL.absoluteString)
        guard !selectedProofs.isEmpty else {
            throw NDKError.insufficientBalance(amount: totalNeeded)
        }
        
        // Reserve proofs for this operation
        try await proofStateManager.reserveProofs(selectedProofs)
        
        do {
            // Use CashuSwift's send function with P2PK locking
            let (token, changeProofs, _) = try await CashuSwift.send(
                inputs: selectedProofs,
                mint: mint,
                amount: Int(amount),
                seed: nil,
                memo: nil,
                lockToPublicKey: recipientP2PK
            )
            
            // Get the locked proofs from the token
            guard let lockedProofs = token.proofsByMint[mintURL.absoluteString] else {
                throw NDKError.invalidProof("No proofs in created token")
            }
            
            // Mark used proofs as deleted
            await proofStateManager.markProofsAsDeleted(selectedProofs)
            
            // Add change proofs if any
            if !changeProofs.isEmpty {
                for proof in changeProofs {
                    await proofStateManager.addProof(proof, mint: mintURL.absoluteString)
                }
            }
            
            // Update wallet state
            let stateChange = WalletStateChange(
                store: changeProofs,
                destroy: selectedProofs,
                mint: mintURL.absoluteString,
                memo: "Send tokens"
            )
            _ = try await wallet.update(stateChange: stateChange)
            
            return (proofs: lockedProofs, change: changeProofs)
            
        } catch {
            // Release reservation on failure
            await proofStateManager.releaseProofs(selectedProofs)
            throw error
        }
    }
}

// MARK: - Supporting Types

/// Internal result type for payment operations
public struct PaymentTransferResult {
    public let proofs: [CashuSwift.Proof]
    public let feePaid: Int64
    public let preimage: String
}