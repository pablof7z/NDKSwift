import Foundation
import NDKSwift
import BreezSdkSpark
import BIP39

/// SparkWallet provides a self-custodial Lightning wallet using the Breez Spark SDK.
/// It implements NDKPaymentProvider to integrate with NDKSwift's zap infrastructure.
public actor SparkWallet: NDKPaymentProvider {

    // MARK: - NDKPaymentProvider Conformance

    public nonisolated var id: String { "spark_wallet" }
    public nonisolated var displayName: String { "Spark Wallet" }

    // MARK: - Properties

    private let logPrefix = "[Spark]"
    private var sdk: BreezSdk?
    private let apiKey: String
    private let storagePath: String
    private var eventListenerId: String?

    /// Event stream for wallet events
    public nonisolated let events: AsyncStream<SparkWalletEvent>
    private nonisolated let eventContinuation: AsyncStream<SparkWalletEvent>.Continuation

    // MARK: - Initialization

    /// Initialize SparkWallet with API key and optional storage path
    /// - Parameters:
    ///   - apiKey: Breez API key (request at https://breez.technology/request-api-key)
    ///   - storagePath: Optional custom storage path. Defaults to app's document directory.
    public init(apiKey: String, storagePath: String? = nil) {
        self.apiKey = apiKey
        self.storagePath = storagePath ?? SparkWallet.defaultStoragePath()

        // Create event stream
        var continuation: AsyncStream<SparkWalletEvent>.Continuation!
        self.events = AsyncStream { continuation = $0 }
        self.eventContinuation = continuation
    }

    deinit {
        eventContinuation.finish()
    }

    // MARK: - Connection

    /// Connect to Spark network with existing mnemonic
    /// - Parameter mnemonic: 12 or 24 word BIP39 mnemonic
    public func connect(mnemonic: String) async throws {
        guard sdk == nil else {
            throw SparkWalletError.alreadyConnected
        }

        NDKLogger.log(.info, category: .wallet, "\(logPrefix) Starting connection...")

        // Create storage directory if needed
        try FileManager.default.createDirectory(
            atPath: storagePath,
            withIntermediateDirectories: true
        )

        // Initialize logging (optional, ignore errors)
        try? BreezSdkSpark.initLogging(logDir: storagePath, appLogger: nil, logFilter: nil)

        // Build connect request
        var config = BreezSdkSpark.defaultConfig(network: .mainnet)
        config.apiKey = apiKey

        let seed = Seed.mnemonic(mnemonic: mnemonic, passphrase: nil)
        let request = ConnectRequest(config: config, seed: seed, storageDir: storagePath)

        // Connect to network
        NDKLogger.log(.debug, category: .wallet, "\(logPrefix) Connecting to Spark network...")
        sdk = try await BreezSdkSpark.connect(request: request)

        // Start listening for events
        await startEventListener()

        NDKLogger.log(.info, category: .wallet, "\(logPrefix) Connected successfully")
        eventContinuation.yield(.connected)
    }

    /// Create a new wallet with fresh mnemonic
    /// - Returns: The generated mnemonic (store securely!)
    public func createWallet() async throws -> String {
        let mnemonic = try generateBIP39Mnemonic()
        try await connect(mnemonic: mnemonic)
        return mnemonic
    }

    /// Disconnect from Spark network
    public func disconnect() async throws {
        guard let sdk = sdk else { return }

        if let listenerId = eventListenerId {
            try await sdk.removeEventListener(id: listenerId)
            eventListenerId = nil
        }

        try await sdk.disconnect()
        self.sdk = nil

        eventContinuation.yield(.disconnected)
    }

    // MARK: - NDKPaymentProvider Implementation

    public func isAvailable() async -> Bool {
        return sdk != nil
    }

    public func canFulfill(_ request: PaymentRequest) async -> Bool {
        guard sdk != nil else { return false }

        // SparkWallet can only fulfill Lightning invoice requests
        guard request is LightningInvoiceRequest else {
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
        guard let sdk = sdk else {
            throw PaymentError.providerNotAvailable
        }

        guard let lightningRequest = request as? LightningInvoiceRequest else {
            throw PaymentError.cannotFulfillRequest
        }

        // Check balance before attempting payment
        if let balance = try? await getBalance(),
           balance < lightningRequest.amountSats {
            throw PaymentError.insufficientBalance(
                available: balance,
                required: lightningRequest.amountSats
            )
        }

        NDKLogger.log(.debug, category: .wallet, "\(logPrefix) Preparing payment for \(lightningRequest.amountSats) sats")

        // Prepare payment first
        let prepareRequest = PrepareSendPaymentRequest(
            paymentRequest: lightningRequest.invoice,
            amount: nil // Amount is in the invoice
        )

        let prepareResponse = try await sdk.prepareSendPayment(request: prepareRequest)

        NDKLogger.log(.debug, category: .wallet, "\(logPrefix) Executing payment...")

        // Execute payment
        let sendRequest = SendPaymentRequest(prepareResponse: prepareResponse)
        let response = try await sdk.sendPayment(request: sendRequest)

        // U128 is BInt (BigInt) - convert via string for Int64
        let amountSats = Int64(prepareResponse.amount.asString(radix: 10)) ?? 0
        NDKLogger.log(.info, category: .wallet, "\(logPrefix) Payment succeeded: \(amountSats) sats")

        // Convert to PaymentConfirmation
        return LightningPaymentConfirmation(
            amountSats: amountSats,
            timestamp: Date(),
            preimage: response.payment.id, // Use payment ID as preimage fallback
            paymentHash: response.payment.id,
            feePaid: 0 // Fees included in amount
        )
    }

    public func getBalance() async throws -> Int64? {
        guard let sdk = sdk else { return nil }

        let info = try await sdk.getInfo(request: BreezSdkSpark.GetInfoRequest(ensureSynced: nil))
        return Int64(info.balanceSats)
    }

    // MARK: - Receiving

    /// Generate a Lightning invoice to receive payment
    /// - Parameters:
    ///   - amountSats: Amount in satoshis (nil for any amount)
    ///   - description: Optional description for the invoice
    /// - Returns: BOLT11 invoice string
    public func createInvoice(amountSats: Int64?, description: String?) async throws -> String {
        guard let sdk = sdk else {
            throw SparkWalletError.notConnected
        }

        let paymentMethod: ReceivePaymentMethod
        if let amount = amountSats {
            paymentMethod = .sparkInvoice(
                amount: U128(amount),
                tokenIdentifier: nil,
                expiryTime: nil,
                description: description,
                senderPublicKey: nil
            )
        } else {
            paymentMethod = .sparkAddress
        }

        let request = ReceivePaymentRequest(paymentMethod: paymentMethod)
        let response = try await sdk.receivePayment(request: request)
        return response.paymentRequest
    }

    /// Get the wallet's Lightning address (if registered)
    public func getLightningAddress() async throws -> String? {
        guard let sdk = sdk else {
            throw SparkWalletError.notConnected
        }

        let info = try await sdk.getLightningAddress()
        return info?.lightningAddress
    }

    /// Register a Lightning address
    /// - Parameter username: Desired username (will become username@spark.money)
    public func registerLightningAddress(_ username: String) async throws {
        guard let sdk = sdk else {
            throw SparkWalletError.notConnected
        }

        let request = RegisterLightningAddressRequest(username: username)
        _ = try await sdk.registerLightningAddress(request: request)
    }

    // MARK: - Wallet Info

    /// Get detailed wallet information
    public func getInfo() async throws -> SparkWalletInfo {
        guard let sdk = sdk else {
            throw SparkWalletError.notConnected
        }

        let info = try await sdk.getInfo(request: BreezSdkSpark.GetInfoRequest(ensureSynced: nil))

        return SparkWalletInfo(
            balanceSats: Int64(info.balanceSats),
            pendingReceiveSats: 0,
            pendingSendSats: 0,
            sparkAddress: nil
        )
    }

    /// Sync wallet with network (uses getInfo with ensureSynced)
    public func sync() async throws {
        guard let sdk = sdk else {
            throw SparkWalletError.notConnected
        }

        // Use getInfo with ensureSynced: true to trigger sync
        _ = try await sdk.getInfo(request: BreezSdkSpark.GetInfoRequest(ensureSynced: true))
    }

    // MARK: - Transaction History

    /// List payments with optional filters
    public func listPayments(
        typeFilter: [SparkPaymentType]? = nil,
        statusFilter: [SparkPaymentStatus]? = nil,
        limit: UInt32? = 50,
        offset: UInt32? = nil
    ) async throws -> [SparkPayment] {
        guard let sdk = sdk else {
            throw SparkWalletError.notConnected
        }

        let sdkTypeFilter: [PaymentType]? = typeFilter?.map { type in
            switch type {
            case .send: return .send
            case .receive: return .receive
            }
        }

        let sdkStatusFilter: [PaymentStatus]? = statusFilter?.map { status in
            switch status {
            case .pending: return .pending
            case .completed: return .completed
            case .failed: return .failed
            }
        }

        let request = ListPaymentsRequest(
            typeFilter: sdkTypeFilter,
            statusFilter: sdkStatusFilter,
            assetFilter: nil,
            sparkHtlcStatusFilter: nil,
            fromTimestamp: nil,
            toTimestamp: nil,
            offset: offset,
            limit: limit,
            sortAscending: false
        )

        let response = try await sdk.listPayments(request: request)

        return response.payments.map { payment in
            SparkPayment(from: payment)
        }
    }

    // MARK: - Input Parsing

    /// Parse a payment input string (invoice, address, LNURL, etc.)
    public func parseInput(_ input: String) async throws -> SparkParsedInput {
        guard let sdk = sdk else {
            throw SparkWalletError.notConnected
        }

        let parsed = try await sdk.parse(input: input)

        switch parsed {
        case .bolt11Invoice(let details):
            let amountSats = details.amountMsat.map { Int64($0) / 1000 }
            return .bolt11Invoice(SparkBolt11Details(
                invoice: details.invoice.bolt11,
                amountSats: amountSats,
                description: details.description,
                expiry: details.expiry,
                payeePubkey: details.payeePubkey
            ))

        case .bitcoinAddress(let details):
            return .bitcoinAddress(SparkBitcoinAddressDetails(
                address: details.address,
                network: String(describing: details.network),
                amountSats: nil
            ))

        case .lnurlPay(let details):
            let minSats = Int64(details.minSendable) / 1000
            let maxSats = Int64(details.maxSendable) / 1000
            return .lnurlPay(SparkLnurlPayDetails(
                domain: details.domain,
                minSendableSats: minSats,
                maxSendableSats: maxSats,
                metadata: details.metadataStr,
                lightningAddress: details.address
            ))

        case .lnurlWithdraw(let details):
            let minSats = Int64(details.minWithdrawable) / 1000
            let maxSats = Int64(details.maxWithdrawable) / 1000
            return .lnurlWithdraw(SparkLnurlWithdrawDetails(
                domain: details.callback,
                minWithdrawableSats: minSats,
                maxWithdrawableSats: maxSats,
                description: details.defaultDescription
            ))

        case .sparkAddress(let details):
            return .sparkAddress(SparkAddressDetails(address: details.address))

        case .sparkInvoice(let details):
            let amountSats = details.amount.flatMap { Int64($0.asString(radix: 10)) } ?? 0
            return .sparkInvoice(SparkInvoiceDetails(
                invoice: details.invoice,
                amountSats: amountSats
            ))

        case .url(let url):
            return .url(url)

        case .lnurlAuth, .lightningAddress, .bolt12Invoice, .bolt12Offer, .silentPaymentAddress, .bip21, .bolt12InvoiceRequest:
            throw SparkWalletError.unsupportedPaymentType
        }
    }

    // MARK: - Payment Preparation

    /// Prepare a payment to get fee estimates before sending
    public func preparePayment(input: String, amount: Int64?) async throws -> SparkPreparedPayment {
        guard let sdk = sdk else {
            throw SparkWalletError.notConnected
        }

        let amountU128: U128? = amount.map { U128($0) }
        let request = PrepareSendPaymentRequest(paymentRequest: input, amount: amountU128)
        let response = try await sdk.prepareSendPayment(request: request)

        let totalAmountSats = Int64(response.amount.asString(radix: 10)) ?? 0

        return SparkPreparedPayment(
            destination: input,
            amountSats: totalAmountSats,
            feeSats: 0, // Fees included in total amount in SDK v0.5.2
            totalSats: totalAmountSats,
            prepareResponse: response
        )
    }

    /// Send a prepared payment
    public func sendPreparedPayment(_ prepared: SparkPreparedPayment) async throws -> PaymentConfirmation {
        guard let sdk = sdk else {
            throw SparkWalletError.notConnected
        }

        let sendRequest = SendPaymentRequest(prepareResponse: prepared.prepareResponse)
        let response = try await sdk.sendPayment(request: sendRequest)

        return LightningPaymentConfirmation(
            amountSats: prepared.amountSats,
            timestamp: Date(),
            preimage: response.payment.id,
            paymentHash: response.payment.id,
            feePaid: prepared.feeSats
        )
    }

    // MARK: - Private Helpers

    private static func defaultStoragePath() -> String {
        let documentsPath = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first!.path
        return "\(documentsPath)/spark_wallet"
    }

    private func startEventListener() async {
        guard let sdk = sdk else { return }

        do {
            eventListenerId = try await sdk.addEventListener(listener: SparkEventHandler(continuation: eventContinuation))
        } catch {
            NDKLogger.log(.error, category: .wallet, "Failed to add Spark event listener: \(error)")
        }
    }

    private func generateBIP39Mnemonic() throws -> String {
        let mnemonic = Mnemonic(strength: 128)
        return mnemonic.phrase.joined(separator: " ")
    }
}

// MARK: - Event Handler

private class SparkEventHandler: EventListener {
    private let continuation: AsyncStream<SparkWalletEvent>.Continuation

    init(continuation: AsyncStream<SparkWalletEvent>.Continuation) {
        self.continuation = continuation
    }

    func onEvent(event: SdkEvent) async {
        switch event {
        case .paymentSucceeded(let payment):
            let amountSats = Int64(payment.amount.asString(radix: 10)) ?? 0
            continuation.yield(.paymentSucceeded(amountSats: amountSats))
        case .paymentFailed(let payment):
            let reason = "Payment failed (status: \(payment.status))"
            continuation.yield(.paymentFailed(reason: reason))
        case .paymentPending(let payment):
            let amountSats = Int64(payment.amount.asString(radix: 10)) ?? 0
            continuation.yield(.paymentPending(amountSats: amountSats))
        case .synced:
            continuation.yield(.synced)
        case .unclaimedDeposits, .claimedDeposits:
            break
        }
    }
}

// MARK: - Types

public struct SparkWalletInfo: Sendable {
    public let balanceSats: Int64
    public let pendingReceiveSats: Int64
    public let pendingSendSats: Int64
    public let sparkAddress: String?
}

public enum SparkWalletEvent: Sendable {
    case connected
    case disconnected
    case synced
    case paymentSucceeded(amountSats: Int64)
    case paymentFailed(reason: String)
    case paymentPending(amountSats: Int64)
}

public enum SparkWalletError: LocalizedError {
    case notConnected
    case alreadyConnected
    case unsupportedPaymentType
    case invalidMnemonic
    case connectionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Spark wallet is not connected"
        case .alreadyConnected:
            return "Spark wallet is already connected"
        case .unsupportedPaymentType:
            return "Unsupported payment type for Spark wallet"
        case .invalidMnemonic:
            return "Invalid mnemonic phrase"
        case .connectionFailed(let reason):
            return "Failed to connect to Spark network: \(reason)"
        }
    }
}

