import Foundation
import SwiftUI
import NDKSwift

@MainActor
@Observable
final class SparkWalletManager {
    public private(set) var connectionStatus: SparkConnectionStatus = .disconnected
    public private(set) var balance: Int64 = 0
    public private(set) var lightningAddress: String?
    public private(set) var isLoading = false
    public private(set) var payments: [SparkPayment] = []
    public var error: String?

    // Fiat conversion
    public private(set) var fiatRate: Double?
    public var preferredCurrency: String {
        didSet {
            UserDefaults.standard.set(preferredCurrency, forKey: "spark_fiat_currency")
            Task { await refreshFiatRate() }
        }
    }
    public var showFiatAsPrimary: Bool {
        didSet {
            UserDefaults.standard.set(showFiatAsPrimary, forKey: "spark_show_fiat_primary")
        }
    }

    @ObservationIgnored
    private var wallet: SparkWallet?
    @ObservationIgnored
    private var eventTask: Task<Void, Never>?
    @ObservationIgnored
    private var fiatRefreshTask: Task<Void, Never>?
    @ObservationIgnored
    private let ndk: NDK

    // Cached formatters
    @ObservationIgnored
    private let satsFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()
    @ObservationIgnored
    private let fiatFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    public init(ndk: NDK) {
        self.ndk = ndk
        self.preferredCurrency = UserDefaults.standard.string(forKey: "spark_fiat_currency") ?? "USD"
        self.showFiatAsPrimary = UserDefaults.standard.bool(forKey: "spark_show_fiat_primary")
    }

    // MARK: - Public Methods

    /// Attempt to restore wallet from keychain on app launch
    public func restoreWalletIfExists() async {
        guard let mnemonic = KeychainService.load(for: .sparkMnemonic) else { return }

        do {
            try await connect(mnemonic: mnemonic)
        } catch {
            // Mnemonic was invalid or connection failed - clear it
            KeychainService.delete(for: .sparkMnemonic)
            self.error = error.localizedDescription
        }
    }

    /// Create a new wallet with fresh mnemonic
    /// - Returns: The mnemonic (caller must display for user to back up)
    public func createWallet() async throws -> String {
        guard wallet == nil else {
            throw SparkWalletError.alreadyConnected
        }

        isLoading = true
        connectionStatus = .connecting
        defer { isLoading = false }

        let newWallet = SparkWallet(apiKey: OlasConstants.breezApiKey)
        let mnemonic = try await newWallet.createWallet()

        // Save mnemonic to keychain
        try KeychainService.save(mnemonic, for: .sparkMnemonic)

        wallet = newWallet
        await setupWallet(newWallet)

        return mnemonic
    }

    /// Import existing wallet with mnemonic
    public func importWallet(mnemonic: String) async throws {
        guard wallet == nil else {
            throw SparkWalletError.alreadyConnected
        }

        isLoading = true
        connectionStatus = .connecting
        defer { isLoading = false }

        let newWallet = SparkWallet(apiKey: OlasConstants.breezApiKey)
        try await newWallet.connect(mnemonic: mnemonic)

        // Save mnemonic to keychain
        try KeychainService.save(mnemonic, for: .sparkMnemonic)

        wallet = newWallet
        await setupWallet(newWallet)
    }

    /// Connect with existing mnemonic (internal use for restore)
    private func connect(mnemonic: String) async throws {
        guard wallet == nil else {
            throw SparkWalletError.alreadyConnected
        }

        connectionStatus = .connecting

        let newWallet = SparkWallet(apiKey: OlasConstants.breezApiKey)
        try await newWallet.connect(mnemonic: mnemonic)

        wallet = newWallet
        await setupWallet(newWallet)
    }

    /// Disconnect and optionally clear stored mnemonic
    public func disconnect(clearMnemonic: Bool = false) async {
        isLoading = true
        defer { isLoading = false }

        eventTask?.cancel()
        eventTask = nil
        fiatRefreshTask?.cancel()
        fiatRefreshTask = nil

        if let wallet = wallet {
            try? await wallet.disconnect()
        }

        // Unregister from ZapManager
        await ndk.zapManager.unregister(providerId: "spark_wallet")

        wallet = nil
        connectionStatus = .disconnected
        fiatRate = nil
        balance = 0
        lightningAddress = nil

        if clearMnemonic {
            KeychainService.delete(for: .sparkMnemonic)
        }
    }

