import Foundation
import Observation
@preconcurrency import NDKSwiftCore
@preconcurrency import NDKSwiftCashu
import Security

/// Wallet type options
public enum WalletType: String, CaseIterable, Sendable {
    case cashu  // NIP-60 Cashu wallet
    case nwc    // NIP-47 Nostr Wallet Connect

    public var displayName: String {
        switch self {
        case .cashu: return "Cashu"
        case .nwc: return "Wallet Connect"
        }
    }

    public var description: String {
        switch self {
        case .cashu: return "Self-custodial ecash wallet using NIP-60"
        case .nwc: return "Connect to external wallet using NIP-47"
        }
    }
}

/// Observable wallet state for Chirp
@Observable
@MainActor
public final class WalletState {
    // MARK: - Properties

    private let ndk: NDK

    /// Current wallet type
    public var walletType: WalletType {
        didSet {
            UserDefaults.standard.set(walletType.rawValue, forKey: "chirp_wallet_type")
        }
    }

    /// NIP-60 Cashu wallet instance
    public private(set) var cashuWallet: NIP60Wallet?

    /// NIP-47 NWC wallet instance
    public private(set) var nwcWallet: NDKNWCWallet?

    /// Current balance in sats
    public private(set) var balance: Int64 = 0

    /// Balance by mint (for Cashu)
    public private(set) var balancesByMint: [String: Int64] = [:]

    /// Configured mints (for Cashu)
    public private(set) var configuredMints: [String] = []

    /// Wallet relays
    public private(set) var walletRelays: [String] = []

    /// Transactions for display
    public private(set) var transactions: [WalletTransaction] = []

    /// Loading state
    public var isLoading: Bool = false

    /// Error message
    public var errorMessage: String?

    /// Whether wallet is set up
    public var isSetUp: Bool {
        switch walletType {
        case .cashu:
            return cashuWallet != nil && !configuredMints.isEmpty
        case .nwc:
            return nwcWallet != nil
        }
    }

    /// NWC connection status
    public private(set) var nwcConnectionStatus: NWCConnectionStatus = .disconnected

    // MARK: - Event observation

    private var cashuEventTask: Task<Void, Never>?

    // MARK: - Keychain Keys

    private let nwcKeychainService = "com.chirp.nwc"

    // MARK: - Initialization

    public init(ndk: NDK) {
        self.ndk = ndk

        // Restore wallet type from UserDefaults
        if let savedType = UserDefaults.standard.string(forKey: "chirp_wallet_type"),
           let type = WalletType(rawValue: savedType) {
            self.walletType = type
        } else {
            self.walletType = .cashu
        }
    }

    // MARK: - Wallet Initialization

