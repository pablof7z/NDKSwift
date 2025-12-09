// WalletViewModel.swift
import SwiftUI
import NDKSwift
import CashuSwift

@MainActor
public class WalletViewModel: ObservableObject {
    let ndk: NDK

    @Published public private(set) var wallet: NIP60Wallet?
    @Published public private(set) var balance: Int64 = 0
    @Published public private(set) var balancesByMint: [String: Int64] = [:]
    @Published public private(set) var isLoading = false
    @Published public private(set) var isSetup = false
    @Published public private(set) var transactions: [WalletTransaction] = []
    @Published public private(set) var configuredMints: [String] = []
    @Published public private(set) var error: Error?

    private var eventObservationTask: Task<Void, Never>?

    public init(ndk: NDK) {
        self.ndk = ndk
    }

    deinit {
        eventObservationTask?.cancel()
    }

    // MARK: - Wallet Lifecycle

    /// Load existing wallet or determine if setup is needed
    public func loadWallet() async {
        guard wallet == nil else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let newWallet = try NIP60Wallet(ndk: ndk)
            self.wallet = newWallet

            // Start listening for events before loading
            startEventObservation()

            // Load wallet state from relays
            try await newWallet.load()

            // Check if wallet has mints configured (indicates setup complete)
            let mints = await newWallet.mints.getMintURLs()
            isSetup = !mints.isEmpty
            configuredMints = mints

            // Get initial balance
            if let bal = try await newWallet.getBalance() {
                balance = bal
            }
            balancesByMint = await newWallet.getBalancesByMint()

            // Load transaction history
            transactions = await newWallet.getTransactionHistory()

            // Configure zap manager with this wallet
            await ndk.zapManager.configureDefaults(cashuWallet: newWallet)

        } catch {
            self.error = error
        }
    }

    /// Setup wallet with selected mints and relays
    public func setupWallet(mints: [String], relays: [String]) async throws {
        guard let wallet = wallet else {
            throw WalletError.notInitialized
        }

        isLoading = true
        defer { isLoading = false }

        // Setup publishes kind 17375 (wallet config) and kind 10019 (mint list)
        try await wallet.setup(mints: mints, relays: relays, publishMintList: true)

        isSetup = true
        configuredMints = mints
    }

    // MARK: - Deposit

    /// Request a Lightning invoice for depositing funds
    public func requestDeposit(amount: Int64, mintURL: String) async throws -> CashuMintQuote {
        guard let wallet = wallet else {
            throw WalletError.notInitialized
        }

        return try await wallet.requestMint(amount: amount, mintURL: mintURL, persistQuote: true)
    }

    /// Monitor deposit status
    public func monitorDeposit(quote: CashuMintQuote) async -> AsyncThrowingStream<DepositStatus, Error> {
        guard let wallet = wallet else {
            return AsyncThrowingStream { $0.finish(throwing: WalletError.notInitialized) }
        }

        return await wallet.monitorDeposit(quote: quote)
    }

    // MARK: - Send/Withdraw

    /// Pay a Lightning invoice
    public func payLightningInvoice(_ invoice: String, amount: Int64) async throws -> (preimage: String, feePaid: Int64?) {
        guard let wallet = wallet else {
            throw WalletError.notInitialized
        }

        let result = try await wallet.payLightning(invoice: invoice, amount: amount)

        // Refresh balance after payment
        await refreshBalance()

        return result
    }

    /// Create a Cashu token for offline sending
    public func createToken(amount: Int64, mint: URL) async throws -> String {
        guard let wallet = wallet else {
            throw WalletError.notInitialized
        }

        // Get proofs for the amount
        let proofs = await wallet.proofStateManager.getAvailableProofs(mint: mint.absoluteString)

        // Select proofs that cover the amount
        var selectedProofs: [CashuSwift.Proof] = []
        var total: Int64 = 0

        for proof in proofs {
            if total >= amount { break }
            selectedProofs.append(proof)
            total += Int64(proof.amount)
        }

        guard total >= amount else {
            throw WalletError.insufficientBalance
        }

        return try await wallet.createTokenFromProofs(proofs: selectedProofs, mint: mint)
    }

    // MARK: - Balance & Transactions

    /// Refresh wallet balance
    public func refreshBalance() async {
        guard let wallet = wallet else { return }

        if let bal = try? await wallet.getBalance() {
            balance = bal
        }
        balancesByMint = await wallet.getBalancesByMint()
    }

    /// Refresh transaction history
    public func refreshTransactions() async {
        guard let wallet = wallet else { return }
        transactions = await wallet.getTransactionHistory()
    }

    // MARK: - Event Observation

    private func startEventObservation() {
        guard let wallet = wallet else { return }

        eventObservationTask?.cancel()
        eventObservationTask = Task { [weak self] in
            let events = await wallet.events
            for await event in events {
                guard let self = self else { break }

                await MainActor.run {
                    self.handleWalletEvent(event)
                }
            }
        }
    }

    private func handleWalletEvent(_ event: NIP60WalletEvent) {
        switch event.type {
        case .balanceChanged(let newBalance):
            balance = newBalance
            Task {
                balancesByMint = await wallet?.getBalancesByMint() ?? [:]
            }

        case .configurationUpdated(let mints):
            configuredMints = mints
            isSetup = !mints.isEmpty

        case .mintsAdded(let added):
            for mint in added {
                if !configuredMints.contains(mint) {
                    configuredMints.append(mint)
                }
            }

        case .mintsRemoved(let removed):
            configuredMints.removeAll { removed.contains($0) }

        case .blacklistUpdated:
            // Could update UI to show blacklisted mints
            break

        case .nutzapReceived:
            // Refresh transactions when nutzap activity occurs
            Task {
                await refreshTransactions()
            }

        case .transactionAdded, .transactionUpdated:
            // Refresh transactions
            Task {
                await refreshTransactions()
            }
        }
    }

    // MARK: - Zapping

    /// Send a zap (nutzap or Lightning) to an event
    public func zap(event: NDKEvent, amount: Int64, comment: String? = nil) async throws {
        let recipient = NDKUser(pubkey: event.pubkey)

        _ = try await ndk.zapManager.zap(
            event: event,
            to: recipient,
            amountSats: amount,
            comment: comment
        )

        // Refresh balance after zap
        await refreshBalance()
    }
}

// MARK: - Errors

public enum WalletError: LocalizedError {
    case notInitialized
    case insufficientBalance
    case invalidMint
    case setupFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Wallet not initialized"
        case .insufficientBalance:
            return "Insufficient balance"
        case .invalidMint:
            return "Invalid mint"
        case .setupFailed(let reason):
            return "Wallet setup failed: \(reason)"
        }
    }
}
