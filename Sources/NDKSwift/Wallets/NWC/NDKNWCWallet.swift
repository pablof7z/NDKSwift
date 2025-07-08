import Foundation

/// Concrete implementation of Nostr Wallet Connect (NWC) wallet
public actor NDKNWCWallet: NDKNWCWalletProtocol {
    // MARK: - Properties
    
    public let ndk: NDK
    public let connectionURI: NWCConnectionURI
    
    private let signer: NDKSigner
    private let requestBuilder: NWCRequestBuilder
    private let responseHandler: NWCResponseHandler
    private var _status: NWCConnectionStatus = .disconnected
    private var _walletInfo: GetInfoResponse?
    private var _cachedBalance: Int64?
    private var _lastBalanceCheck: Date?
    private let balanceCacheDuration: TimeInterval = 30 // 30 seconds
    
    // MARK: - Computed Properties
    
    public var status: NWCConnectionStatus {
        return _status
    }
    
    public var walletInfo: GetInfoResponse? {
        return _walletInfo
    }
    
    // MARK: - Initialization
    
    /// Initialize with a connection URI string
    public init(ndk: NDK, connectionURI: String) async throws {
        self.ndk = ndk
        self.connectionURI = try NWCConnectionURI(uri: connectionURI)
        self.signer = try self.connectionURI.createSigner()
        self.requestBuilder = NWCRequestBuilder(
            ndk: ndk,
            walletPubkey: self.connectionURI.walletPubkey,
            signer: signer
        )
        self.responseHandler = NWCResponseHandler(
            ndk: ndk,
            signer: signer,
            relayURLs: self.connectionURI.normalizedRelayURLs()
        )
    }
    
    /// Initialize with a parsed connection URI
    public init(ndk: NDK, connectionURI: NWCConnectionURI) async throws {
        self.ndk = ndk
        self.connectionURI = connectionURI
        self.signer = try connectionURI.createSigner()
        self.requestBuilder = NWCRequestBuilder(
            ndk: ndk,
            walletPubkey: connectionURI.walletPubkey,
            signer: signer
        )
        self.responseHandler = NWCResponseHandler(
            ndk: ndk,
            signer: signer,
            relayURLs: connectionURI.normalizedRelayURLs()
        )
    }
    
    // MARK: - Connection Management
    
    public func connect() async throws {
        _status = .connecting
        
        do {
            // Fetch wallet info to verify connection
            let info = try await getInfo()
            _walletInfo = info
            _status = .connected
        } catch {
            _status = .error(error.localizedDescription)
            throw error
        }
    }
    
    public func disconnect() async {
        _status = .disconnected
        _walletInfo = nil
        _cachedBalance = nil
        _lastBalanceCheck = nil
    }
    
    // MARK: - Payment Methods
    
    public func payInvoice(_ invoice: String, amount: Int64? = nil) async throws -> PayInvoiceResponse {
        try await ensureConnected()
        
        let request = PayInvoiceRequest(invoice: invoice, amount: amount)
        let event = try await requestBuilder.buildPayInvoiceRequest(request)
        
        // Publish request
        try await ndk.publish(event, to: connectionURI.normalizedRelayURLs())
        
        // Wait for response
        return try await responseHandler.waitForResponse(
            requestId: event.id!,
            responseType: PayInvoiceResponse.self
        )
    }
    
    public func multiPayInvoice(_ invoices: [MultiPayInvoiceRequest.PayableInvoice]) async throws -> [String: Result<PayInvoiceResponse, NWCError>] {
        try await ensureConnected()
        
        let request = MultiPayInvoiceRequest(invoices: invoices)
        let event = try await requestBuilder.buildMultiPayInvoiceRequest(request)
        
        // Publish request
        try await ndk.publish(event, to: connectionURI.normalizedRelayURLs())
        
        // Wait for multiple responses
        return try await responseHandler.waitForMultipleResponses(
            requestId: event.id!,
            responseType: PayInvoiceResponse.self,
            expectedCount: invoices.count
        )
    }
    
    public func payKeysend(amount: Int64, pubkey: String, preimage: String? = nil, tlvRecords: [PayKeysendRequest.TLVRecord]? = nil) async throws -> PayKeysendResponse {
        try await ensureConnected()
        
        let request = PayKeysendRequest(
            amount: amount,
            pubkey: pubkey,
            preimage: preimage,
            tlvRecords: tlvRecords
        )
        let event = try await requestBuilder.buildPayKeysendRequest(request)
        
        // Publish request
        try await ndk.publish(event, to: connectionURI.normalizedRelayURLs())
        
        // Wait for response
        return try await responseHandler.waitForResponse(
            requestId: event.id!,
            responseType: PayKeysendResponse.self
        )
    }
    
    public func multiPayKeysend(_ keysends: [MultiPayKeysendRequest.PayableKeysend]) async throws -> [String: Result<PayKeysendResponse, NWCError>] {
        try await ensureConnected()
        
        let request = MultiPayKeysendRequest(keysends: keysends)
        let event = try await requestBuilder.buildMultiPayKeysendRequest(request)
        
        // Publish request
        try await ndk.publish(event, to: connectionURI.normalizedRelayURLs())
        
        // Wait for multiple responses
        return try await responseHandler.waitForMultipleResponses(
            requestId: event.id!,
            responseType: PayKeysendResponse.self,
            expectedCount: keysends.count
        )
    }
    
    // MARK: - Invoice Methods
    
    public func makeInvoice(amount: Int64? = nil, description: String? = nil, descriptionHash: String? = nil, expiry: Int? = nil) async throws -> MakeInvoiceResponse {
        try await ensureConnected()
        
        let request = MakeInvoiceRequest(
            amount: amount,
            description: description,
            descriptionHash: descriptionHash,
            expiry: expiry
        )
        let event = try await requestBuilder.buildMakeInvoiceRequest(request)
        
        // Publish request
        try await ndk.publish(event, to: connectionURI.normalizedRelayURLs())
        
        // Wait for response
        return try await responseHandler.waitForResponse(
            requestId: event.id!,
            responseType: MakeInvoiceResponse.self
        )
    }
    
    public func lookupInvoice(paymentHash: String? = nil, invoice: String? = nil) async throws -> Transaction {
        try await ensureConnected()
        
        guard paymentHash != nil || invoice != nil else {
            throw NWCError.missingRequiredParameter("paymentHash or invoice")
        }
        
        let request = LookupInvoiceRequest(paymentHash: paymentHash, invoice: invoice)
        let event = try await requestBuilder.buildLookupInvoiceRequest(request)
        
        // Publish request
        try await ndk.publish(event, to: connectionURI.normalizedRelayURLs())
        
        // Wait for response
        return try await responseHandler.waitForResponse(
            requestId: event.id!,
            responseType: Transaction.self
        )
    }
    
    // MARK: - Transaction Methods
    
    public func listTransactions(from: Date? = nil, until: Date? = nil, limit: Int? = nil, offset: Int? = nil, unpaid: Bool? = nil, type: TransactionType? = nil) async throws -> [Transaction] {
        try await ensureConnected()
        
        let request = ListTransactionsRequest(
            from: from.map { Int64($0.timeIntervalSince1970) },
            until: until.map { Int64($0.timeIntervalSince1970) },
            limit: limit,
            offset: offset,
            unpaid: unpaid,
            type: type
        )
        let event = try await requestBuilder.buildListTransactionsRequest(request)
        
        // Publish request
        try await ndk.publish(event, to: connectionURI.normalizedRelayURLs())
        
        // Wait for response
        let response = try await responseHandler.waitForResponse(
            requestId: event.id!,
            responseType: ListTransactionsResponse.self
        )
        
        return response.transactions
    }
    
    // MARK: - Balance & Info Methods
    
    public func getBalance() async throws -> GetBalanceResponse {
        try await ensureConnected()
        
        // Check cache
        if let cachedBalance = _cachedBalance,
           let lastCheck = _lastBalanceCheck,
           Date().timeIntervalSince(lastCheck) < balanceCacheDuration {
            return GetBalanceResponse(balance: cachedBalance)
        }
        
        let event = try await requestBuilder.buildGetBalanceRequest()
        
        // Publish request
        try await ndk.publish(event, to: connectionURI.normalizedRelayURLs())
        
        // Wait for response
        let response = try await responseHandler.waitForResponse(
            requestId: event.id!,
            responseType: GetBalanceResponse.self
        )
        
        // Update cache
        _cachedBalance = response.balance
        _lastBalanceCheck = Date()
        
        return response
    }
    
    public func getInfo() async throws -> GetInfoResponse {
        let event = try await requestBuilder.buildGetInfoRequest()
        
        // Publish request
        try await ndk.publish(event, to: connectionURI.normalizedRelayURLs())
        
        // Wait for response
        return try await responseHandler.waitForResponse(
            requestId: event.id!,
            responseType: GetInfoResponse.self
        )
    }
    
    // MARK: - Notifications
    
    public func notifications() -> AsyncStream<NWCNotification<PaymentNotification>> {
        return responseHandler.subscribeToNotifications()
    }
    
    // MARK: - Private Helpers
    
    private func ensureConnected() async throws {
        switch _status {
        case .connected:
            return
        case .disconnected:
            try await connect()
        case .connecting:
            // Wait a bit for connection to complete
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            if case .connected = _status {
                return
            }
            throw NWCError.connectionFailed(url: connectionURI.relayURLs.joined(separator: ", "))
        case .error(let message):
            throw NWCError(code: .internal, message: "Wallet connection error: \(message)")
        }
    }
}

// MARK: - Convenience Factory

extension NDK {
    /// Create an NWC wallet from a connection URI
    public func createNWCWallet(connectionURI: String) async throws -> NDKNWCWallet {
        let wallet = try await NDKNWCWallet(ndk: self, connectionURI: connectionURI)
        try await wallet.connect()
        return wallet
    }
}