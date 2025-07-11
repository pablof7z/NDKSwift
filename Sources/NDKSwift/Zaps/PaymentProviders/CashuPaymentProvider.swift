import Foundation

/// Payment provider that uses a Cashu wallet
public class CashuPaymentProvider: NDKPaymentProvider {
    public let id = "cashu_wallet"
    public let displayName = "Cashu Wallet"
    
    private let cashuWallet: NDKCashuWallet
    
    public init(cashuWallet: NDKCashuWallet) {
        self.cashuWallet = cashuWallet
    }
    
    public func isAvailable() async -> Bool {
        // Check if wallet has any mints configured and balance
        let mints = await cashuWallet.getMints()
        guard !mints.isEmpty else { return false }
        
        // Check if we have any balance
        let balance = (try? await cashuWallet.getBalance()) ?? 0
        return balance > 0
    }
    
    public func canFulfill(_ request: PaymentRequest) async -> Bool {
        // Cashu wallet can handle:
        // 1. Direct Cashu proof requests (for same-mint transfers)
        // 2. Nutzap funding requests (choosing optimal mint)
        // 3. Lightning invoices (via mint's Lightning gateway)
        
        if request is CashuProofRequest || request is NutzapFundingRequest {
            return await isAvailable()
        }
        
        if let _ = request as? LightningInvoiceRequest {
            // Check if any of our mints support Lightning
            let mints = await cashuWallet.getMints()
            // In a real implementation, check mint capabilities
            let available = await isAvailable()
            return !mints.isEmpty && available
        }
        
        return false
    }
    
    public func fulfill(_ request: PaymentRequest) async throws -> PaymentConfirmation {
        // Handle Nutzap funding request
        if let nutzapRequest = request as? NutzapFundingRequest {
            return try await fulfillNutzapRequest(nutzapRequest)
        }
        
        // Handle direct Cashu proof request
        if let cashuRequest = request as? CashuProofRequest {
            return try await fulfillCashuRequest(cashuRequest)
        }
        
        // Handle Lightning invoice via mint gateway
        if let lightningRequest = request as? LightningInvoiceRequest {
            return try await fulfillLightningRequest(lightningRequest)
        }
        
        throw PaymentError.cannotFulfillRequest
    }
    
    public func getBalance() async throws -> Int64? {
        return try? await cashuWallet.getBalance()
    }
    
    // MARK: - Private Methods
    
    private func fulfillNutzapRequest(_ request: NutzapFundingRequest) async throws -> PaymentConfirmation {
        // Get our wallet's mints
        let walletMints = await cashuWallet.getMints()
        let walletMintURLs = Set(walletMints.map { $0.url })
        
        // Find intersection with recipient's accepted mints
        let acceptedMintURLs = Set(request.acceptedMints)
        let commonMints = walletMintURLs.intersection(acceptedMintURLs)
        
        // Select optimal mint
        let selectedMint: URL
        if !commonMints.isEmpty {
            // Prefer same-mint transfer (free and instant)
            selectedMint = try await selectOptimalMint(
                from: Array(commonMints),
                forAmount: request.amountSats
            )
        } else {
            // No common mints - need to use Lightning bridge
            // Get wallet mint URLs for error message
            let walletMintStrings = walletMintURLs.map { $0.absoluteString }
            let recipientMintStrings = acceptedMintURLs.map { $0.absoluteString }
            throw ZapError.noCommonMints(
                wallet: walletMintStrings,
                recipient: recipientMintStrings
            )
        }
        
        // Generate P2PK-locked proofs for the selected mint
        let (proofs, change) = try await cashuWallet.send(
            amount: request.amountSats,
            to: request.recipientP2PK,
            mint: selectedMint
        )
        
        return CashuPaymentConfirmation(
            proofs: proofs,
            change: change,
            mintURL: selectedMint
        )
    }
    
    private func fulfillCashuRequest(_ request: CashuProofRequest) async throws -> PaymentConfirmation {
        // Direct Cashu proof request - check if we have balance on this mint
        let walletMints = await cashuWallet.getMints()
        guard walletMints.contains(where: { $0.url == request.mintURL }) else {
            throw PaymentError.mintNotAvailable
        }
        
        // Generate P2PK-locked proofs
        let (proofs, change) = try await cashuWallet.send(
            amount: request.amountSats,
            to: request.recipientP2PK,
            mint: request.mintURL
        )
        
        return CashuPaymentConfirmation(
            proofs: proofs,
            change: change,
            mintURL: request.mintURL
        )
    }
    
    private func fulfillLightningRequest(_ request: LightningInvoiceRequest) async throws -> PaymentConfirmation {
        // Pay Lightning invoice via mint (melting ecash)
        let result = try await cashuWallet.payLightning(
            invoice: request.invoice,
            amount: request.amountSats
        )
        
        return LightningPaymentConfirmation(
            preimage: result.preimage,
            feePaid: result.feePaid
        )
    }
    
    private func selectOptimalMint(from mints: [URL], forAmount amount: Int64) async throws -> URL {
        // Select the mint with the best balance for this amount
        for mint in mints {
            let balance = await cashuWallet.getBalance(mint: mint)
            if balance >= amount {
                return mint
            }
        }
        
        // If no single mint has enough balance
        let totalBalance = (try? await cashuWallet.getBalance()) ?? 0
        if totalBalance < amount {
            throw PaymentError.insufficientBalance(available: totalBalance, required: amount)
        }
        
        // Would need to implement mint splitting in the future
        throw PaymentError.noAvailableMint
    }
}

// MARK: - Cashu-specific Payment Errors

extension PaymentError {
    static var noAvailableMint: PaymentError {
        return .paymentFailed(reason: "No available mint for payment")
    }
    
    static var requiresLightningBridge: PaymentError {
        return .paymentFailed(reason: "Payment requires Lightning bridge")
    }
    
    static var mintNotAvailable: PaymentError {
        return .paymentFailed(reason: "Requested mint is not available in wallet")
    }
}