    /// Sync wallet with network
    public func sync() async {
        guard let wallet = wallet else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            try await wallet.sync()
            await refreshInfo()
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Refresh balance, info, and payments
    public func refreshInfo() async {
        guard let wallet = wallet else { return }

        do {
            let info = try await wallet.getInfo()
            balance = info.balanceSats
            lightningAddress = try? await wallet.getLightningAddress()

            // Fetch recent payments
            payments = try await wallet.listPayments(limit: 20)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Parse a payment input (invoice, address, etc.)
    public func parseInput(_ input: String) async throws -> SparkParsedInput {
        guard let wallet = wallet else {
            throw SparkWalletError.notConnected
        }
        return try await wallet.parseInput(input)
    }

    /// Prepare a payment to see fees before sending
    public func preparePayment(input: String, amount: Int64?) async throws -> SparkPreparedPayment {
        guard let wallet = wallet else {
            throw SparkWalletError.notConnected
        }
        return try await wallet.preparePayment(input: input, amount: amount)
    }

    /// Send a prepared payment
    public func sendPreparedPayment(_ prepared: SparkPreparedPayment) async throws {
        guard let wallet = wallet else {
            throw SparkWalletError.notConnected
        }

        isLoading = true
        defer { isLoading = false }

        _ = try await wallet.sendPreparedPayment(prepared)
        await refreshInfo()
    }

    /// Register a lightning address
    public func registerLightningAddress(_ address: String) async throws {
        guard let wallet = wallet else {
            throw SparkWalletError.notConnected
        }

        try await wallet.registerLightningAddress(address)
        lightningAddress = "\(address)@spark.money"
    }

    /// Create a Lightning invoice to receive payment
    public func createInvoice(amountSats: Int64?, description: String?) async throws -> String {
        guard let wallet = wallet else {
            throw SparkWalletError.notConnected
        }

        return try await wallet.createInvoice(amountSats: amountSats, description: description)
    }

    /// Pay a Lightning invoice
    public func pay(invoice: String) async throws {
        guard let wallet = wallet else {
            throw SparkWalletError.notConnected
        }

        isLoading = true
        defer { isLoading = false }

        let request = LightningInvoiceRequest(invoice: invoice, amountSats: 0, recipient: "unknown")
        _ = try await wallet.fulfill(request)
        await refreshInfo()
    }

    /// Check if wallet has stored mnemonic (can restore)
    public var hasSavedWallet: Bool {
        KeychainService.exists(for: .sparkMnemonic)
    }

    /// Get the stored mnemonic for backup purposes
    public func getMnemonic() -> String? {
        KeychainService.load(for: .sparkMnemonic)
    }

    // MARK: - Fiat Conversion

    /// Refresh the fiat exchange rate
    public func refreshFiatRate() async {
        guard let wallet = wallet else { return }

        do {
            fiatRate = try await wallet.getFiatRate(currency: preferredCurrency)
        } catch {
            // Silent fail - fiat display is optional
        }
    }

    /// Convert sats to fiat value
    public func satsToFiat(_ sats: Int64) -> Double? {
        guard let rate = fiatRate else { return nil }
        return SatsConverter.satsToFiat(sats, btcRate: rate)
    }

    /// Convert fiat to sats
    public func fiatToSats(_ fiat: Double) -> Int64? {
        guard let rate = fiatRate, rate > 0 else { return nil }
        return SatsConverter.fiatToSats(fiat, btcRate: rate)
    }

    /// Format sats with commas
    public func formatSats(_ sats: Int64) -> String {
        SatsConverter.formatSats(sats, formatter: satsFormatter)
    }

    /// Format fiat value with currency symbol
    public func formatFiat(_ value: Double) -> String {
        SatsConverter.formatFiat(value, currencyCode: preferredCurrency, formatter: fiatFormatter)
    }

    /// Toggle between sats and fiat as primary display
    public func togglePrimaryDisplay() {
        showFiatAsPrimary.toggle()
    }

    // MARK: - Private Helpers

    private func setupWallet(_ wallet: SparkWallet) async {
        connectionStatus = .connected

        // Register with ZapManager for payments
        await ndk.zapManager.register(provider: wallet)

        // Fetch initial info and fiat rate
        await refreshInfo()
        await refreshFiatRate()

        // Start listening for events
        startEventListener(wallet)

        // Start periodic fiat rate refresh (every 5 minutes)
        startFiatRefreshTask()
    }

    private func startFiatRefreshTask() {
        fiatRefreshTask?.cancel()
        fiatRefreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300)) // 5 minutes
                await refreshFiatRate()
            }
        }
    }

    private func startEventListener(_ wallet: SparkWallet) {
        eventTask?.cancel()
        eventTask = Task {
            for await event in wallet.events {
                await handleEvent(event)
            }
        }
    }

    private func handleEvent(_ event: SparkWalletEvent) async {
        switch event {
        case .connected:
            connectionStatus = .connected
        case .disconnected:
            connectionStatus = .disconnected
        case .synced:
            await refreshInfo()
        case .paymentSucceeded(let amount):
            await refreshInfo()
            print("[Spark] Payment succeeded: \(amount) sats")
        case .paymentFailed(let reason):
            error = "Payment failed: \(reason)"
        case .paymentPending(let amount):
            print("[Spark] Payment pending: \(amount) sats")
        }
    }
}

// MARK: - Connection Status

enum SparkConnectionStatus: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)

    public var icon: String {
        switch self {
        case .disconnected: return "bolt.slash.fill"
        case .connecting: return "bolt.horizontal.fill"
        case .connected: return "bolt.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    public var color: Color {
        switch self {
        case .disconnected: return .secondary
        case .connecting: return .orange
        case .connected: return OlasTheme.Colors.zapGold
        case .error: return .red
        }
    }

    public var description: String {
        switch self {
        case .disconnected: return "Not Connected"
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .error(let msg): return "Error: \(msg)"
        }
    }
}
