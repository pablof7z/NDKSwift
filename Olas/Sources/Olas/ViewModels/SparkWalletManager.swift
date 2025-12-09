import Foundation
import SwiftUI
import NDKSwift
import Security

@MainActor
public final class SparkWalletManager: ObservableObject {
    @Published public private(set) var connectionStatus: SparkConnectionStatus = .disconnected
    @Published public private(set) var balance: Int64 = 0
    @Published public private(set) var lightningAddress: String?
    @Published public private(set) var isLoading = false
    @Published public private(set) var payments: [SparkPayment] = []
    @Published public var error: String?

    private var wallet: SparkWallet?
    private var eventTask: Task<Void, Never>?
    private let ndk: NDK

    private let keychainService = "com.olas.spark"
    private let mnemonicAccount = "spark_mnemonic"

    public init(ndk: NDK) {
        self.ndk = ndk
    }

    deinit {
        eventTask?.cancel()
    }

    // MARK: - Public Methods

    /// Attempt to restore wallet from keychain on app launch
    public func restoreWalletIfExists() async {
        guard let mnemonic = loadMnemonicFromKeychain() else { return }

        do {
            try await connect(mnemonic: mnemonic)
        } catch {
            // Mnemonic was invalid or connection failed - clear it
            deleteMnemonicFromKeychain()
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
        try saveMnemonicToKeychain(mnemonic)

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
        try saveMnemonicToKeychain(mnemonic)

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

        if let wallet = wallet {
            try? await wallet.disconnect()
        }

        // Unregister from ZapManager
        await ndk.zapManager.unregister(providerId: "spark_wallet")

        wallet = nil
        connectionStatus = .disconnected
        balance = 0
        lightningAddress = nil

        if clearMnemonic {
            deleteMnemonicFromKeychain()
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
        loadMnemonicFromKeychain() != nil
    }

    // MARK: - Private Helpers

    private func setupWallet(_ wallet: SparkWallet) async {
        connectionStatus = .connected

        // Register with ZapManager for payments
        await ndk.zapManager.configureWithSpark(sparkWallet: wallet)

        // Fetch initial info
        await refreshInfo()

        // Start listening for events
        startEventListener(wallet)
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
            // Could show notification
            print("[Spark] Payment succeeded: \(amount) sats")
        case .paymentFailed(let reason):
            error = "Payment failed: \(reason)"
        case .paymentPending(let amount):
            print("[Spark] Payment pending: \(amount) sats")
        }
    }

    // MARK: - Keychain

    private func saveMnemonicToKeychain(_ mnemonic: String) throws {
        guard let data = mnemonic.data(using: .utf8) else {
            throw SparkWalletError.invalidMnemonic
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: mnemonicAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        // Delete existing item first
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SparkWalletError.connectionFailed("Failed to save to keychain: \(status)")
        }
    }

    private func loadMnemonicFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: mnemonicAccount,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let mnemonic = String(data: data, encoding: .utf8) else {
            return nil
        }

        return mnemonic
    }

    private func deleteMnemonicFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: mnemonicAccount
        ]

        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Connection Status

public enum SparkConnectionStatus: Equatable {
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
