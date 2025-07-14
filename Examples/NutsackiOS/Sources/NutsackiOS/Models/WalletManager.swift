import Foundation
import NDKSwift
import CashuSwift
import SwiftData

@MainActor
class WalletManager: ObservableObject {
    @Published var activeWallet: NDKCashuWallet?
    @Published var isLoading = false
    @Published var error: Error?
    @Published var transactions: [Transaction] = []
    
    private let nostrManager: NostrManager
    private let modelContext: ModelContext
    private let defaultMintURL = URL(string: "https://testnut.cashu.space")!
    
    // Subscription for history events
    private var historySubscription: NDKSubscription?
    
    init(nostrManager: NostrManager, modelContext: ModelContext) {
        self.nostrManager = nostrManager
        self.modelContext = modelContext
    }
    
    // MARK: - Wallet Operations
    
    /// Ensure wallet exists (called automatically by loadWallet)
    private func ensureWalletExists(for account: NostrAccount) async throws {
        guard let ndk = nostrManager.ndk else {
            throw WalletError.ndkNotInitialized
        }
        
        // Create NDKCashuWallet instance with mint cache if available
        let ndkWallet = NDKCashuWallet(ndk: ndk, mintCache: nostrManager.cache)
        
        // Try to load existing wallet
        do {
            try await ndkWallet.load()
            // Wallet exists, we're done
            self.activeWallet = ndkWallet
            return
        } catch {
            // No wallet exists, create one with default mint
            let defaultMintURL = URL(string: "https://testnut.cashu.space")!
            try await ndkWallet.addMint(url: defaultMintURL)
            
            // Save wallet to Nostr (creates NIP-60 events)
            try await ndkWallet.save()
            
            // Set as active wallet
            self.activeWallet = ndkWallet
        }
    }
    
    /// Load wallet from NIP-60 events
    func loadWallet(for account: NostrAccount) async throws {
        guard let ndk = nostrManager.ndk else {
            throw WalletError.ndkNotInitialized
        }
        
        isLoading = true
        defer { isLoading = false }
        
        // Ensure wallet exists (creates if needed)
        try await ensureWalletExists(for: account)
        
        guard let wallet = activeWallet else {
            throw WalletError.noActiveWallet
        }
        
        // Start nutzap monitoring
        Task {
            await wallet.startNutzapMonitor()
        }
        
        // Start periodic proof state checking
        Task {
            await wallet.startPeriodicProofStateCheck(interval: 300) // 5 minutes
        }
        
        // Publish nutzap preferences if needed (in case they haven't been published)
        Task {
            do {
                try await wallet.publishNutzapPreferences()
            } catch {
                print("Failed to publish nutzap preferences: \(error)")
                // Non-critical error, wallet can still function
            }
        }
        
        // Start monitoring transaction history
        startHistoryEventMonitoring()
    }
    
    /// Start monitoring NIP-60 history events (kind 7376)
    private func startHistoryEventMonitoring() {
        guard let ndk = nostrManager.ndk else { return }
        
        // Close existing subscription if any
        Task {
            await historySubscription?.close()
        }
        
        Task {
            guard let signer = ndk.signer else { return }
            let userPubkey = try? await signer.pubkey
            guard let pubkey = userPubkey else { return }
            
            // Create filter for history events
            let historyFilter = NDKFilter(
                authors: [pubkey],
                kinds: [7376]  // NIP-60 history events
            )
            
            // Subscribe to history events
            historySubscription = ndk.subscribe(filters: [historyFilter])
            
            guard let subscription = historySubscription else { return }
            
            // Process events as they arrive
            for try await event in subscription {
                await processHistoryEvent(event)
            }
        }
    }
    
