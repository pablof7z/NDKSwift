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
            return supportedMethods.contains(.lightning)
        }
        
        // Future: Could support Cashu if wallet implements it
        return false
    }
    
    public func fulfill(_ request: PaymentRequest) async throws -> PaymentConfirmation {
        // The wallet now expects the new PaymentRequest types directly
        let confirmation = try await wallet.pay(request)
        
        // The confirmation is already in the new format
        return confirmation
    }
    
    public func getBalance() async throws -> Int64? {
        return try await wallet.getBalance()
    }
}