import Foundation
import BreezSdkSpark

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
    public let events: AsyncStream<SparkWalletEvent>
    private let eventContinuation: AsyncStream<SparkWalletEvent>.Continuation

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

        // Initialize logging
        try initLogging()

        // Build connect request
        let config = defaultConfig(network: .mainnet, apiKey: apiKey, storagePath: storagePath)
        let seed = Seed.mnemonic(mnemonic: mnemonic)
        let request = ConnectRequest(config: config, seed: seed)

        // Connect to network
        NDKLogger.log(.debug, category: .wallet, "\(logPrefix) Connecting to Spark network...")
        sdk = try await connect(request: request)

        // Start listening for events
        await startEventListener()

        NDKLogger.log(.info, category: .wallet, "\(logPrefix) Connected successfully")
        eventContinuation.yield(.connected)
    }

    /// Create a new wallet with fresh mnemonic
    /// - Returns: The generated mnemonic (store securely!)
    public func createWallet() async throws -> String {
        let mnemonic = try generateMnemonic()
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

        NDKLogger.log(.info, category: .wallet, "\(logPrefix) Payment succeeded: \(prepareResponse.amount) sats")

        // Convert to PaymentConfirmation
        return LightningPaymentConfirmation(
            amountSats: Int64(prepareResponse.amount),
            timestamp: Date(),
            preimage: response.payment.preimage ?? "",
            paymentHash: response.payment.paymentHash,
            feePaid: Int64(response.payment.feesSat ?? 0)
        )
    }

    public func getBalance() async throws -> Int64? {
        guard let sdk = sdk else { return nil }

        let info = try await sdk.getInfo(request: GetInfoRequest())
        return Int64(info.balanceSat)
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

        let request = ReceivePaymentRequest(
            paymentMethod: .lightning,
            amount: amountSats.map { UInt64($0) },
            description: description
        )

        let response = try await sdk.receivePayment(request: request)
        return response.paymentRequest
    }

    /// Get the wallet's Lightning address (if registered)
    public func getLightningAddress() async throws -> String? {
        guard let sdk = sdk else {
            throw SparkWalletError.notConnected
        }

        return try await sdk.getLightningAddress()
    }

    /// Register a Lightning address
    /// - Parameter address: Desired Lightning address (username@domain format)
    public func registerLightningAddress(_ address: String) async throws {
        guard let sdk = sdk else {
            throw SparkWalletError.notConnected
        }

        let request = RegisterLightningAddressRequest(lightningAddress: address)
        try await sdk.registerLightningAddress(request: request)
    }

    // MARK: - Wallet Info

    /// Get detailed wallet information
    public func getInfo() async throws -> SparkWalletInfo {
        guard let sdk = sdk else {
            throw SparkWalletError.notConnected
        }

        let info = try await sdk.getInfo(request: GetInfoRequest())

        return SparkWalletInfo(
            balanceSats: Int64(info.balanceSat),
            pendingReceiveSats: Int64(info.pendingReceiveSat),
            pendingSendSats: Int64(info.pendingSendSat),
            sparkAddress: info.sparkAddress
        )
    }

    /// Sync wallet with network
    public func sync() async throws {
        guard let sdk = sdk else {
            throw SparkWalletError.notConnected
        }

        try await sdk.syncWallet(request: SyncWalletRequest())
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
}

// MARK: - Event Handler

private class SparkEventHandler: EventListener {
    private let continuation: AsyncStream<SparkWalletEvent>.Continuation

    init(continuation: AsyncStream<SparkWalletEvent>.Continuation) {
        self.continuation = continuation
    }

    func onEvent(e: SdkEvent) {
        switch e {
        case .paymentSucceeded(let details):
            continuation.yield(.paymentSucceeded(amountSats: Int64(details.payment.amountSat)))
        case .paymentFailed(let details):
            continuation.yield(.paymentFailed(reason: details.payment.description ?? "Unknown error"))
        case .paymentPending(let details):
            continuation.yield(.paymentPending(amountSats: Int64(details.payment.amountSat)))
        case .synced:
            continuation.yield(.synced)
        }
    }
}

// MARK: - Types

/// Wallet information
public struct SparkWalletInfo: Sendable {
    public let balanceSats: Int64
    public let pendingReceiveSats: Int64
    public let pendingSendSats: Int64
    public let sparkAddress: String?
}

/// Wallet events
public enum SparkWalletEvent: Sendable {
    case connected
    case disconnected
    case synced
    case paymentSucceeded(amountSats: Int64)
    case paymentFailed(reason: String)
    case paymentPending(amountSats: Int64)
}

/// Spark wallet errors
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
