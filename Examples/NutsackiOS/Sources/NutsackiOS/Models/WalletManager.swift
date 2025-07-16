import Foundation
import NDKSwift
import CashuSwift
import SwiftData
import Observation

@MainActor
@Observable
class WalletManager {
    var activeWallet: NIP60Wallet?
    var isLoading = false
    var error: Error?
    var transactions: [Transaction] = []
    var availableMints: [String] = []
    var currentBalance: Int64 = 0
    
    private let nostrManager: NostrManager
    private let modelContext: ModelContext
    private let defaultMintURL = URL(string: "https://testnut.cashu.space")!
    
    // Subscription for history events
    private var historySubscription: NDKSubscription?
    
    // Task for monitoring wallet events
    private var walletEventTask: Task<Void, Never>?
    
    
    init(nostrManager: NostrManager, modelContext: ModelContext) {
        self.nostrManager = nostrManager
        self.modelContext = modelContext
    }
    
    // MARK: - Wallet Operations
    
    /// Load wallet for currently authenticated user
    func loadWalletForCurrentUser() async throws {
        guard nostrManager.isAuthenticated else {
            throw WalletError.notAuthenticated
        }
        
        try await loadWallet()
    }
    
    /// Ensure wallet exists (called automatically by loadWallet)
    private func ensureWalletExists() async throws {
        guard let ndk = nostrManager.ndk else {
            throw WalletError.ndkNotInitialized
        }
        
        // Wait for signer to be available before creating wallet
        guard ndk.signer != nil else {
            throw WalletError.signerNotAvailable
        }
        
        // Create NIP60Wallet instance with mint cache if available
        let ndkWallet = NIP60Wallet(ndk: ndk, cache: nostrManager.cache)
        
        // Set as active wallet
        self.activeWallet = ndkWallet
        
        // Start monitoring wallet events
        startWalletEventMonitoring()
        
        // Load wallet - this will fetch initial config and subscribe to wallet events
        print("WalletManager - Loading wallet...")
        try await ndkWallet.load()
        print("WalletManager - Wallet loading finished")
        
        // Get initial balance
        if let balance = try? await ndkWallet.getBalance() {
            self.currentBalance = balance
            print("WalletManager - Initial balance: \(balance)")
        }
        
        // Check if wallet has mints configured
        let mintURLs = await ndkWallet.mints.getMintURLs()
        if mintURLs.isEmpty {
            print("WalletManager - No mints configured, setting up default mint")
            
            // No wallet exists or no mints configured, create one with default mint
            let defaultMints = ["https://testnut.cashu.space"]
            let relays = await getRelaysForWallet()
            
            // Setup wallet with default mint
            try await ndkWallet.setup(
                mints: defaultMints,
                relays: relays,
                publishMintList: true
            )
            print("WalletManager - Default wallet setup completed")
        } else {
            print("WalletManager - Wallet loaded with \(mintURLs.count) mints")
            // Update our local state
            self.availableMints = mintURLs
        }
    }
    
    /// Load wallet from NIP-60 events
    func loadWallet() async throws {
        guard let ndk = nostrManager.ndk else {
            throw WalletError.ndkNotInitialized
        }
        
        isLoading = true
        defer { isLoading = false }
        
        // Ensure wallet exists (creates if needed)
        try await ensureWalletExists()
        
        guard let wallet = activeWallet else {
            throw WalletError.noActiveWallet
        }
        
        // Nutzap monitoring is now handled by the unified wallet subscription in load()
        
        // Start monitoring transaction history
        startHistoryEventMonitoring()
    }
    
    /// Start monitoring wallet configuration changes
    private func startWalletEventMonitoring() {
        walletEventTask?.cancel()
        
        walletEventTask = Task {
            guard let wallet = activeWallet else { return }
            
            for await event in await wallet.events {
                switch event.type {
                case .configurationUpdated(let mints):
                    print("WalletManager - Configuration updated with \(mints.count) mints")
                    await MainActor.run {
                        self.availableMints = mints
                    }
                    
                case .mintsAdded(let addedMints):
                    print("WalletManager - Mints added: \(addedMints)")
                    
                case .mintsRemoved(let removedMints):
                    print("WalletManager - Mints removed: \(removedMints)")
                    
                case .balanceChanged(let newBalance):
                    print("WalletManager - Balance changed: \(newBalance)")
                    await MainActor.run {
                        self.currentBalance = newBalance
                    }
                    
                case .nutzapReceived(let amount, let from):
                    print("WalletManager - Nutzap received: \(amount) sats from \(from ?? "unknown")")
                }
            }
        }
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
                kinds: [EventKind.cashuSpendingHistory]  // NIP-60 history events
            )
            
