import Foundation

/// Protocol for Nostr Wallet Connect (NWC) wallets
/// Extends the base NDKWallet with NWC-specific functionality
public protocol NDKNWCWalletProtocol: NDKWallet {
    /// The connection URI used to establish the wallet connection
    var connectionURI: NWCConnectionURI { get }
    
    /// Current connection status
    var status: NWCConnectionStatus { get async }
    
    /// Cached wallet information
    var walletInfo: GetInfoResponse? { get async }
    
    /// Initialize the wallet and establish connection
    func connect() async throws
    
    /// Disconnect from the wallet service
    func disconnect() async
    
    // MARK: - NWC Specific Methods
    
    /// Pay a lightning invoice with optional amount override
    func payInvoice(_ invoice: String, amount: Int64?) async throws -> PayInvoiceResponse
    
    /// Pay multiple invoices in a batch
    func multiPayInvoice(_ invoices: [MultiPayInvoiceRequest.PayableInvoice]) async throws -> [String: Result<PayInvoiceResponse, NWCError>]
    
    /// Send a keysend payment
    func payKeysend(amount: Int64, pubkey: String, preimage: String?, tlvRecords: [PayKeysendRequest.TLVRecord]?) async throws -> PayKeysendResponse
    
    /// Send multiple keysend payments
    func multiPayKeysend(_ keysends: [MultiPayKeysendRequest.PayableKeysend]) async throws -> [String: Result<PayKeysendResponse, NWCError>]
    
    /// Create a new invoice
    func makeInvoice(amount: Int64?, description: String?, descriptionHash: String?, expiry: Int?) async throws -> MakeInvoiceResponse
    
    /// Look up an invoice by payment hash or invoice string
    func lookupInvoice(paymentHash: String?, invoice: String?) async throws -> Transaction
    
    /// List transactions with optional filters
    func listTransactions(from: Date?, until: Date?, limit: Int?, offset: Int?, unpaid: Bool?, type: TransactionType?) async throws -> [Transaction]
    
    /// Get detailed wallet information
    func getInfo() async throws -> GetInfoResponse
    
    /// Subscribe to wallet notifications (payment_received, payment_sent)
    func notifications() -> AsyncStream<NWCNotification<PaymentNotification>>
}

/// Connection status for NWC wallets
public enum NWCConnectionStatus: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)
}

// MARK: - Default Implementations

extension NDKNWCWalletProtocol {
    /// Default implementation of NDKWallet.pay using NWC payInvoice
    public func pay(_ request: NDKPaymentRequest) async throws -> NDKPaymentConfirmation {
        // For NWC, we need to get the invoice from somewhere
        // This is a simplified implementation - in practice you'd need to fetch the invoice
        throw NDKError.runtime("NWC_NOT_IMPLEMENTED", "Direct payment requests not supported. Use payInvoice with a bolt11 invoice.")
    }
    
    /// Default implementation of NDKWallet.getBalance
    public func getBalance() async throws -> Int64 {
        let response = try await getBalance()
        return response.balance
    }
    
    /// Default implementation of NDKWallet.createInvoice
    public func createInvoice(amount: Int64, description: String?) async throws -> String {
        let response = try await makeInvoice(amount: amount, description: description, descriptionHash: nil, expiry: nil)
        guard let invoice = response.invoice else {
            throw NWCError(code: .internal, message: "No invoice returned from wallet service")
        }
        return invoice
    }
    
    /// Default implementation of NDKWallet.supports
    public func supports(method: NDKPaymentMethod) -> Bool {
        return method == .nwc || method == .lightning
    }
}

// MARK: - Convenience Methods

extension NDKNWCWalletProtocol {
    /// Check if wallet is connected
    public var isConnected: Bool {
        get async {
            if case .connected = await status {
                return true
            }
            return false
        }
    }
    
    /// Check if wallet supports a specific NWC method
    public func supportsMethod(_ method: NWCMethod) async -> Bool {
        guard let info = await walletInfo else { return false }
        return info.methods.contains(method.rawValue)
    }
    
    /// Check if wallet supports a specific notification type
    public func supportsNotification(_ type: NWCNotificationType) async -> Bool {
        guard let info = await walletInfo,
              let notifications = info.notifications else { return false }
        return notifications.contains(type.rawValue)
    }
    
    /// Convert Unix timestamp to Date
    public func listTransactions(from: Int64?, until: Int64?, limit: Int?, offset: Int?, unpaid: Bool?, type: TransactionType?) async throws -> [Transaction] {
        let fromDate = from.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        let untilDate = until.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        return try await listTransactions(from: fromDate, until: untilDate, limit: limit, offset: offset, unpaid: unpaid, type: type)
    }
}