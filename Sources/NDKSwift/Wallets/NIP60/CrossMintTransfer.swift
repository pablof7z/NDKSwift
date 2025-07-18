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
        proofStateManager: ProofStateManager
    ) async -> String? {
        // Get our mints
        let ourMints = await mints.getMintURLs()
        
        // Find intersection
        let commonMints = Set(ourMints).intersection(acceptedMints)
        
        // Check each common mint for sufficient balance
        for mintURL in commonMints {
            let balance = await proofStateManager.getBalance(mint: mintURL)
            if balance >= requiredAmount {
                return mintURL
            }
        }
        
        return nil
    }
    
    /// Find all mints that have sufficient balance and are in the intersection of accepted mints
    public static func findAllMintsWithSufficientBalance(
        acceptedMints: Set<String>,
        requiredAmount: Int64,
        mints: MintManager,
        proofStateManager: ProofStateManager
    ) async -> [String] {
        // Get our mints
        let ourMints = await mints.getMintURLs()
        
        // Find intersection
        let commonMints = Set(ourMints).intersection(acceptedMints)
        
        var viableMints: [String] = []
        
        // Check each common mint for sufficient balance
        for mintURL in commonMints {
            let balance = await proofStateManager.getBalance(mint: mintURL)
            if balance >= requiredAmount {
                viableMints.append(mintURL)
            }
        }
        
        // Sort by balance (highest first) to try the mint with most balance first
        let sortedMints = await withTaskGroup(of: (String, Int64).self) { group in
            for mintURL in viableMints {
                group.addTask {
                    let balance = await proofStateManager.getBalance(mint: mintURL)
                    return (mintURL, balance)
                }
            }
            
            var results: [(String, Int64)] = []
            for await result in group {
                results.append(result)
            }
            return results.sorted { $0.1 > $1.1 }.map { $0.0 }
        }
        
        return sortedMints
    }
    
    /// Find the best source mint for a cross-mint transfer
    public static func findSourceMintForTransfer(
        amount: Int64,
        targetMint: String,
        mints: MintManager,
        proofStateManager: ProofStateManager,
        feeBuffer: Int64 = 1000
    ) async -> String? {
        let requiredAmount = amount + feeBuffer
        let ourMints = await mints.getMintURLs()
        
        // Find mint with highest balance that can cover the transfer
        var bestMint: (url: String, balance: Int64)? = nil
        
        for mintURL in ourMints {
            // Skip the target mint (no self-transfer)
            if mintURL == targetMint { continue }
            
            let balance = await proofStateManager.getBalance(mint: mintURL)
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
        proofStateManager: ProofStateManager
    ) async -> PaymentRoute {
        print("CrossMintTransfer.findBestPaymentRoute - amount: \(amount), acceptedMints: \(acceptedMints)")
        // First, try to find a direct payment option
        if let directMint = await findMintWithSufficientBalance(
            acceptedMints: acceptedMints,
            requiredAmount: amount,
            mints: mints,
            proofStateManager: proofStateManager
        ) {
            return .direct(mint: directMint)
        }
        
        // No direct payment possible, try cross-mint transfer routes for all accepted mints
        for targetMint in acceptedMints {
            // Find source mint with sufficient balance for transfer + fees
            if let sourceMint = await findSourceMintForTransfer(
                amount: amount,
                targetMint: targetMint,
                mints: mints,
                proofStateManager: proofStateManager,
                feeBuffer: 1000
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
        print("CrossMintTransfer.evaluateTransferRoute - totalBalance: \(totalBalance), required amount: \(amount)")
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
        let meltQuote = try await CashuSwift.getQuote(
            mint: sourceMint,
            quoteRequest: quoteRequest
        ) as! CashuSwift.Bolt11.MeltQuote
        
        // Get available proofs for fee calculation
        let availableProofs = await proofStateManager.getAvailableProofs(mint: sourceMintURL.absoluteString)
        
        // Calculate fees
        let lightningFee = Int64(meltQuote.feeReserve)
        let inputFee = try CashuSwift.calculateFee(for: availableProofs, of: sourceMint)
        let totalFee = lightningFee + Int64(inputFee)
        
        return (lightningFee: lightningFee, inputFee: Int64(inputFee), totalFee: totalFee)
    }
    
    // MARK: - Helper Functions
    
    /// Get total balance across all mints
    private static func getTotalBalance(
        mints: MintManager,
        proofStateManager: ProofStateManager
    ) async -> Int64 {
        let mintURLs = await mints.getMintURLs()
        print("CrossMintTransfer.getTotalBalance - checking balance for \(mintURLs.count) mints: \(mintURLs)")
        var total: Int64 = 0
        
        for mint in mintURLs {
            let balance = await proofStateManager.getBalance(mint: mint)
            print("CrossMintTransfer.getTotalBalance - mint: \(mint), balance: \(balance)")
            total += balance
        }
        
        print("CrossMintTransfer.getTotalBalance - total balance: \(total)")
        return total
    }
}

