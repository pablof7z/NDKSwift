import Foundation

/// Connection status for NWC wallets
public enum NWCConnectionStatus: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)
}

/// Concrete implementation of Nostr Wallet Connect (NWC) wallet
public actor NDKNWCWallet: NDKPaymentProvider {
    // MARK: - Properties

    /// Log prefix constant for NWC wallet related logging
    private let logPrefix = "[NWC]"

    public let id = "nwc_wallet"
    public let displayName = "Nostr Wallet Connect"

    public let ndk: NDK
    public nonisolated let connectionURI: NWCConnectionURI

    private let signer: NDKSigner
    private let requestBuilder: NWCRequestBuilder
    private nonisolated let responseHandler: NWCResponseHandler
    private var _status: NWCConnectionStatus = .disconnected
    private var _walletInfo: GetInfoResponse?
    private var _cachedBalance: Int64?
    private var _lastBalanceCheck: Date?
    private let balanceCacheDuration: TimeInterval = NetworkConstants.timeoutStandardRequest // 30 seconds
    private var connectionTask: Task<Void, Error>?

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
        signer = try self.connectionURI.createSigner()
        requestBuilder = NWCRequestBuilder(
            ndk: ndk,
            walletPubkey: self.connectionURI.walletPubkey,
            signer: signer
        )
        responseHandler = NWCResponseHandler(
            ndk: ndk,
            signer: signer,
            relayURLs: Array(self.connectionURI.normalizedRelayURLs()),
            walletPubkey: self.connectionURI.walletPubkey,
            clientPubkey: try self.connectionURI.clientPubkey()
        )
    }

    /// Initialize with a parsed connection URI
    public init(ndk: NDK, connectionURI: NWCConnectionURI) async throws {
        self.ndk = ndk
        self.connectionURI = connectionURI
        signer = try connectionURI.createSigner()
        requestBuilder = NWCRequestBuilder(
            ndk: ndk,
            walletPubkey: connectionURI.walletPubkey,
            signer: signer
        )
        responseHandler = NWCResponseHandler(
            ndk: ndk,
            signer: signer,
            relayURLs: Array(connectionURI.normalizedRelayURLs()),
            walletPubkey: connectionURI.walletPubkey,
            clientPubkey: try connectionURI.clientPubkey()
        )
    }

    // MARK: - Connection Management

    public func connect() async throws {
        // If already connecting, wait for that connection
        if let existingTask = connectionTask {
            return try await existingTask.value
        }

        // If already connected, nothing to do
        guard _status != .connected else { return }

        _status = .connecting
        NDKLogger.log(.info, category: .wallet, "\(logPrefix) Starting connection...")

        // Store the connection task
        let task = Task {
            do {
                // First, ensure NWC relays are connected
                let nwcRelayURLs = connectionURI.normalizedRelayURLs()
                NDKLogger.log(.debug, category: .wallet, "\(logPrefix) Connecting to NWC relays: \(nwcRelayURLs)")

                // Use outbox origin to avoid polluting app relay list - these are NWC-specific relays
                for relayURL in nwcRelayURLs {
                    let relay = await ndk.addRelay(relayURL, origin: .outbox(authorPubkey: ""))

                    // Wait for relay to connect (up to 5 seconds)
                    let startTime = Date()
                    while !(await relay.isConnected) {
                        if Date().timeIntervalSince(startTime) > 5.0 {
                            throw NDKError.timeout(operation: "NWC relay connection to \(relayURL)", seconds: 5)
                        }
                        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                    }
                    NDKLogger.log(.debug, category: .wallet, "\(logPrefix) Relay \(relayURL) connected")
                }

                // Fetch wallet info to verify connection
                NDKLogger.log(.debug, category: .wallet, "\(logPrefix) Fetching wallet info...")
                let info = try await getInfo()
                NDKLogger.log(.info, category: .wallet, "\(logPrefix) Got wallet info: \(info.methods.count) methods")
                _walletInfo = info
                _status = .connected
                connectionTask = nil
            } catch {
                NDKLogger.log(.error, category: .wallet, "\(logPrefix) Connection error: \(error)")
                _status = .error(error.localizedDescription)
                connectionTask = nil
                throw error
            }
        }
        connectionTask = task

        try await task.value
    }

    public func disconnect() async {
        // Cancel any pending connection
        connectionTask?.cancel()
        connectionTask = nil

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
            requestId: event.id,
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
            requestId: event.id,
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
        let eventId = event.id
        NDKLogger.log(.debug, category: .wallet, "\(logPrefix) Executing get_balance request with ID: \(eventId)")
        let response = try await responseHandler.executeRequestAndWaitForResponse(
            event: event,
            responseType: GetBalanceResponse.self
        )
        NDKLogger.log(.debug, category: .wallet, "\(logPrefix) Received balance response: \(response.balance) msat")

        // Update cache
        _cachedBalance = response.balance
        _lastBalanceCheck = Date()

        return response
    }

    // MARK: - NDKPaymentProvider Protocol

    /// Check if NWC wallet is available
    public func isAvailable() async -> Bool {
        do {
            _ = try await getInfo()
            return true
        } catch {
            return false
        }
    }

    /// Check if NWC wallet can fulfill a payment request
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
        do {
            if let balance = try await getBalance() {
                return balance >= request.amountSats
            } else {
                // Balance unavailable, assume we can pay
                return true
            }
        } catch {
            NDKLogger.log(.warning, category: .wallet, "Failed to check NWC balance for canFulfill check: \(error.localizedDescription)")
            // If we can't check balance, assume we can pay
            return true
        }
    }

    /// Fulfill a payment request using NWC
    public func fulfill(_ request: PaymentRequest) async throws -> PaymentConfirmation {
        // NWC only handles Lightning invoices
        guard let lightningRequest = request as? LightningInvoiceRequest else {
            throw PaymentError.cannotFulfillRequest
        }

        // Check balance if needed
        do {
            if let balance = try await getBalance() {
                if balance < lightningRequest.amountSats {
                    throw PaymentError.insufficientBalance(
                        available: balance,
                        required: lightningRequest.amountSats
                    )
                }
            }
            // If balance is nil, continue with payment attempt
        } catch let error as PaymentError {
            throw error
        } catch {
            NDKLogger.log(.warning, category: .wallet, "Failed to check NWC balance before payment: \(error.localizedDescription)")
            // Continue with payment attempt even if balance check fails
        }

        // Pay the invoice using NWC
        let response = try await payInvoice(
            lightningRequest.invoice,
            amount: nil // Amount is in the invoice
        )

        // Convert NWC response to our confirmation type
        return LightningPaymentConfirmation(
            amountSats: lightningRequest.amountSats,
            timestamp: Date(),
            preimage: response.preimage,
            paymentHash: nil,
            feePaid: response.feesPaid
        )
    }

    /// Implementation of NDKPaymentProvider.getBalance() -> Int64?
    /// Returns balance in satoshis (converts from millisatoshis)
    public func getBalance() async throws -> Int64? {
        let response = try await fetchBalance()
        return PaymentConstants.millisatsToSats(response.balance)
    }

    /// NWC-specific getBalance that returns full response with millisatoshi precision
    public func getBalanceResponse() async throws -> GetBalanceResponse {
        return try await fetchBalance()
    }

    public func getInfo() async throws -> GetInfoResponse {
        NDKLogger.log(.trace, category: .wallet, "\(logPrefix) Building get_info request...")
        let event = try await requestBuilder.buildGetInfoRequest()
        let eventId = event.id
        NDKLogger.log(.trace, category: .wallet, "\(logPrefix) Request event ID: \(eventId)")

        // Use the new method that subscribes before publishing
        NDKLogger.log(.debug, category: .wallet, "\(logPrefix) Executing get_info request...")
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
            // Wait for the existing connection task
            if let task = connectionTask {
                try await task.value
            } else {
                // Shouldn't happen, but handle gracefully by attempting connection
                try await connect()
            }
        case let .error(message):
            throw NDKError.walletError(message: "Wallet connection error: \(message)")
        }
    }
}

// MARK: - Convenience Factory

public extension NDK {
    /// Create an NWC wallet from a connection URI
    func createNWCWallet(connectionURI: String) async throws -> NDKNWCWallet {
        let wallet = try await NDKNWCWallet(ndk: self, connectionURI: connectionURI)
        try await wallet.connect()
        return wallet
    }
}