// MARK: - Payment Types

public enum SparkPaymentType: Sendable {
    case send
    case receive
}

public enum SparkPaymentStatus: Sendable {
    case pending
    case completed
    case failed
}

public struct SparkPayment: Identifiable, Sendable {
    public let id: String
    public let type: SparkPaymentType
    public let status: SparkPaymentStatus
    public let amountSats: Int64
    public let feeSats: Int64
    public let timestamp: Date
    public let description: String?
    public let destination: String?
    public let preimage: String?

    init(from payment: BreezSdkSpark.Payment) {
        self.id = payment.id
        self.type = payment.paymentType == .send ? .send : .receive
        self.status = {
            switch payment.status {
            case .pending: return .pending
            case .completed: return .completed
            case .failed: return .failed
            }
        }()
        self.amountSats = Int64(payment.amount.asString(radix: 10)) ?? 0
        self.feeSats = Int64(payment.fees.asString(radix: 10)) ?? 0
        self.timestamp = Date(timeIntervalSince1970: TimeInterval(payment.timestamp))

        if let details = payment.details {
            switch details {
            case .lightning(let description, let preimage, _, _, let destinationPubkey, _, _, _):
                self.description = description
                self.preimage = preimage
                self.destination = destinationPubkey
            case .spark(_, _), .token(_, _, _), .withdraw(_), .deposit(_):
                self.description = nil
                self.preimage = nil
                self.destination = nil
            }
        } else {
            self.description = nil
            self.preimage = nil
            self.destination = nil
        }
    }
}