    /// Initialize wallet based on current type
    public func initializeWallet() async {
        isLoading = true
        errorMessage = nil

        do {
            switch walletType {
            case .cashu:
                try await initializeCashuWallet()
            case .nwc:
                try await restoreNWCConnection()
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Cashu Wallet

    private func initializeCashuWallet() async throws {
        // Stop existing observation
        cashuEventTask?.cancel()

        let wallet = try NIP60Wallet(ndk: ndk)
        cashuWallet = wallet

        // Load wallet (subscribes to events)
        try await wallet.load()

        // Start observing wallet events
        cashuEventTask = Task {
            for await event in wallet.events {
                await handleCashuEvent(event)
            }
        }

        // Initial state
        await refreshCashuState()
    }

    private func handleCashuEvent(_ event: NIP60WalletEvent) async {
        switch event.type {
        case .balanceChanged(let newBalance):
            balance = newBalance
            if let wallet = cashuWallet {
                balancesByMint = await wallet.getBalancesByMint()
            }

        case .configurationUpdated(let mints):
            configuredMints = mints

        case .mintsAdded(let added):
            configuredMints.append(contentsOf: added)

        case .mintsRemoved(let removed):
            configuredMints.removeAll { removed.contains($0) }

        case .transactionAdded(let transaction):
            // Insert at beginning (newest first)
            transactions.insert(transaction, at: 0)

        case .transactionUpdated(let transaction):
            if let index = transactions.firstIndex(where: { $0.id == transaction.id }) {
                transactions[index] = transaction
            }

        default:
            break
        }
    }

    private func refreshCashuState() async {
        guard let wallet = cashuWallet else { return }

        balance = (try? await wallet.getBalance()) ?? 0
        balancesByMint = await wallet.getBalancesByMint()
        configuredMints = await wallet.mints.getMintURLs()
        transactions = await wallet.getTransactionHistory()
    }

    /// Set up Cashu wallet with mints
    public func setupCashuWallet(mints: [String], relays: [String]) async throws {
        isLoading = true
        defer { isLoading = false }

        walletRelays = relays

        guard let wallet = cashuWallet else {
            // Initialize wallet first if needed
            try await initializeCashuWallet()
            guard let wallet = cashuWallet else {
                throw WalletError.notInitialized
            }
            try await wallet.setup(mints: mints, relays: relays, publishMintList: true)
            return
        }

        try await wallet.setup(mints: mints, relays: relays, publishMintList: true)
        await refreshCashuState()
    }

    /// Request deposit (mint quote)
    public func requestDeposit(amount: Int64, mintURL: String) async throws -> CashuMintQuote {
        guard let wallet = cashuWallet else {
            throw WalletError.notInitialized
        }

        return try await wallet.requestMint(amount: amount, mintURL: mintURL, persistQuote: true)
    }

    /// Current deposit monitoring status
    public private(set) var depositStatus: DepositStatus?

    /// Deposit monitoring error
    public private(set) var depositError: Error?

    /// Active deposit monitoring task
    private var depositMonitorTask: Task<Void, Never>?

    /// Start monitoring deposit status - updates depositStatus property
    public func startMonitoringDeposit(quote: CashuMintQuote) {
        guard let wallet = cashuWallet else {
            depositError = WalletError.notInitialized
            return
        }

        depositStatus = .pending
        depositError = nil
        depositMonitorTask?.cancel()

        depositMonitorTask = Task {
            do {
                let stream = await wallet.monitorDeposit(quote: quote)
                for try await status in stream {
                    depositStatus = status
                    if case .minted = status {
                        break
                    }
                }
            } catch {
                depositError = error
            }
        }
    }

    /// Stop monitoring deposit
    public func stopMonitoringDeposit() {
        depositMonitorTask?.cancel()
        depositMonitorTask = nil
        depositStatus = nil
        depositError = nil
    }

    /// Pay lightning invoice with Cashu
    public func payLightning(invoice: String, amount: Int64) async throws -> (preimage: String, feePaid: Int64?) {
        guard let wallet = cashuWallet else {
            throw WalletError.notInitialized
        }

        return try await wallet.payLightning(invoice: invoice, amount: amount)
    }

    // MARK: - NWC Wallet

    /// Connect to NWC wallet
    public func connectNWC(connectionURI: String) async throws {
        isLoading = true
        defer { isLoading = false }

        let wallet = try await NDKNWCWallet(ndk: ndk, connectionURI: connectionURI)
        nwcConnectionStatus = .connecting

        do {
            try await wallet.connect()
            nwcWallet = wallet
            nwcConnectionStatus = .connected

            // Store connection URI in keychain
            try storeNWCConnection(connectionURI)

            // Refresh balance
            await refreshNWCState()
        } catch {
            nwcConnectionStatus = .error(error.localizedDescription)
            throw error
        }
    }

    private func restoreNWCConnection() async throws {
        guard let uri = retrieveNWCConnection() else {
            return
        }

        try await connectNWC(connectionURI: uri)
    }

    private func refreshNWCState() async {
        guard let wallet = nwcWallet else { return }

        do {
            if let bal = try await wallet.getBalance() {
                balance = bal
            }

            // Get transactions if supported
            let txs = try await wallet.listTransactions()
            transactions = txs.map { tx in
                WalletTransaction(
                    id: tx.paymentHash ?? UUID().uuidString,
                    type: tx.type == .incoming ? .receive : .send,
                    amount: tx.amount / 1000,
                    direction: tx.type == .incoming ? .incoming : .outgoing,
                    status: tx.settledAt != nil ? .completed : .pending,
                    memo: tx.description,
                    timestamp: Date(timeIntervalSince1970: TimeInterval(tx.createdAt))
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Disconnect NWC wallet
    public func disconnectNWC() async {
        await nwcWallet?.disconnect()
        nwcWallet = nil
        nwcConnectionStatus = .disconnected
        balance = 0
        transactions = []
        deleteNWCConnection()
    }

    /// Pay invoice via NWC
    public func payInvoiceNWC(invoice: String) async throws -> PayInvoiceResponse {
        guard let wallet = nwcWallet else {
            throw WalletError.notInitialized
        }

        let response = try await wallet.payInvoice(invoice)
        await refreshNWCState()
        return response
    }

    /// Create invoice via NWC
    public func createInvoiceNWC(amount: Int64, description: String?) async throws -> MakeInvoiceResponse {
        guard let wallet = nwcWallet else {
            throw WalletError.notInitialized
        }

        return try await wallet.makeInvoice(amount: amount, description: description)
    }

    // MARK: - Keychain Helpers

    private func storeNWCConnection(_ uri: String) throws {
        let data = uri.data(using: .utf8)!

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: nwcKeychainService,
            kSecAttrAccount as String: "connection_uri",
            kSecValueData as String: data
        ]

        // Delete existing
        SecItemDelete(query as CFDictionary)

        // Add new
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw WalletError.keychainError
        }
    }

    private func retrieveNWCConnection() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: nwcKeychainService,
            kSecAttrAccount as String: "connection_uri",
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let uri = String(data: data, encoding: .utf8) else {
            return nil
        }

        return uri
    }

    private func deleteNWCConnection() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: nwcKeychainService,
            kSecAttrAccount as String: "connection_uri"
        ]

        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Cleanup

    public func cleanup() {
        cashuEventTask?.cancel()
    }
}

// MARK: - Errors

public enum WalletError: LocalizedError {
    case notInitialized
    case keychainError
    case invalidInput(String)

    public var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Wallet not initialized"
        case .keychainError:
            return "Failed to access keychain"
        case .invalidInput(let message):
            return message
        }
    }
}
