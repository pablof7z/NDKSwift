import Foundation

/// Payment provider that adapts the legacy NDKWallet interface
public class WalletAdapterPaymentProvider: NDKPaymentProvider {
    public let id: String
    public let displayName: String
    
    private let wallet: NDKWallet
    private let supportedMethods: Set<NDKPaymentMethod>
    
    public init(wallet: NDKWallet, id: String? = nil, displayName: String? = nil) {
        self.wallet = wallet
        self.id = id ?? "wallet_adapter"
        self.displayName = displayName ?? "Wallet"
        
        // Determine supported methods
        var methods = Set<NDKPaymentMethod>()
        if wallet.supports(method: .lightning) {
            methods.insert(.lightning)
        }
        if wallet.supports(method: .nwc) {
            methods.insert(.nwc)
        }
        self.supportedMethods = methods
    }
    
    public func isAvailable() async -> Bool {
        // Try to get balance to check if wallet is working
        do {
            _ = try await wallet.getBalance()
            return true
        } catch {
            return false
        }
    }
    
    public func canFulfill(_ request: PaymentRequest) async -> Bool {
        // Can only handle Lightning invoices if wallet supports Lightning
        if request is LightningInvoiceRequest {
            return supportedMethods.contains(.lightning) || supportedMethods.contains(.nwc)
        }
        
        // Future: Could support Cashu if wallet implements it
        return false
    }
    
    public func fulfill(_ request: PaymentRequest) async throws -> PaymentConfirmation {
        guard let lightningRequest = request as? LightningInvoiceRequest else {
            throw PaymentError.cannotFulfillRequest
        }
        
        // Create legacy payment request
        let recipient = NDKUser(pubkey: lightningRequest.recipient)
        let paymentRequest = NDKStandardPaymentRequest(
            recipient: recipient,
            amount: lightningRequest.amountSats,
            comment: nil
        )
        
        // Pay using legacy wallet
        let confirmation = try await wallet.pay(paymentRequest)
        
        // Convert to new confirmation type
        if let lightningConfirmation = confirmation as? NDKLightningPaymentConfirmation {
            return LightningPaymentConfirmation(
                preimage: lightningConfirmation.preimage,
                paymentHash: nil,
                feePaid: nil
            )
        } else {
            // Generic confirmation - generate a placeholder preimage
            return LightningPaymentConfirmation(
                preimage: "legacy_payment_\(Date().timeIntervalSince1970)",
                paymentHash: nil,
                feePaid: nil
            )
        }
    }
    
    public func getBalance() async throws -> Int64? {
        return try await wallet.getBalance()
    }
}