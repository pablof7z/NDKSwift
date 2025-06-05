import Foundation

/// Payment request details
public struct NDKPaymentRequest {
    public let recipient: NDKUser
    public let amount: Int64 // in satoshis
    public let comment: String?
    public let tags: [[String]]?
    public let unit: String = "sat"

    public init(recipient: NDKUser, amount: Int64, comment: String? = nil, tags: [[String]]? = nil) {
        self.recipient = recipient
        self.amount = amount
        self.comment = comment
        self.tags = tags
    }
}

/// Payment confirmation details
public protocol NDKPaymentConfirmation {
    var amount: Int64 { get }
    var recipient: String { get } // pubkey
    var timestamp: Date { get }
}

/// Lightning payment confirmation
public struct NDKLightningPaymentConfirmation: NDKPaymentConfirmation {
    public let amount: Int64
    public let recipient: String
    public let timestamp: Date
    public let preimage: String
    public let paymentRequest: String

    public init(amount: Int64, recipient: String, timestamp: Date, preimage: String, paymentRequest: String) {
        self.amount = amount
        self.recipient = recipient
        self.timestamp = timestamp
        self.preimage = preimage
        self.paymentRequest = paymentRequest
    }
}

/// Cashu payment confirmation
public struct NDKCashuPaymentConfirmation: NDKPaymentConfirmation {
    public let amount: Int64
    public let recipient: String
    public let timestamp: Date
    public let nutzap: NDKNutzap?

    public init(amount: Int64, recipient: String, timestamp: Date, nutzap: NDKNutzap? = nil) {
        self.amount = amount
        self.recipient = recipient
        self.timestamp = timestamp
        self.nutzap = nutzap
    }
}

/// Base wallet protocol
public protocol NDKWallet {
    /// Pay a payment request
    func pay(_ request: NDKPaymentRequest) async throws -> NDKPaymentConfirmation

    /// Get wallet balance
    func getBalance() async throws -> Int64

    /// Create a Lightning invoice
    func createInvoice(amount: Int64, description: String?) async throws -> String

    /// Check if wallet supports a specific payment method
    func supports(method: NDKPaymentMethod) -> Bool
}

/// Payment methods
public enum NDKPaymentMethod: String {
    case lightning = "nip57"
    case nutzap = "nip61"
    case nwc = "nip47"
}

/// Wallet configuration for NDK
public struct NDKWalletConfig {
    /// Lightning payment callback
    public var lnPay: ((NDKPaymentRequest, String) async throws -> NDKLightningPaymentConfirmation?)?

    /// Cashu payment callback
    public var cashuPay: ((NDKPaymentRequest) async throws -> NDKCashuPaymentConfirmation?)?

    /// Enable automatic fallback to NIP-61 if NIP-57 fails
    public var nutzapAsFallback: Bool = false

    /// Completion callback
    public var onPaymentComplete: ((NDKPaymentConfirmation?, Error?) -> Void)?

    public init(
        lnPay: ((NDKPaymentRequest, String) async throws -> NDKLightningPaymentConfirmation?)? = nil,
        cashuPay: ((NDKPaymentRequest) async throws -> NDKCashuPaymentConfirmation?)? = nil,
        nutzapAsFallback: Bool = false,
        onPaymentComplete: ((NDKPaymentConfirmation?, Error?) -> Void)? = nil
    ) {
        self.lnPay = lnPay
        self.cashuPay = cashuPay
        self.nutzapAsFallback = nutzapAsFallback
        self.onPaymentComplete = onPaymentComplete
    }
}
