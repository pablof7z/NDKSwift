import Foundation
import CashuSwift

/// Functions for handling cross-mint transfers and payment routing
public enum CrossMintTransfer {

    // MARK: - Mint Finding

    /// Find a mint that has sufficient balance and is in the intersection of accepted mints
    public static func findMintWithSufficientBalance(
        acceptedMints: Set<String>,
        requiredAmount: Int64,
        mints: MintManager,
        proofStateManager: ProofStateManager,
        blacklistedMints: Set<String> = []
    ) async -> String? {
        // Get mints that actually have proofs
        let proofsByMint = await proofStateManager.getAvailableProofsByMint()
        let ourMints = Set(proofsByMint.keys)

        // Find intersection and exclude blacklisted mints
        let commonMints = ourMints.intersection(acceptedMints).subtracting(blacklistedMints)
        NDKLogger.log(.debug, category: .general, "CrossMintTransfer.findMintWithSufficientBalance - ourMints: \(ourMints)")
        NDKLogger.log(.debug, category: .general, "CrossMintTransfer.findMintWithSufficientBalance - acceptedMints: \(acceptedMints)")
        NDKLogger.log(.debug, category: .general, "CrossMintTransfer.findMintWithSufficientBalance - blacklistedMints: \(blacklistedMints)")
        NDKLogger.log(.debug, category: .general, "CrossMintTransfer.findMintWithSufficientBalance - commonMints: \(commonMints)")

        // Get mints with sufficient balance, then find first one in accepted mints
        let mintsWithBalance = await proofStateManager.getMintsWithSufficientBalance(amount: requiredAmount)
        NDKLogger.log(.debug, category: .general, "CrossMintTransfer.findMintWithSufficientBalance - mintsWithBalance: \(mintsWithBalance)")
        let result = mintsWithBalance.first { commonMints.contains($0) }
        NDKLogger.log(.debug, category: .general, "CrossMintTransfer.findMintWithSufficientBalance - result: \(String(describing: result))")
        return result
    }

    /// Find all mints that have sufficient balance and are in the intersection of accepted mints
    public static func findAllMintsWithSufficientBalance(
        acceptedMints: Set<String>,
        requiredAmount: Int64,
        mints: MintManager,
        proofStateManager: ProofStateManager,
        blacklistedMints: Set<String> = []
    ) async -> [String] {
        // Get mints that actually have proofs
        let proofsByMint = await proofStateManager.getAvailableProofsByMint()
        let ourMints = Set(proofsByMint.keys)

        // Find intersection and exclude blacklisted mints
        let commonMints = ourMints.intersection(acceptedMints).subtracting(blacklistedMints)

        // Get all mints with sufficient balance, then filter by accepted mints
        let mintsWithBalance = await proofStateManager.getMintsWithSufficientBalance(amount: requiredAmount)
        let sortedMints = mintsWithBalance.filter { commonMints.contains($0) }

        return sortedMints
    }

    /// Find the best source mint for a cross-mint transfer
    public static func findSourceMintForTransfer(
        amount: Int64,
        targetMint: String,
        mints: MintManager,
        proofStateManager: ProofStateManager,
        feeBuffer: Int64 = PaymentConstants.defaultCashuFeeBuffer,
        blacklistedMints: Set<String> = []
    ) async -> String? {
        let requiredAmount = amount + feeBuffer

        // Get mints that actually have proofs, not just configured mints
        let proofsByMint = await proofStateManager.getAvailableProofsByMint()

        // Find mint with highest balance that can cover the transfer
        var bestMint: (url: String, balance: Int64)? = nil

        for (mintURL, proofs) in proofsByMint {
            // Skip the target mint (no self-transfer) and blacklisted mints
            if mintURL == targetMint || blacklistedMints.contains(mintURL) { continue }

            let balance = proofs.reduce(0) { $0 + Int64($1.amount) }
            if balance >= requiredAmount {
                if bestMint == nil || balance > bestMint!.balance {
                    bestMint = (url: mintURL, balance: balance)
                }
            }
        }

        return bestMint?.url
    }

    // MARK: - Smart Payment Routing

    /// Find the best payment route (direct or cross-mint transfer)
    public static func findBestPaymentRoute(
        amount: Int64,
        acceptedMints: Set<String>,
        mints: MintManager,
        proofStateManager: ProofStateManager,
        blacklistedMints: Set<String> = []
    ) async -> PaymentRoute {
        NDKLogger.log(.debug, category: .general, "CrossMintTransfer.findBestPaymentRoute - amount: \(amount), acceptedMints: \(acceptedMints)")
        // First, try to find a direct payment option
        // Add buffer for fees (typically 1-2 sats for small payments)
        let amountWithFeeBuffer = amount + 2
        if let directMint = await findMintWithSufficientBalance(
            acceptedMints: acceptedMints,
            requiredAmount: amountWithFeeBuffer,
            mints: mints,
            proofStateManager: proofStateManager,
            blacklistedMints: blacklistedMints
        ) {
            return .direct(mint: directMint)
        }

        // No direct payment possible, try cross-mint transfer routes for all accepted mints
        for targetMint in acceptedMints where !blacklistedMints.contains(targetMint) {
            // Find source mint with sufficient balance for transfer + fees
            if let sourceMint = await findSourceMintForTransfer(
                amount: amount,
                targetMint: targetMint,
                mints: mints,
                proofStateManager: proofStateManager,
                feeBuffer: PaymentConstants.defaultCashuFeeBuffer,
                blacklistedMints: blacklistedMints
            ) {
                // Estimate fees for the transfer
                if let sourceURL = URL(string: sourceMint),
                   let targetURL = URL(string: targetMint) {
                    do {
                        let fees = try await estimateTransferFees(
                            amount: amount,
                            from: sourceURL,
                            to: targetURL,
                            mints: mints,
                            proofStateManager: proofStateManager
                        )
                        return .crossMint(
                            sourceMint: sourceMint,
                            targetMint: targetMint,
                            estimatedFee: fees.totalFee
                        )
                    } catch {
                        // If fee estimation fails, still suggest the route with unknown fees
                        return .crossMint(
                            sourceMint: sourceMint,
                            targetMint: targetMint,
                            estimatedFee: nil
                        )
                    }
                }
            }
        }

        // If no routes work, check why
        let totalBalance = await getTotalBalance(
            mints: mints,
            proofStateManager: proofStateManager
        )
        NDKLogger.log(.debug, category: .general, "CrossMintTransfer.evaluateTransferRoute - totalBalance: \(totalBalance), required amount: \(amount)")
        if totalBalance < amount {
            return .impossible(reason: "Insufficient total balance: \(totalBalance) < \(amount)")
        } else {
            return .impossible(reason: "Insufficient balance in any single mint for transfer with fees")
        }
    }