            // Subscribe to history events
            historySubscription = await ndk.subscribe(filters: [historyFilter])
            
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
            
            // Determine transaction type from tags
            let transactionType: Transaction.TransactionType
            
            // Check for specific type in clear tags (e.g., nutzap)
            if let typeTag = event.tags.first(where: { $0.count >= 2 && $0[0] == "type" }) {
                switch typeTag[1] {
                case "nutzap":
                    transactionType = .nutzap
                default:
                    // Fall back to direction-based type
                    guard let dir = direction else { return }
                    switch dir {
                    case "in": 
                        transactionType = .receive
                    case "out": 
                        transactionType = .send
                    default: 
                        return
                    }
                }
            } else {
                // Use direction to determine type
                guard let dir = direction else { return }
                switch dir {
                case "in": 
                    transactionType = .mint  // Lightning deposits or received ecash
                case "out": 
                    transactionType = .melt  // Lightning payments or sent ecash
                default: 
                    return
                }
            }
            
            // Get amount from encrypted tags or clear tags
            guard let amt = amount ?? extractAmountFromTags(event.tags) else {
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
        
        return try await wallet.getBalance() ?? 0
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
        guard let wallet = activeWallet else {
            throw WalletError.noActiveWallet
        }
        
        print("WalletManager - Configuring wallet with \(mintURLs.count) mints")
        
        // Convert URLs to strings
        let mintStrings = mintURLs.map { $0.absoluteString }
        
        // Get relays from the user's relay list or use defaults
        let relays = await getRelaysForWallet()
        
        // Setup wallet with mints, relays, and publish mint list
        print("WalletManager - Publishing wallet configuration")
        try await wallet.setup(
            mints: mintStrings,
            relays: relays,
            publishMintList: true
        )
        print("WalletManager - Wallet configuration published")
        
        // The wallet event monitoring will update availableMints when the event is processed
        // For now, optimistically update the UI
        self.availableMints = mintStrings
    }
    
