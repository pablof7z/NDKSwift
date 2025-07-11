import Foundation

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
        // NWC is a Lightning wallet - it can only pay Lightning invoices directly
        guard request is LightningInvoiceRequest else {
            return false
        }
        
        // Check if available
        guard await isAvailable() else {
            return false
        }
        
        // Check balance if we can
        if let balance = try? await getBalance() {
            return balance >= request.amountSats
        }
        
        // If we can't check balance, assume we can pay
        return true
    }
    
    public func fulfill(_ request: PaymentRequest) async throws -> PaymentConfirmation {
        // NWC only handles Lightning invoices
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
}