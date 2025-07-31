import Foundation
import CashuSwift

/// Errors specific to mint failures during payment operations
public enum MintFailureError: LocalizedError {
    case requiresUserIntervention(
        pendingOperation: PendingMintOperation,
        sourceMint: String,
        destinationMint: String,
        amount: Int64,
        paymentProof: String
    )

    public var errorDescription: String? {
        switch self {
        case .requiresUserIntervention(let op, let source, let dest, let amount, _):
            return "\(ErrorMessageConstants.failedTo("mint \(amount) sats at \(dest)")) after payment from \(source). Quote ID: \(op.quoteId)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .requiresUserIntervention:
            return "The mint has received payment but failed to issue tokens. You can retry minting or blacklist this mint."
        }
    }
}

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
        let invoiceAmount = amount

        // Get mints with sufficient balance
        let viableMintURLs = await proofStateManager.getMintsWithSufficientBalance(amount: invoiceAmount)

        for mintURL in viableMintURLs {
            do {
                // Get mint with cached keysets
                guard let mintUrl = URLUtils.safeURL(mintURL) else {
                    NDKLogger.log(.error, category: .wallet, "\(ErrorMessageConstants.invalid("mint URL")): \(mintURL)")
                    continue
                }
                let mint = try await wallet.mints.loadMint(url: mintUrl)

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
                NDKLogger.log(.warning, category: .wallet, "\(ErrorMessageConstants.failedTo("pay from mint \(mintURL)")): \(error)")
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
        let response = try await CashuSwift.getQuote(
            mint: mint,
            quoteRequest: quoteRequest
        )

        guard let quote = response as? CashuSwift.Bolt11.MeltQuote else {
            throw NDKError.walletError(message: "Unexpected melt quote response type")
        }

        // Get available proofs for this mint
        let availableProofs = await proofStateManager.getAvailableProofs(mint: mintURL)

        // Calculate total amount needed (invoice amount + fees)
        let lightningFee = Int64(quote.feeReserve)
        let inputFee = try CashuSwift.calculateFee(for: availableProofs, of: mint)
        let totalNeeded = amount + lightningFee + Int64(inputFee)

        // Select proofs to cover the payment
        let selectedProofs = await proofStateManager.selectProofs(amount: totalNeeded, mint: mintURL)
        try GuardHelpers.requireNotEmpty(
            selectedProofs,
            error: NDKError.insufficientBalance(amount: totalNeeded)
        )

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

            // Log DLEQ verification failure but continue
            if !dleqValid {
                NDKLogger.log(.warning, category: .wallet, "⚠️ DLEQ verification failed but continuing since payment was successful. Mint: \(mintURL)")
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
                memo: StringConstants.Transactions.lightningPayment
            )
            let newEventIds = try await wallet.update(stateChange: stateChange)

            // Create spending history
            try await eventManager.createSpendingHistoryEvent(
                direction: .out,
                amount: amount,
                memo: StringConstants.Transactions.lightningPayment,
                destroyedEventIds: nil,
                createdEventIds: newEventIds,
                redeemedEventId: nil,
                signer: signer,
                relays: await wallet.resolvedWalletRelays
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
        let destinationMint = try GuardHelpers.unwrap(
            mints[destinationMintURL.absoluteString],
            error: NDKError.invalidRequest("Destination mint not found in wallet")
        )

        // Step 1: Create Lightning invoice at destination mint
        let mintQuoteRequest = CashuSwift.Bolt11.RequestMintQuote(
            unit: "sat",
            amount: Int(amount)
        )

        let mintResponse = try await CashuSwift.getQuote(
            mint: destinationMint,
            quoteRequest: mintQuoteRequest
        )

        let mintQuote = try GuardHelpers.unwrap(
            mintResponse as? CashuSwift.Bolt11.MintQuote,
            error: NDKError.walletError(message: "Unexpected mint quote response type")
        )

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

        // Step 3: Mint new tokens at destination with retry logic
        let retryHandler = MintRetryHandler()
        let (newProofs, wasUserNotified) = try await retryHandler.retryMintWithBackoff(
            mintQuote: mintQuote,
            mint: destinationMint,
            amount: amount,
            paymentProof: preimage,
            onRetryAttempt: { attemptNumber, delay in
                NDKLogger.log(.info, category: .wallet, "⏳ Cross-mint transfer: Retry attempt \(attemptNumber) in \(Int(delay))s...")
            }
        )

        // Check if user notification is required
        if wasUserNotified && newProofs.isEmpty {
            // Create a pending mint operation for user notification
            let pendingOp = PendingMintOperation(
                quoteId: mintQuote.quote,
                mintURL: destinationMintURL.absoluteString,
                amount: amount,
                invoice: invoice,
                paymentProof: preimage,
                createdAt: Date(),
                lastAttemptAt: Date()
            )

            throw MintFailureError.requiresUserIntervention(
                pendingOperation: pendingOp,
                sourceMint: sourceMintURL.absoluteString,
                destinationMint: destinationMintURL.absoluteString,
                amount: amount,
                paymentProof: preimage
            )
        }

        try GuardHelpers.requireNotEmpty(
            newProofs,
            error: NDKError.paymentFailed(reason: ErrorMessageConstants.failedTo("mint tokens at destination after multiple retries"))
        )

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
        let mint = try GuardHelpers.unwrap(
            mints[mintURL.absoluteString],
            error: NDKError.noMintAvailable("Mint not found: \(mintURL)")
        )

        // Get available proofs for fee calculation
        let availableProofs = await proofStateManager.getAvailableProofs(mint: mintURL.absoluteString)

        // Select proofs for the amount (with some extra for fees)
        let inputFee = try CashuSwift.calculateFee(for: availableProofs, of: mint)
        let totalNeeded = amount + Int64(inputFee)

        let selectedProofs = await proofStateManager.selectProofs(amount: totalNeeded, mint: mintURL.absoluteString)
        try GuardHelpers.requireNotEmpty(
            selectedProofs,
            error: NDKError.insufficientBalance(amount: totalNeeded)
        )

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
            let lockedProofs = try GuardHelpers.unwrap(
                token.proofsByMint[mintURL.absoluteString],
                error: NDKError.invalidProof("No proofs in created token")
            )

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
                memo: StringConstants.Transactions.sendTokens
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