    /// Process incoming history event
    private func processHistoryEvent(_ event: NDKEvent) async {
        guard let signer = nostrManager.ndk?.signer else { return }
        
        do {
            // Decrypt the event content
            let sender = NDKUser(pubkey: event.pubkey)
            let decryptedContent = try await signer.decrypt(
                sender: sender,
                value: event.content,
                scheme: .nip44
            )
            
            // Parse the tags from decrypted content
            guard let tagsData = decryptedContent.data(using: .utf8),
                  let tags = try? JSONDecoder().decode([[String]].self, from: tagsData) else {
                print("Failed to parse history event tags")
                return
            }
            
            // Extract transaction info from tags
            var direction: String?
            var amount: Int64?
            var memo: String?
            
            for tag in tags {
                guard tag.count >= 2 else { continue }
                switch tag[0] {
                case "direction":
                    direction = tag[1]
                case "amount":
                    amount = Int64(tag[1])
                case "memo":
                    memo = tag[1]
                default:
                    break
                }
            }
            
            // Create transaction object
            guard let dir = direction,
                  let amt = amount ?? extractAmountFromTags(event.tags) else {
                return
            }
            
            let transactionType: Transaction.TransactionType
            switch dir {
            case "in": 
                transactionType = .mint  // Lightning deposits
            case "out": 
                transactionType = .melt  // Lightning payments
            default: 
                return
            }
            
            let transaction = Transaction(
                type: transactionType,
                amount: Int(amt),
                memo: memo
            )
            transaction.createdAt = Date(timeIntervalSince1970: TimeInterval(event.createdAt))
            transaction.status = .completed
            
            // Add to published transactions array
            await MainActor.run {
                // Check if we already have this transaction
                if !self.transactions.contains(where: { 
                    $0.createdAt == transaction.createdAt && 
                    $0.amount == transaction.amount 
                }) {
                    self.transactions.append(transaction)
                    
                    // Sort by date (newest first)
                    self.transactions.sort { $0.createdAt > $1.createdAt }
                }
            }
        } catch {
            print("Failed to process history event: \(error)")
        }
    }
    
    /// Extract amount from clear tags if not in encrypted content
    private func extractAmountFromTags(_ tags: [[String]]) -> Int64? {
        for tag in tags {
            if tag.count >= 2 && tag[0] == "amount" {
                return Int64(tag[1])
            }
        }
        return nil
    }
    
    /// Get current balance
    func getBalance() async throws -> Int64 {
        guard let wallet = activeWallet else {
            throw WalletError.noActiveWallet
        }
        
        return try await wallet.getBalance()
    }
    
    /// Get balance for specific mint
    func getBalance(for mintURL: URL) async -> Int64 {
        guard let wallet = activeWallet else {
            return 0
        }
        
        return await wallet.getBalance(mint: mintURL)
    }
    
    /// Create and configure a new wallet with selected mints
    func createAndConfigureWallet(with mintURLs: [URL]) async throws {
        guard let ndk = nostrManager.ndk else {
            throw WalletError.ndkNotInitialized
        }
        
        // Create a new wallet instance with mint cache if available
        let ndkWallet = NDKCashuWallet(ndk: ndk, mintCache: nostrManager.cache)
        
        // Add all selected mints
        for mintURL in mintURLs {
            try await ndkWallet.addMint(url: mintURL)
        }
        
        // Save wallet to Nostr (creates NIP-60 events)
        try await ndkWallet.save()
        
        // Publish nutzap preferences so others can send nutzaps to this wallet
        try await ndkWallet.publishNutzapPreferences()
        
        // Set as active wallet
        self.activeWallet = ndkWallet
    }
    
    // MARK: - Mint Operations
    
    /// Request a Lightning invoice to mint ecash
    func requestMint(amount: Int64, mintURL: String) async throws -> CashuMintQuote {
        guard let wallet = activeWallet else {
            throw WalletError.noActiveWallet
        }
        
        return try await wallet.requestMint(
            amount: amount,
            mintURL: mintURL,
            persistQuote: true
        )
    }
    
