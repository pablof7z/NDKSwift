import Foundation

/// Concrete implementation of Nostr Wallet Connect (NWC) wallet
public actor NDKNWCWallet: NDKNWCWalletProtocol {
    // MARK: - Properties
    
    public let ndk: NDK
    nonisolated public let connectionURI: NWCConnectionURI
    
    private let signer: NDKSigner
    private let requestBuilder: NWCRequestBuilder
    nonisolated private let responseHandler: NWCResponseHandler
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
            relayURLs: Array(self.connectionURI.normalizedRelayURLs())
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
            relayURLs: Array(connectionURI.normalizedRelayURLs())
        )
    }
    
    // MARK: - Connection Management
    
    public func connect() async throws {
        _status = .connecting
        print("[NWC] Starting connection...")
        
        do {
            // Fetch wallet info to verify connection
            print("[NWC] Fetching wallet info...")
            let info = try await getInfo()
            print("[NWC] Got wallet info: \(info.methods.count) methods")
            _walletInfo = info
            _status = .connected
        } catch {
            print("[NWC] Connection error: \(error)")
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
        
        // Use the new method that subscribes before publishing
        return try await responseHandler.executeRequestAndWaitForResponse(
            event: event,
            responseType: PayInvoiceResponse.self
        )
    }
    
    public func multiPayInvoice(_ invoices: [MultiPayInvoiceRequest.PayableInvoice]) async throws -> [String: Result<PayInvoiceResponse, NDKError>] {
        try await ensureConnected()
        
        let request = MultiPayInvoiceRequest(invoices: invoices)
        let event = try await requestBuilder.buildMultiPayInvoiceRequest(request)
        
        // Publish request
        _ = try await ndk.publish(event)
        
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
        
        // Use the new method that subscribes before publishing
        return try await responseHandler.executeRequestAndWaitForResponse(
            event: event,
            responseType: PayKeysendResponse.self
        )
    }
    
    public func multiPayKeysend(_ keysends: [MultiPayKeysendRequest.PayableKeysend]) async throws -> [String: Result<PayKeysendResponse, NDKError>] {
        try await ensureConnected()
        
        let request = MultiPayKeysendRequest(keysends: keysends)
        let event = try await requestBuilder.buildMultiPayKeysendRequest(request)
        
        // Publish request
        _ = try await ndk.publish(event)
        
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
        
        // Use the new method that subscribes before publishing
        return try await responseHandler.executeRequestAndWaitForResponse(
            event: event,
            responseType: MakeInvoiceResponse.self
        )
    }
    
    public func lookupInvoice(paymentHash: String? = nil, invoice: String? = nil) async throws -> Transaction {
        try await ensureConnected()
        
        guard paymentHash != nil || invoice != nil else {
            throw NDKError.invalidInput(message: "Missing required parameter: paymentHash or invoice")
        }
        
        let request = LookupInvoiceRequest(paymentHash: paymentHash, invoice: invoice)
        let event = try await requestBuilder.buildLookupInvoiceRequest(request)
        
        // Use the new method that subscribes before publishing
        return try await responseHandler.executeRequestAndWaitForResponse(
            event: event,
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
        
        // Use the new method that subscribes before publishing
        let response = try await responseHandler.executeRequestAndWaitForResponse(
            event: event,
            responseType: ListTransactionsResponse.self
        )
        
        return response.transactions
    }
    
    // MARK: - Balance & Info Methods
    
    private func fetchBalance() async throws -> GetBalanceResponse {
        try await ensureConnected()
        
        // Check cache
        if let cachedBalance = _cachedBalance,
           let lastCheck = _lastBalanceCheck,
           Date().timeIntervalSince(lastCheck) < balanceCacheDuration {
            return GetBalanceResponse(balance: cachedBalance)
        }
        
        let event = try await requestBuilder.buildGetBalanceRequest()
        
        // Use the new method that subscribes before publishing
        let eventId = await event.id ?? "nil"
        print("[NWC] Executing get_balance request with ID: \(eventId)")
        let response = try await responseHandler.executeRequestAndWaitForResponse(
            event: event,
            responseType: GetBalanceResponse.self
        )
        print("[NWC] Received balance response: \(response.balance) msat")
        
        // Update cache
        _cachedBalance = response.balance
        _lastBalanceCheck = Date()
        
        return response
    }
    
    /// Implementation of NDKWallet.getBalance() -> Int64
    /// Returns balance in satoshis (converts from millisatoshis)
    public func getBalance() async throws -> Int64 {
        let response = try await fetchBalance()
        return response.balance / 1000  // Convert msat to sats
    }
    
    /// NWC-specific getBalance that returns full response
    public func getBalance() async throws -> GetBalanceResponse {
        return try await fetchBalance()
    }
    
    public func getInfo() async throws -> GetInfoResponse {
        print("[NWC] Building get_info request...")
        let event = try await requestBuilder.buildGetInfoRequest()
        let eventId = await event.id ?? "nil"
        print("[NWC] Request event ID: \(eventId)")
        
        // Use the new method that subscribes before publishing
        print("[NWC] Executing get_info request...")
        return try await responseHandler.executeRequestAndWaitForResponse(
            event: event,
            responseType: GetInfoResponse.self
        )
    }
    
    // MARK: - Notifications
    
    public nonisolated func notifications() -> AsyncStream<NWCNotification<PaymentNotification>> {
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
            throw NDKError.connectionFailed(relay: connectionURI.relayURLs.joined(separator: ", "), message: "Wallet not connected")
        case .error(let message):
            throw NDKError.walletError(message: "Wallet connection error: \(message)")
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