// MARK: - Parsed Input Types

public enum SparkParsedInput: Sendable {
    case bolt11Invoice(SparkBolt11Details)
    case bitcoinAddress(SparkBitcoinAddressDetails)
    case lnurlPay(SparkLnurlPayDetails)
    case lnurlWithdraw(SparkLnurlWithdrawDetails)
    case sparkAddress(SparkAddressDetails)
    case sparkInvoice(SparkInvoiceDetails)
    case nodeId(String)
    case url(String)

    public var requiresAmount: Bool {
        switch self {
        case .bolt11Invoice(let details):
            return details.amountSats == nil
        case .bitcoinAddress(let details):
            return details.amountSats == nil
        case .lnurlPay:
            return true
        case .sparkAddress:
            return true
        case .sparkInvoice, .lnurlWithdraw, .nodeId, .url:
            return false
        }
    }

    public var embeddedAmountSats: Int64? {
        switch self {
        case .bolt11Invoice(let details):
            return details.amountSats
        case .bitcoinAddress(let details):
            return details.amountSats
        case .sparkInvoice(let details):
            return details.amountSats
        default:
            return nil
        }
    }

    public var typeDescription: String {
        switch self {
        case .bolt11Invoice: return "Lightning Invoice"
        case .bitcoinAddress: return "Bitcoin Address"
        case .lnurlPay: return "Lightning Address"
        case .lnurlWithdraw: return "LNURL Withdraw"
        case .sparkAddress: return "Spark Address"
        case .sparkInvoice: return "Spark Invoice"
        case .nodeId: return "Node ID"
        case .url: return "URL"
        }
    }
}

public struct SparkBolt11Details: Sendable {
    public let invoice: String
    public let amountSats: Int64?
    public let description: String?
    public let expiry: UInt64
    public let payeePubkey: String
}

public struct SparkBitcoinAddressDetails: Sendable {
    public let address: String
    public let network: String
    public let amountSats: Int64?
}

public struct SparkLnurlPayDetails: Sendable {
    public let domain: String
    public let minSendableSats: Int64
    public let maxSendableSats: Int64
    public let metadata: String
    public let lightningAddress: String?
}

public struct SparkLnurlWithdrawDetails: Sendable {
    public let domain: String
    public let minWithdrawableSats: Int64
    public let maxWithdrawableSats: Int64
    public let description: String
}

public struct SparkAddressDetails: Sendable {
    public let address: String
}

public struct SparkInvoiceDetails: Sendable {
    public let invoice: String
    public let amountSats: Int64
}

// MARK: - Prepared Payment

public struct SparkPreparedPayment: Sendable {
    public let destination: String
    public let amountSats: Int64
    public let feeSats: Int64
    public let totalSats: Int64
    let prepareResponse: PrepareSendPaymentResponse
}