    /// Monitor deposit status
    func monitorDeposit(quote: CashuMintQuote) async -> AsyncThrowingStream<DepositStatus, Error> {
        guard let wallet = activeWallet else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: WalletError.noActiveWallet)
            }
        }
        
        return await wallet.monitorDeposit(quote: quote, pollingInterval: 5.0, timeout: 600.0)
    }
    
    // MARK: - Send Operations
    
    /// Send ecash tokens
    func send(amount: Int64, memo: String?, fromMint: URL?) async throws -> String {
        guard let wallet = activeWallet else {
            throw WalletError.noActiveWallet
        }
        
        // Select mint if not specified
        let mintURL: URL
        if let fromMint = fromMint {
            mintURL = fromMint
        } else {
            // Auto-select mint with sufficient balance
            let mints = await wallet.getMints()
            var selectedMint: URL?
            
            for mint in mints {
                let balance = await wallet.getBalance(mint: mint.url)
                if balance >= amount {
                    selectedMint = mint.url
                    break
                }
            }
            
            guard let selected = selectedMint else {
                throw WalletError.insufficientBalance
            }
            mintURL = selected
        }
        
        // Generate P2PK pubkey for locking
        let p2pkPubkey = try await wallet.getP2PKPubkey()
        
        // Send tokens (creates P2PK locked proofs)
        let (proofs, _) = try await wallet.send(
            amount: amount,
            to: p2pkPubkey,
            mint: mintURL
        )
        
        // Create token from proofs
        let token = CashuSwift.Token(
            proofs: [mintURL.absoluteString: proofs.toCashuSwiftProofs()],
            unit: "sat",
            memo: memo
        )
        
        // Encode token
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let tokenData = try encoder.encode(token)
        guard String(data: tokenData, encoding: .utf8) != nil else {
            throw WalletError.encodingError
        }
        
        // Create base64url encoded token
        let base64Token = tokenData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        
        return "cashuA\(base64Token)"
    }
    
    // MARK: - Receive Operations
    
    /// Receive ecash tokens
    func receive(tokenString: String) async throws -> Int64 {
        guard let wallet = activeWallet else {
            throw WalletError.noActiveWallet
        }
        
        // Parse token string
        guard tokenString.hasPrefix("cashuA") else {
            throw WalletError.invalidToken
        }
        
        let base64Part = String(tokenString.dropFirst(6))
        
        // Convert base64url to base64
        var base64 = base64Part
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        
        // Add padding if needed
        while base64.count % 4 != 0 {
            base64.append("=")
        }
        
        guard let tokenData = Data(base64Encoded: base64),
              let token = try? JSONDecoder().decode(CashuSwift.Token.self, from: tokenData) else {
            throw WalletError.invalidToken
        }
        
        var totalReceived: Int64 = 0
        
        // Process proofs from each mint
        for (mintURL, proofs) in token.proofsByMint {
            // Ensure we have this mint
            if let url = URL(string: mintURL) {
                try await wallet.addMint(url: url)
            }
            
            // Receive the proofs
            try await wallet.receive(proofs: proofs)
            
            // Calculate total
            totalReceived += proofs.reduce(0) { $0 + Int64($1.amount) }
        }
        
        return totalReceived
    }
    
    // MARK: - Lightning Operations
    
    /// Pay a Lightning invoice
    func payLightning(invoice: String, amount: Int64) async throws -> String {
        guard let wallet = activeWallet else {
            throw WalletError.noActiveWallet
        }
        
        let (preimage, feePaid) = try await wallet.payLightning(
            invoice: invoice,
            amount: amount
        )
        
        print("Paid Lightning invoice: \(amount) sats, fee: \(feePaid ?? 0) sats")
        
        return preimage
    }
    
    // MARK: - Nutzap Operations
    
    /// Send a nutzap
    func sendNutzap(
        to recipient: String,
        amount: Int64,
        comment: String?,
        acceptedMints: [URL]
    ) async throws {
        guard let wallet = activeWallet else {
            throw WalletError.noActiveWallet
        }
        
        // Create recipient user
        let recipientUser = NDKUser(pubkey: recipient)
        
        // Create nutzap request
        let request = NDKNutzapRequest(
            recipient: recipientUser,
            amount: amount,
            mints: acceptedMints,
            recipientPubkey: recipient,
            comment: comment
        )
        
        // Send nutzap
        _ = try await wallet.pay(request)
        
        print("Sent nutzap: \(amount) sats to \(recipient)")
    }
    
    // MARK: - Mint Management
    
    /// Add a new mint
    func addMint(url: URL) async throws {
        guard let wallet = activeWallet else {
            throw WalletError.noActiveWallet
        }
        
        try await wallet.addMint(url: url)
        
        // Note: SwiftData model should be updated by the view that calls this
    }
    
    /// Remove a mint
    func removeMint(url: URL) async throws {
        guard let wallet = activeWallet else {
            throw WalletError.noActiveWallet
        }
        
        try await wallet.removeMint(url: url)
        
        // Note: SwiftData model should be updated by the view that calls this
    }
    
    /// Discover mints via NIP-60
    func discoverMints() async throws -> [MintDiscovery.DiscoveredMint] {
        guard let wallet = activeWallet else {
            throw WalletError.noActiveWallet
        }
        
        return try await wallet.mintDiscovery.discoverMints()
    }
    
    // MARK: - Cross-mint Operations
    
    /// Transfer between mints
    func transferBetweenMints(
        amount: Int64,
        fromMint: URL,
        toMint: URL
    ) async throws -> TransferResult {
        guard let wallet = activeWallet else {
            throw WalletError.noActiveWallet
        }
        
        return try await wallet.transferBetweenMints(
            amount: amount,
            fromMint: fromMint,
            toMint: toMint
        )
    }
    
    /// Estimate transfer fees
    func estimateTransferFees(
        amount: Int64,
        fromMint: URL,
        toMint: URL
    ) async throws -> (lightningFee: Int64, inputFee: Int64, totalFee: Int64) {
        guard let wallet = activeWallet else {
            throw WalletError.noActiveWallet
        }
        
        return try await wallet.estimateCrossMintTransferFees(
            amount: amount,
            fromMint: fromMint,
            toMint: toMint
        )
    }
    
    // MARK: - State Management
    
    /// Check and reconcile proof states
    func reconcileProofStates() async throws {
        guard let wallet = activeWallet else {
            throw WalletError.noActiveWallet
        }
        
        try await wallet.checkAndReconcileProofStates()
    }
    
    /// Publish nutzap preferences
    func publishNutzapPreferences() async throws {
        guard let wallet = activeWallet else {
            throw WalletError.noActiveWallet
        }
        
        try await wallet.publishNutzapPreferences()
    }
    
    /// Get wallet's P2PK pubkey
    func getP2PKPubkey() async throws -> String {
        guard let wallet = activeWallet else {
            throw WalletError.noActiveWallet
        }
        
        return try await wallet.getP2PKPubkey()
    }
}

// MARK: - Errors

enum WalletError: LocalizedError {
    case ndkNotInitialized
    case noActiveWallet
    case insufficientBalance
    case invalidToken
    case encodingError
    
    var errorDescription: String? {
        switch self {
        case .ndkNotInitialized:
            return "NDK is not initialized"
        case .noActiveWallet:
            return "No active wallet"
        case .insufficientBalance:
            return "Insufficient balance"
        case .invalidToken:
            return "Invalid token format"
        case .encodingError:
            return "Failed to encode data"
        }
    }
}

// MARK: - Extensions

extension Array where Element == CashuProof {
    func toCashuSwiftProofs() -> [CashuSwift.Proof] {
        return self.map { $0.toCashuSwiftProof() }
    }
}