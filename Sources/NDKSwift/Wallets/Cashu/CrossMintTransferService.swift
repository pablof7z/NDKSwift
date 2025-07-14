import Foundation
import CashuSwift

/// Service for handling transfers between different Cashu mints
public actor CrossMintTransferService {
    // MARK: - Properties
    
    private let paymentProcessor: PaymentProcessor
    private let depositManager: CashuDepositManager
    private let mintManager: MintManager
    private let proofStateManager: ProofStateManager
    
    // MARK: - Initialization
    
    public init(
        paymentProcessor: PaymentProcessor,
        depositManager: CashuDepositManager,
        mintManager: MintManager,
        proofStateManager: ProofStateManager
    ) {
        self.paymentProcessor = paymentProcessor
        self.depositManager = depositManager
        self.mintManager = mintManager
        self.proofStateManager = proofStateManager
    }
    
    // MARK: - Mint Finding
    
    /// Find a mint that has sufficient balance and is in the intersection of accepted mints
    /// - Parameters:
    ///   - acceptedMints: Set of mint URLs that are accepted for the payment
    ///   - requiredAmount: Minimum amount needed (including potential fees)
    /// - Returns: The mint URL with sufficient balance, or nil if none found
    public func findMintWithSufficientBalance(
        acceptedMints: Set<String>,
        requiredAmount: Int64
    ) async -> String? {
        // Get our mints
        let ourMints = await mintManager.getMintURLs()
        
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
    
    /// Find the best source mint for a cross-mint transfer
    /// - Parameters:
    ///   - amount: Amount to transfer
    ///   - targetMint: Destination mint URL
    ///   - feeBuffer: Additional amount to cover fees (default 1000 sats)
    /// - Returns: Source mint URL with sufficient balance, or nil if none found
    public func findSourceMintForTransfer(
        amount: Int64,
        targetMint: String,
        feeBuffer: Int64 = 1000
    ) async -> String? {
        let requiredAmount = amount + feeBuffer
        let ourMints = await mintManager.getMintURLs()
        
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
    
    // MARK: - Transfer Operations
    
    /// Transfer funds between mints using Lightning as a bridge
    public func transferBetweenMints(
        amount: Int64,
        from sourceMintURL: URL,
        to destinationMintURL: URL,
        wallet: NDKCashuWallet,
        signer: NDKSigner
    ) async throws -> TransferResult {
        // Validate mints exist
        let mints = await mintManager.getAllMints()
        guard mints[sourceMintURL.absoluteString] != nil else {
            throw NDKError.invalidRequest("Source mint not found in wallet")
        }
        guard mints[destinationMintURL.absoluteString] != nil else {
            throw NDKError.invalidRequest("Destination mint not found in wallet")
        }
        
        // Execute transfer through payment processor
        let result = try await paymentProcessor.transferBetweenMints(
            wallet: wallet,
            from: sourceMintURL,
            to: destinationMintURL,
            amount: amount,
            mints: mints,
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
    public func estimateTransferFees(
        amount: Int64,
        from sourceMintURL: URL,
        to destinationMintURL: URL
    ) async throws -> (lightningFee: Int64, inputFee: Int64, totalFee: Int64) {
        // Validate mints exist
        let mints = await mintManager.getAllMints()
        guard let sourceMint = mints[sourceMintURL.absoluteString] else {
            throw NDKError.invalidRequest("Source mint not found in wallet")
        }
        
        // Request a mint quote to get the Lightning invoice
        let mintQuote = try await depositManager.requestMintQuote(
            amount: amount,
            mintURL: destinationMintURL.absoluteString,
            mintManager: mintManager,
            persistQuote: false,
            signer: nil
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
    
    // MARK: - Smart Payment Routing
    
    /// Find the best payment route (direct or cross-mint transfer)
    /// - Parameters:
    ///   - amount: Payment amount
    ///   - acceptedMints: Mints accepted by the recipient
    ///   - preferDirectPayment: Whether to prefer direct payment over cross-mint transfer
    /// - Returns: Payment route information
    public func findBestPaymentRoute(
        amount: Int64,
        acceptedMints: Set<String>,
        preferDirectPayment: Bool = true
    ) async -> PaymentRoute {
        // First, try to find a direct payment option
        if let directMint = await findMintWithSufficientBalance(
            acceptedMints: acceptedMints,
            requiredAmount: amount
        ) {
            return .direct(mint: directMint)
        }
        
        // No direct payment possible, find cross-mint transfer route
        guard let targetMint = acceptedMints.first else {
            return .impossible(reason: "No accepted mints provided")
        }
        
        // Find source mint with sufficient balance for transfer + fees
        guard let sourceMint = await findSourceMintForTransfer(
            amount: amount,
            targetMint: targetMint,
            feeBuffer: 1000 // Conservative fee buffer
        ) else {
            let totalBalance = await getTotalBalance()
            if totalBalance < amount {
                return .impossible(reason: "Insufficient total balance: \(totalBalance) < \(amount)")
            } else {
                return .impossible(reason: "Insufficient balance in any single mint for transfer with fees")
            }
        }
        
        // Estimate fees for the transfer
        if let sourceURL = URL(string: sourceMint),
           let targetURL = URL(string: targetMint) {
            do {
                let fees = try await estimateTransferFees(
                    amount: amount,
                    from: sourceURL,
                    to: targetURL
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
        
        return .impossible(reason: "Invalid mint URLs")
    }
    
    // MARK: - Helper Methods
    
    /// Get total balance across all mints
    private func getTotalBalance() async -> Int64 {
        let mints = await mintManager.getMintURLs()
        var total: Int64 = 0
        
        for mint in mints {
            total += await proofStateManager.getBalance(mint: mint)
        }
        
        return total
    }
}

// MARK: - Supporting Types

/// Represents a payment route decision
public enum PaymentRoute {
    /// Direct payment using a mint that both parties accept
    case direct(mint: String)
    
    /// Cross-mint transfer required
    case crossMint(sourceMint: String, targetMint: String, estimatedFee: Int64?)
    
    /// Payment is impossible
    case impossible(reason: String)
    
    /// Check if this route requires a cross-mint transfer
    public var requiresTransfer: Bool {
        if case .crossMint = self {
            return true
        }
        return false
    }
    
    /// Get the mint to use for payment (nil if impossible)
    public var paymentMint: String? {
        switch self {
        case .direct(let mint):
            return mint
        case .crossMint(_, let targetMint, _):
            return targetMint
        case .impossible:
            return nil
        }
    }
}