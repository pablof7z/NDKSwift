import Foundation

/// Payment provider that shows a QR code for manual payment
public class QRCodePaymentProvider: NDKPaymentProvider {
    public let id = "qr_code"
    public let displayName = "QR Code (Manual)"
    
    /// Closure to display QR code to user
    public var displayQRCode: ((String) async throws -> Void)?
    
    /// Closure to wait for payment confirmation from user
    public var waitForConfirmation: (() async throws -> String)?
    
    public init(
        displayQRCode: ((String) async throws -> Void)? = nil,
        waitForConfirmation: (() async throws -> String)? = nil
    ) {
        self.displayQRCode = displayQRCode
        self.waitForConfirmation = waitForConfirmation
    }
    
    public func isAvailable() async -> Bool {
        // QR code provider is always available
        return true
    }
    
    public func canFulfill(_ request: PaymentRequest) async -> Bool {
        // Can only handle Lightning invoices for now
        return request is LightningInvoiceRequest
    }
    
    public func fulfill(_ request: PaymentRequest) async throws -> PaymentConfirmation {
        guard let lightningRequest = request as? LightningInvoiceRequest else {
            throw PaymentError.cannotFulfillRequest
        }
        
        // Display QR code
        if let display = displayQRCode {
            try await display(lightningRequest.invoice)
        } else {
            // Default: just print to console
            print("⚡ Pay this Lightning invoice:")
            print(lightningRequest.invoice)
            print("\nAmount: \(lightningRequest.amountSats) sats")
        }
        
        // Wait for confirmation
        let preimage: String
        if let wait = waitForConfirmation {
            preimage = try await wait()
        } else {
            // Default: wait for user input
            print("\nEnter payment preimage when paid (or 'cancel' to abort):")
            
            // In a real app, this would be a proper UI interaction
            // For now, we'll simulate with a placeholder
            throw PaymentError.userCancelled
        }
        
        return LightningPaymentConfirmation(
            preimage: preimage,
            paymentHash: nil,
            feePaid: nil
        )
    }
    
    public func getBalance() async throws -> Int64? {
        // QR code provider doesn't have a balance
        return nil
    }
}