import Foundation
import CashuSwift

/// Payment provider that uses Nostr Wallet Connect (NWC)
public class NWCPaymentProvider: NDKPaymentProvider {
    public let id = "nwc_wallet"
    public let displayName = "Nostr Wallet Connect"
    
    private let nwcWallet: NDKNWCWallet
    
    public init(nwcWallet: NDKNWCWallet) {
        self.nwcWallet = nwcWallet
    }
    
    public func isAvailable() async -> Bool {
        // Check if NWC is connected and ready
        do {
            _ = try await nwcWallet.getInfo()
            return true
        } catch {
            return false
        }
    }
    
    public func canFulfill(_ request: PaymentRequest) async -> Bool {
        // NWC can handle:
        // 1. Direct Lightning invoices
        // 2. Nutzap funding requests (by getting Lightning invoice from mint)
        if request is LightningInvoiceRequest || request is NutzapFundingRequest {
            return await isAvailable()
        }
        
        return false
    }
    
    public func fulfill(_ request: PaymentRequest) async throws -> PaymentConfirmation {
        // Handle Nutzap funding request
        if let nutzapRequest = request as? NutzapFundingRequest {
            return try await fulfillNutzapRequest(nutzapRequest)
        }
        
        // Handle direct Lightning invoice
        guard let lightningRequest = request as? LightningInvoiceRequest else {
            throw PaymentError.cannotFulfillRequest
        }
        
        // Check balance if needed
        if let balance = try? await getBalance(),
           balance < lightningRequest.amountSats {
            throw PaymentError.insufficientBalance(
                available: balance,
                required: lightningRequest.amountSats
            )
        }
        
        // Pay the invoice using NWC
        let response = try await nwcWallet.payInvoice(
            lightningRequest.invoice,
            amount: nil // Amount is in the invoice
        )
        
        // Convert NWC response to our confirmation type
        return LightningPaymentConfirmation(
            preimage: response.preimage,
            paymentHash: nil,
            feePaid: response.feesPaid
        )
    }
    
    public func getBalance() async throws -> Int64? {
        // Use the Int64 version directly
        let balance: Int64 = try await nwcWallet.getBalance()
        return balance
    }
    
    // MARK: - Private Methods
    
    private func fulfillNutzapRequest(_ request: NutzapFundingRequest) async throws -> PaymentConfirmation {
        // Try mints in parallel to find the fastest one
        let mintTasks = request.acceptedMints.map { mintURL in
            Task {
                try await getMintQuote(
                    from: mintURL,
                    amount: request.amountSats
                )
            }
        }
        
        // Wait for first successful quote
        var firstError: Error?
        for task in mintTasks {
            do {
                let (mintURL, quote, invoice) = try await task.value
                
                // Cancel other tasks
                mintTasks.forEach { if $0 !== task { $0.cancel() } }
                
                // Pay the Lightning invoice
                let response = try await nwcWallet.payInvoice(
                    invoice,
                    amount: nil // Amount is in the invoice
                )
                
                // Mint the tokens using the quote
                let proofs = try await mintTokens(
                    mint: mintURL,
                    quote: quote,
                    amount: request.amountSats,
                    recipientP2PK: request.recipientP2PK
                )
                
                // Return Cashu confirmation
                return CashuPaymentConfirmation(
                    proofs: proofs,
                    change: nil,
                    mintURL: mintURL
                )
            } catch {
                firstError = error
                continue
            }
        }
        
        // All mints failed
        throw firstError ?? PaymentError.noAvailableMint
    }
    
    private func getMintQuote(
        from mintURL: URL,
        amount: Int64
    ) async throws -> (mint: URL, quote: String, invoice: String) {
        // In a real implementation, this would:
        // 1. Connect to the mint
        // 2. Request a mint quote for the amount
        // 3. Return the quote ID and Lightning invoice
        
        // For now, throw an error indicating this needs implementation
        throw PaymentError.notImplemented("Mint quote fetching not yet implemented")
    }
    
    private func mintTokens(
        mint: URL,
        quote: String,
        amount: Int64,
        recipientP2PK: String
    ) async throws -> [CashuProof] {
        // In a real implementation, this would:
        // 1. Use the quote to mint tokens after payment
        // 2. Lock the tokens with P2PK for the recipient
        // 3. Return the proofs
        
        // For now, throw an error indicating this needs implementation
        throw PaymentError.notImplemented("Token minting not yet implemented")
    }
}

extension PaymentError {
    static func notImplemented(_ message: String) -> PaymentError {
        return .cannotFulfillRequest
    }
}