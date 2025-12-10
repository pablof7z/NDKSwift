import Foundation
import SwiftUI
import NDKSwift

@MainActor
@Observable
final class SparkWalletManager {
    public private(set) var connectionStatus: SparkConnectionStatus = .disconnected
    public private(set) var isLoading = false
    public var error: String?

    // Fiat display preferences
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

    public init(ndk: NDK) {
        self.ndk = ndk
        self.preferredCurrency = UserDefaults.standard.string(forKey: "spark_fiat_currency") ?? "USD"
        self.showFiatAsPrimary = UserDefaults.standard.bool(forKey: "spark_show_fiat_primary")
    }

    // MARK: - Wallet Access

    public var sparkWallet: SparkWallet? {
        wallet
    }

    // MARK: - Connection Management

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

        if clearMnemonic {
            KeychainService.delete(for: .sparkMnemonic)
        }
    }

    /// Check if wallet has stored mnemonic (can restore)
    public var hasSavedWallet: Bool {
        KeychainService.exists(for: .sparkMnemonic)
    }

    /// Get the stored mnemonic for backup purposes
    public func getMnemonic() -> String? {
        KeychainService.load(for: .sparkMnemonic)
    }

    // MARK: - Fiat Rate

    /// Refresh the fiat exchange rate
    private func refreshFiatRate() async {
        guard let wallet = wallet else { return }

        do {
            fiatRate = try await wallet.getFiatRate(currency: preferredCurrency)
        } catch {
            // Silent fail - fiat display is optional
        }
    }

    // MARK: - Private Helpers

    private func setupWallet(_ wallet: SparkWallet) async {
        connectionStatus = .connected

        // Register with ZapManager for payments
        await ndk.zapManager.register(provider: wallet)

        // Fetch initial fiat rate
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
            break
        case .paymentSucceeded(let amount):
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