    // MARK: - Transfer Operations

    /// Transfer funds between mints using Lightning as a bridge
    public static func transferBetweenMints(
        amount: Int64,
        from sourceMintURL: URL,
        to destinationMintURL: URL,
        wallet: NIP60Wallet,
        proofStateManager: ProofStateManager,
        eventManager: WalletEventManager,
        mints: MintManager,
        signer: NDKSigner
    ) async throws -> TransferResult {
        // Validate mints exist
        let allMints = await mints.getAllMints()
        guard allMints[sourceMintURL.absoluteString] != nil else {
            throw NDKError.invalidRequest("Source mint not found in wallet")
        }
        guard allMints[destinationMintURL.absoluteString] != nil else {
            throw NDKError.invalidRequest("Destination mint not found in wallet")
        }

        // Execute transfer through Payment static functions
        let result = try await Payment.transferBetweenMints(
            wallet: wallet,
            from: sourceMintURL,
            to: destinationMintURL,
            amount: amount,
            mints: await mints.getAllMints(),
            proofStateManager: proofStateManager,
            eventManager: eventManager,
            signer: signer
        )

        return TransferResult(
            amountTransferred: amount,
            feePaid: result.feePaid,
            preimage: result.preimage,
            sourceMint: sourceMintURL,
            destinationMint: destinationMintURL
        )
    }

    /// Estimate fees for a cross-mint transfer
    public static func estimateTransferFees(
        amount: Int64,
        from sourceMintURL: URL,
        to destinationMintURL: URL,
        mints: MintManager,
        proofStateManager: ProofStateManager
    ) async throws -> (lightningFee: Int64, inputFee: Int64, totalFee: Int64) {
        // Validate mints exist
        let allMints = await mints.getAllMints()
        guard let sourceMint = allMints[sourceMintURL.absoluteString] else {
            throw NDKError.invalidRequest("Source mint not found in wallet")
        }

        // Request a mint quote to get the Lightning invoice
        let quoteResponse = try await mints.requestMintQuote(
            amount: amount,
            mintURL: destinationMintURL.absoluteString
        )

        let mintQuote = CashuMintQuote(
            quoteId: quoteResponse.quote,
            mintURL: destinationMintURL.absoluteString,
            amount: amount,
            invoice: quoteResponse.request,
            expiry: Date(),
            requestedAt: Date()
        )

        // Create melt quote request to estimate fees
        let quoteRequest = CashuSwift.Bolt11.RequestMeltQuote(
            unit: "sat",
            request: mintQuote.invoice,
            options: nil
        )

        // Get melt quote from source mint
        let meltResponse = try await CashuSwift.getQuote(
            mint: sourceMint,
            quoteRequest: quoteRequest
        )

        guard let meltQuote = meltResponse as? CashuSwift.Bolt11.MeltQuote else {
            throw NDKError.walletError(message: "Unexpected melt quote response type")
        }

        // Get available proofs for fee calculation
        let availableProofs = await proofStateManager.getAvailableProofs(mint: sourceMintURL.absoluteString)

        // Calculate fees
        let lightningFee = Int64(meltQuote.feeReserve)
        let inputFee = try CashuSwift.calculateFee(for: availableProofs, of: sourceMint)
        let totalFee = lightningFee + Int64(inputFee)

        return (lightningFee: lightningFee, inputFee: Int64(inputFee), totalFee: totalFee)
    }

    // MARK: - Helper Functions

    /// Get total balance across all mints that actually have proofs
    private static func getTotalBalance(
        mints: MintManager,
        proofStateManager: ProofStateManager
    ) async -> Int64 {
        // Get mints with actual proofs, not configured mints
        let proofsByMint = await proofStateManager.getAvailableProofsByMint()
        let mintsWithProofs = Array(proofsByMint.keys)
        NDKLogger.log(.debug, category: .general, "CrossMintTransfer.getTotalBalance - checking balance for \(mintsWithProofs.count) mints with proofs: \(mintsWithProofs)")

        var total: Int64 = 0
        for (mint, proofs) in proofsByMint {
            let balance = proofs.reduce(0) { $0 + Int64($1.amount) }
            NDKLogger.log(.debug, category: .wallet, "CrossMintTransfer.getTotalBalance - mint: \(mint), balance: \(balance)")
            total += balance
        }

        NDKLogger.log(.debug, category: .wallet, "CrossMintTransfer.getTotalBalance - total balance: \(total)")
        return total
    }
}