    /// Get relays for wallet configuration
    private func getRelaysForWallet() async -> [String] {
        print("getRelaysForWallet")
        guard let ndk = nostrManager.ndk,
              let signer = ndk.signer,
              let userPubkey = try? await signer.pubkey else {
            // Return default relays if we can't get user's relays
            return [
                "wss://relay.primal.net"
            ]
        }
        print("getRelaysForWallet guard ok")
        
        // Try to get user's relay list
        let user = ndk.getUser(userPubkey)
        do {
            // Use the method from NDKUser.swift that returns [NDKRelayInfo]
            print("getRelaysForWallet fetchRelayList")
            let relayInfoList: [NDKRelayInfo] = try await user.fetchRelayList()
            let writeRelays = relayInfoList
                .filter { $0.write }
                .map { $0.url }
            print("getRelaysForWallet fetchRelayList done")
            if !writeRelays.isEmpty {
                return writeRelays
            }
        } catch {
            print("WalletManager - Failed to fetch user's relay list: \(error)")
        }
        
        // Fallback to default relays
        return [
            "wss://relay.primal.net"
        ]
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
            let mintURLs = await wallet.mints.getMintURLs()
            let mints = mintURLs.compactMap { URL(string: $0) }
            var selectedMint: URL?
            
            for mintURL in mints {
                let balance = await wallet.getBalance(mint: mintURL)
                if balance >= amount {
                    selectedMint = mintURL
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
            proofs: [mintURL.absoluteString: proofs],
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
            // Receive the proofs - wallet can handle proofs from any mint
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
        let request = NutzapPaymentRequest(
            amountSats: amount,
            recipientPubkey: recipient,
            acceptedMints: acceptedMints,
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
        
        print("🔧 WalletManager - Starting mint addition process for: \(url)")
        
        // Use WalletManager's availableMints state which tracks the current configuration
        var mintStrings = availableMints
        print("🔧 WalletManager - Current mints from WalletManager state: \(mintStrings)")
        
        // Check if the mint already exists
        if mintStrings.contains(url.absoluteString) {
            print("🔧 WalletManager - Mint \(url) already exists, skipping")
            return
        }
        
        mintStrings.append(url.absoluteString)
        print("🔧 WalletManager - Updated mints list: \(mintStrings)")
        
        // Get relays
        let relays = await getRelaysForWallet()
        print("🔧 WalletManager - Retrieved relays for wallet: \(relays)")
        
        // Use NIP60Wallet.setup() to handle both wallet config and mint list events
        try await wallet.setup(
            mints: mintStrings,
            relays: relays,
            publishMintList: true
        )
        
        print("🔧 WalletManager - Completed mint addition process for: \(url)")
        
        // The wallet will update itself when it receives the event
    }
    
    /// Remove a mint
    func removeMint(url: URL) async throws {
        guard let wallet = activeWallet else {
            throw WalletError.noActiveWallet
        }
        
        print("WalletManager - Removing mint: \(url)")
        
        // Use WalletManager's availableMints state which tracks the current configuration
        let mintStrings = availableMints.filter { $0 != url.absoluteString }
        
        // Get relays
        let relays = await getRelaysForWallet()
        
        // Use NIP60Wallet.setup() to handle both wallet config and mint list events
        try await wallet.setup(
            mints: mintStrings,
            relays: relays,
            publishMintList: true
        )
        
        print("WalletManager - Published updated wallet configuration without mint: \(url)")
        
        // The wallet will update itself when it receives the event
    }
    
    /// Discover mints via NIP-87 with streaming updates
    func discoverMintsStream() -> AsyncStream<[DiscoveredMint]> {
        guard let ndk = nostrManager.ndk else {
            return AsyncStream { continuation in
                continuation.finish()
            }
        }
        
        let discoveryManager = MintDiscoveryManager(ndk: ndk)
        return discoveryManager.discoverMintsStream()
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
        
        // Estimate fees for cross-mint transfer
        // Lightning fee is typically 0.5% + 1 sat
        let lightningFee = max(1, Int64(Double(amount) * 0.005) + 1)
        // Input fee is typically 0.2%
        let inputFee = max(1, Int64(Double(amount) * 0.002))
        let totalFee = lightningFee + inputFee
        
        return (lightningFee: lightningFee, inputFee: inputFee, totalFee: totalFee)
    }
    
    // MARK: - State Management
    
    /// Check and reconcile proof states
    func reconcileProofStates() async throws {
        guard let wallet = activeWallet else {
            throw WalletError.noActiveWallet
        }
        
        try await wallet.checkAndReconcileProofStates()
    }
    
    // MARK: - Wallet Events Management
    
    /// Fetch all wallet events (kind 7375) and their deletion status
    func fetchAllWalletEvents() async throws -> [WalletEventInfo] {
        guard let ndk = nostrManager.ndk,
              let signer = ndk.signer else {
            throw WalletError.ndkNotInitialized
        }
        
        let userPubkey = try await signer.pubkey
        
        // Fetch all token events (kind 7375) from this user
        let tokenFilter = NDKFilter(
            authors: [userPubkey],
            kinds: [EventKind.cashuToken]
        )
        
        // Fetch deletion events that target token events
        let deletionFilter = NDKFilter(
            authors: [userPubkey],
            kinds: [EventKind.deletion],
            tags: ["k": Set([String(EventKind.cashuToken)])]
        )
        
        // Fetch events from cache or relays
        let tokenEvents = try await ndk.fetchEvents([tokenFilter])
        let deletionEvents = try await ndk.fetchEvents([deletionFilter])
        
        // Build a set of deleted event IDs from deletion events
        var deletedEventIds = Set<String>()
        var deletionEventMap: [String: NDKEvent] = [:]
        
        for deletionEvent in deletionEvents {
            // Extract deleted event IDs from "e" tags
            for tag in deletionEvent.tags {
                if tag.count >= 2 && tag[0] == "e" {
                    deletedEventIds.insert(tag[1])
                    deletionEventMap[tag[1]] = deletionEvent
                }
            }
        }
        
        // Also check for del tags in newer events
        var eventsByDel: [String: Set<String>] = [:]
        for event in tokenEvents {
            // Try to decrypt and parse token data
            if let tokenData = try? await decryptTokenEvent(event, signer: signer) {
                if let delTags = tokenData.del {
                    for deletedId in delTags {
                        deletedEventIds.insert(deletedId)
                        if eventsByDel[deletedId] == nil {
                            eventsByDel[deletedId] = Set<String>()
                        }
                        eventsByDel[deletedId]?.insert(event.id)
                    }
                }
            }
        }
        
        // Process each token event
        var walletEvents: [WalletEventInfo] = []
        
        for event in tokenEvents {
            // Try to decrypt token data
            let tokenData = try? await decryptTokenEvent(event, signer: signer)
            
            // Check if this event is deleted
            let isDeleted = deletedEventIds.contains(event.id)
            
            // Determine deletion reason
            var deletionReason: String? = nil
            var deletionEvent: NDKEvent? = nil
            
            if isDeleted {
                if let delEvent = deletionEventMap[event.id] {
                    deletionReason = "Deleted via NIP-09"
                    deletionEvent = delEvent
                } else if let replacingEventIds = eventsByDel[event.id] {
                    deletionReason = "Replaced by event(s): \(replacingEventIds.joined(separator: ", ").prefix(32))..."
                }
            }
            
            let eventInfo = WalletEventInfo(
                event: event,
                tokenData: tokenData,
                isDeleted: isDeleted,
                deletionReason: deletionReason,
                deletionEvent: deletionEvent
            )
            
            walletEvents.append(eventInfo)
        }
        
        // Sort by creation date (newest first)
        walletEvents.sort { $0.event.createdAt > $1.event.createdAt }
        
        return walletEvents
    }
    
    /// Decrypt a token event to get its content
    private func decryptTokenEvent(_ event: NDKEvent, signer: NDKSigner) async throws -> NIP60TokenEvent? {
        let sender = NDKUser(pubkey: event.pubkey)
        let decryptedContent = try await signer.decrypt(
            sender: sender,
            value: event.content,
            scheme: .nip44
        )
        
        guard let data = decryptedContent.data(using: .utf8) else {
            return nil
        }
        
        return try JSONDecoder().decode(NIP60TokenEvent.self, from: data)
    }
    
    /// Check proof states for specific proofs
    func checkProofStates(for proofs: [CashuSwift.Proof], mint mintURL: String) async throws -> [String: CashuSwift.Proof.ProofState] {
        guard let wallet = activeWallet else {
            throw WalletError.noActiveWallet
        }
        
        guard let url = URL(string: mintURL) else {
            throw WalletError.invalidMintURL
        }
        
        // Get mint instance
        let mints = await wallet.mints.getAllMints()
        guard let mint = mints[mintURL] else {
            throw WalletError.mintNotFound
        }
        
        // Check proof states
        let states = try await CashuSwift.check(proofs, mint: mint)
        
        // Build result dictionary mapping C value to state
        var result: [String: CashuSwift.Proof.ProofState] = [:]
        for (index, proof) in proofs.enumerated() {
            if index < states.count {
                result[proof.C] = states[index]
            }
        }
        
        return result
    }
    
    
    /// Get wallet's P2PK pubkey
    func getP2PKPubkey() async throws -> String {
        guard let wallet = activeWallet else {
            throw WalletError.noActiveWallet
        }
        
        return try await wallet.getP2PKPubkey()
    }
    
    // MARK: - Mint Management
    
    /// Get mints info as MintInfo array
    func getMintsInfo() async -> [MintInfo] {
        // Use the availableMints property which is updated via event monitoring
        let mintURLs = availableMints.compactMap { URL(string: $0) }
        return mintURLs.map { url in
            MintInfo(url: url)
        }
    }
    
    // MARK: - Session Management
    
    /// Clear all wallet data and cancel active subscriptions (called during logout)
    func clearWalletData() {
        // Cancel active subscriptions
        walletEventTask?.cancel()
        walletEventTask = nil
        
        Task {
            await historySubscription?.close()
            historySubscription = nil
        }
        
        // Clear wallet state
        activeWallet = nil
        transactions.removeAll()
        availableMints.removeAll()
        currentBalance = 0
        
        print("WalletManager - Cleared all wallet data and cancelled subscriptions")
    }
    
    // MARK: - Private Methods
}

// MARK: - Errors

enum WalletError: LocalizedError {
    case ndkNotInitialized
    case noActiveWallet
    case notAuthenticated
    case insufficientBalance
    case invalidToken
    case encodingError
    case signerNotAvailable
    case invalidMintURL
    case mintNotFound
    
    var errorDescription: String? {
        switch self {
        case .ndkNotInitialized:
            return "NDK is not initialized"
        case .noActiveWallet:
            return "No active wallet"
        case .notAuthenticated:
            return "User not authenticated"
        case .insufficientBalance:
            return "Insufficient balance"
        case .invalidToken:
            return "Invalid token format"
        case .encodingError:
            return "Failed to encode data"
        case .signerNotAvailable:
            return "Signer not available yet"
        case .invalidMintURL:
            return "Invalid mint URL"
        case .mintNotFound:
            return "Mint not found"
        }
    }
}

// MARK: - Extensions