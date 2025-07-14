import Foundation

// MARK: - Deprecated Types (to be removed in future version)

@available(*, deprecated, renamed: "PaymentRequest", message: "Use PaymentRequest from ZapTypes instead")
public protocol NDKPaymentRequest {
    var recipient: NDKUser { get }
    var amount: Int64 { get }
    var comment: String? { get }
    var tags: [[String]]? { get }
    var unit: String { get }
}

@available(*, deprecated, message: "Use LightningInvoiceRequest or NutzapPaymentRequest from ZapTypes instead")
public struct NDKStandardPaymentRequest: NDKPaymentRequest {
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

@available(*, deprecated, renamed: "PaymentConfirmation", message: "Use PaymentConfirmation from ZapTypes instead")
public protocol NDKPaymentConfirmation {
    var amount: Int64 { get }
    var recipient: String { get } // pubkey
    var timestamp: Date { get }
}

@available(*, deprecated, renamed: "LightningPaymentConfirmation", message: "Use LightningPaymentConfirmation from ZapTypes instead")
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

@available(*, deprecated, renamed: "NutzapConfirmation", message: "Use NutzapConfirmation from ZapTypes instead")
public struct NDKCashuPaymentConfirmation: NDKPaymentConfirmation {
    public let amount: Int64
    public let recipient: String
    public let timestamp: Date
    public let nutzap: NDKEvent

    public init(amount: Int64, recipient: String, timestamp: Date, nutzap: NDKEvent) {
        self.amount = amount
        self.recipient = recipient
        self.timestamp = timestamp
        self.nutzap = nutzap
    }
}

/// Base wallet protocol
public protocol NDKWallet {
    /// Pay a payment request
    func pay(_ request: PaymentRequest) async throws -> PaymentConfirmation

    /// Get wallet balance
    func getBalance() async throws -> Int64

    /// Create a Lightning invoice
    func createInvoice(amount: Int64, description: String?) async throws -> String

    /// Check if wallet supports a specific payment method
    func supports(method: NDKPaymentMethod) -> Bool
}

@available(*, deprecated, renamed: "NutzapPaymentRequest", message: "Use NutzapPaymentRequest from ZapTypes instead")
public struct NDKNutzapRequest: NDKPaymentRequest {
    public let recipient: NDKUser
    public let amount: Int64 // in satoshis
    public let comment: String?
    public let tags: [[String]]?
    public let unit: String = "sat"
    public let mints: [URL] // Accepted mints for the nutzap
    public let recipientPubkey: String // Recipient's public key for P2PK locking

    public init(recipient: NDKUser, amount: Int64, mints: [URL], recipientPubkey: String, comment: String? = nil, tags: [[String]]? = nil) {
        self.recipient = recipient
        self.amount = amount
        self.mints = mints
        self.recipientPubkey = recipientPubkey
        self.comment = comment
        self.tags = tags
    }
}

/// Payment methods
public enum NDKPaymentMethod: String {
    case lightning = "nip57"
    case nutzap = "nip61"
}

