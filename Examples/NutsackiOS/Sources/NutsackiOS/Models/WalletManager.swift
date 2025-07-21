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
    var currentBalance: Int64 = 0
    
    private let nostrManager: NostrManager
    private let modelContext: ModelContext
    private let defaultMintURL = URL(string: "https://testnut.cashu.space")!
    
    // Declarative data sources
    private var walletEventDataSource: WalletEventDataSource?
    private var walletHistoryDataSource: WalletHistoryDataSource?
    private var nutzapDataSource: NutzapDataSource?
    
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
        guard let signer = ndk.signer else {
            throw WalletError.signerNotAvailable
        }
        
        let userPubkey = try await signer.pubkey
        
        // Create NIP60Wallet instance with mint cache if available
        let ndkWallet = try NIP60Wallet(ndk: ndk, cache: nostrManager.cache)
        
        // Set as active wallet
        self.activeWallet = ndkWallet
        
        // Register the wallet with the zap manager
        if let zapManager = nostrManager.zapManager {
            await zapManager.register(provider: ndkWallet)
            print("WalletManager - Registered NIP60Wallet with zap manager")
        }
        
        // Initialize declarative data sources
        self.walletEventDataSource = WalletEventDataSource(ndk: ndk, pubkey: userPubkey)
        self.walletHistoryDataSource = WalletHistoryDataSource(ndk: ndk, pubkey: userPubkey)
        self.nutzapDataSource = NutzapDataSource(ndk: ndk, recipientPubkey: userPubkey)
        
        // Start monitoring wallet events through the wallet itself
        startWalletEventMonitoring()
        
        // Start observing declarative data sources
        startDataSourceObservation()
        
        // Load wallet - this will fetch initial config and subscribe to wallet events
        print("WalletManager - Loading wallet...")
        try await ndkWallet.load()
        print("WalletManager - Wallet loading finished")
        
        // The wallet's load() method will emit a balanceChanged event
        // which our event monitoring task will catch and update currentBalance
        
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
        }
    }
    
    /// Load wallet from NIP-60 events
    func loadWallet() async throws {
        guard nostrManager.ndk != nil else {
            throw WalletError.ndkNotInitialized
        }
        
        isLoading = true
        defer { isLoading = false }
        
        // Ensure wallet exists (creates if needed)
        try await ensureWalletExists()
        
        guard activeWallet != nil else {
            throw WalletError.noActiveWallet
        }
        
        // Trigger negentropy sync after wallet has loaded
        Task {
            await nostrManager.performStartupSync()
        }
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
                    
                case .mintsAdded(let addedMints):
                    print("WalletManager - Mints added: \(addedMints)")
                    
                case .mintsRemoved(let removedMints):
                    print("WalletManager - Mints removed: \(removedMints)")
                    
                case .balanceChanged(let newBalance):
                    print("WalletManager - Balance changed: \(newBalance)")
                    await MainActor.run {
                        self.currentBalance = newBalance
                    }
                    
                case .nutzapReceived(let amount, let from, let eventId):
                    print("WalletManager - Nutzap received: \(amount) sats from \(from ?? "unknown"), event: \(eventId)")
                    
                    // Create a pending transaction for the incoming nutzap
                    await MainActor.run {
                        let transaction = Transaction(
                            type: .nutzap,
                            amount: Int(amount),
                            memo: "Nutzap received"
                        )
                        transaction.status = .pending
                        transaction.senderPubkey = from
                        transaction.nostrEventID = eventId
                        
                        // Insert at the beginning of the list
                        self.transactions.insert(transaction, at: 0)
                    }
                }
            }
        }
    }
    
    /// Start observing declarative data sources
    private func startDataSourceObservation() {
        // Observe wallet history events
        Task {
            guard let historyDataSource = walletHistoryDataSource else { return }
            
            for await transactions in historyDataSource.$transactions.values {
                await processHistoryTransactions(transactions)
            }
        }
        
        // Observe nutzap events
        Task {
            guard let nutzapDataSource = nutzapDataSource else { return }
            
            for await nutzaps in nutzapDataSource.$nutzaps.values {
                await processNutzaps(nutzaps)
            }
        }
    }
    
    /// Process history transactions from data source
    private func processHistoryTransactions(_ events: [NDKEvent]) async {
        guard let signer = nostrManager.ndk?.signer else { return }
        
        var newTransactions: [Transaction] = []
        
        for event in events {
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
                      let tags = try? JSONCoding.decoder.decode([[String]].self, from: tagsData) else {
                    print("Failed to parse history event tags")
                    continue
                }

                print("tags")
                print(tags)
                
                // Extract transaction info from tags
                var direction: String?
                var amount: Int64?
                var memo: String?
                
                for tag in tags {
                    guard tag.count >= 2 else { continue }
                    switch tag[0] {
                    case "description":
                        memo = tag[1]
                    case "direction":
                        direction = tag[1]
                    case "amount":
                        amount = Int64(tag[1])
                    default:
                        break
                    }
                }
                
                // Check for redeemed marker in clear tags to detect nutzaps
                var redeemedEventId: String?
                var nutzapSender: String?
                if let redeemedTag = event.tags.first(where: { $0.count >= 4 && $0[0] == "e" && $0[3] == "redeemed" }) {
                    redeemedEventId = redeemedTag[1]
                    if redeemedTag.count >= 5 {
                        nutzapSender = redeemedTag[4] // Sender pubkey is in position 4
                    }
                }
                
                // Determine transaction type from tags
                let transactionType: Transaction.TransactionType
                
                // Check for redeemed tag first (indicates nutzap)
                if redeemedEventId != nil {
                    transactionType = .nutzap
                } else if let typeTag = event.tags.first(where: { $0.count >= 2 && $0[0] == "type" }) {
                    switch typeTag[1] {
                    case "nutzap":
                        transactionType = .nutzap
                    default:
                        // Fall back to direction-based type
                        guard let dir = direction else { continue }
                        switch dir {
                        case "in": 
                            transactionType = .receive
                        case "out": 
                            transactionType = .send
                        default: 
                            continue
                        }
                    }
                } else {
                    // Use direction to determine type
                    guard let dir = direction else { continue }
                    switch dir {
                    case "in": 
                        transactionType = .mint  // Lightning deposits or received ecash
                    case "out": 
                        transactionType = .melt  // Lightning payments or sent ecash
                    default: 
                        continue
                    }
                }
                
                // Get amount from encrypted tags or clear tags
                guard let amt = amount ?? extractAmountFromTags(event.tags) else {
                    continue
                }

                // Create transaction with proper memo
                let transactionMemo: String?
                if let memo = memo, !memo.isEmpty {
                    transactionMemo = memo
                } else {
                    // Fallback to type-based description if no memo
                    switch transactionType {
                    case .mint: transactionMemo = "Lightning deposit"
                    case .melt: transactionMemo = "Lightning payment" 
                    case .send: transactionMemo = "Sent ecash"
                    case .receive: transactionMemo = "Received ecash"
                    case .nutzap: 
                        if let sender = nutzapSender {
                            transactionMemo = "Nutzap from \(sender.prefix(8))..."
                        } else {
                            transactionMemo = "Nutzap"
                        }
                    }
                }
                
                let transaction = Transaction(
                    type: transactionType,
                    amount: Int(amt),
                    memo: transactionMemo
                )
                transaction.createdAt = Date(timeIntervalSince1970: TimeInterval(event.createdAt))
                transaction.status = .completed
                
                // Store the nutzap event ID and sender if this is a nutzap transaction
                if let redeemedId = redeemedEventId {
                    transaction.nostrEventID = redeemedId
                    transaction.senderPubkey = nutzapSender
                }
                
                newTransactions.append(transaction)
                
                // Fetch nutzap comment asynchronously if this is a nutzap
                if let eventId = redeemedEventId, let ndk = nostrManager.ndk {
                    Task {
                        let filter = NDKFilter(ids: [eventId])
                        let dataSource = ndk.observe(filter: filter, maxAge: 3600)
                        // Wait for first event
                        for await event in dataSource.events {
                            let nutzapEvent = event
                            let nutzap = NDKNutzap(event: nutzapEvent)
                            await MainActor.run {
                                // Update the transaction with the comment
                                if let existingTransaction = self.transactions.first(where: { 
                                    $0.createdAt == transaction.createdAt && 
                                    $0.amount == transaction.amount 
                                }) {
                                    if let comment = nutzap.comment, !comment.isEmpty {
                                        existingTransaction.memo = comment
                                    }
                                }
                            }
                            break // Only need the first event
                        }
                    }
                }
            } catch {
                print("Failed to process history event: \(error)")
            }
        }
        
        // Update transactions list
        await MainActor.run {
            // For nutzaps, check if we have pending transactions to update
            for transaction in newTransactions {
                if transaction.type == .nutzap && transaction.nostrEventID != nil {
                    // Look for a pending nutzap transaction with matching event ID
                    if let pendingIndex = self.transactions.firstIndex(where: {
                        $0.type == .nutzap &&
                        $0.status == .pending &&
                        $0.nostrEventID == transaction.nostrEventID
                    }) {
                        // Update the pending transaction to completed
                        self.transactions[pendingIndex].status = .completed
                        self.transactions[pendingIndex].createdAt = transaction.createdAt
                        if let memo = transaction.memo {
                            self.transactions[pendingIndex].memo = memo
                        }
                        continue // Don't add a duplicate
                    }
                }
                
                // Check if we already have this transaction
                if !self.transactions.contains(where: { 
                    $0.createdAt == transaction.createdAt && 
                    $0.amount == transaction.amount 
                }) {
                    self.transactions.append(transaction)
                }
            }
            
            // Sort by date (newest first)
            self.transactions.sort { $0.createdAt > $1.createdAt }
        }
    }
    
    /// Process nutzaps from data source
    private func processNutzaps(_ events: [NDKEvent]) async {
        // Nutzaps will be processed through the wallet event monitoring
        // This is here for future enhancement if needed
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
    
    
    /// Create and configure a new wallet with selected mints
    
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
    
    
    // MARK: - Offline Operations
    
    /// Get all unspent proofs grouped by mint for offline sending
    func getUnspentProofsByMint() async throws -> [URL: [CashuSwift.Proof]] {
        guard let wallet = activeWallet else {
            throw WalletError.noActiveWallet
        }
        
        let proofsByMint = await wallet.getUnspentProofs()
        
        // Convert string mint URLs to URL objects
        var result: [URL: [CashuSwift.Proof]] = [:]
        for (mintString, proofs) in proofsByMint {
            if let mintURL = URL(string: mintString) {
                result[mintURL] = proofs
            }
        }
        
        return result
    }
    
    /// Send offline using specific proofs
    func sendOffline(
        proofs: [CashuSwift.Proof],
        mint: URL,
        memo: String?
    ) async throws -> (token: String, transactionId: UUID) {
        guard let wallet = activeWallet else {
            throw WalletError.noActiveWallet
        }
        
        // Create the token without P2PK locking
        let token = try await wallet.createTokenFromProofs(
            proofs: proofs,
            mint: mint,
            memo: memo
        )
        
        // Create transaction record with offline token
        let transaction = Transaction(
            type: .send,
            amount: Int(proofs.reduce(0) { $0 + Int64($1.amount) }),
            memo: memo
        )
        transaction.status = .completed
        transaction.offlineToken = token
        
        modelContext.insert(transaction)
        try modelContext.save()
        
        // Add to transactions array
        await MainActor.run {
            self.transactions.insert(transaction, at: 0)
        }
        
        return (token: token, transactionId: transaction.transactionID)
    }
    
    // MARK: - Send Operations
    
    /// Send ecash tokens
    func send(amount: Int64, memo: String?, fromMint: URL?) async throws -> String {
        guard let wallet = activeWallet else {
            throw WalletError.noActiveWallet
        }
        
        // Create pending transaction immediately
        let transaction = Transaction(
            type: .send,
            amount: Int(amount),
            memo: memo ?? "Sent ecash"
        )
        transaction.status = .pending
        
        // Add to transactions list immediately
        await MainActor.run {
            self.transactions.insert(transaction, at: 0)
        }
        
        do {
            // Select mint if not specified
            let selectedMintURL: URL
            if let fromMint = fromMint {
                selectedMintURL = fromMint
            } else {
                // Auto-select mint with sufficient balance
                let mintURLs = await wallet.mints.getMintURLs()
                let mints = mintURLs.compactMap { URL(string: $0) }
                var selectedMint: URL?
                
                for mint in mints {
                    let balance = await wallet.getBalance(mint: mint)
                    if balance >= amount {
                        selectedMint = mint
                        break
                    }
                }
                
                guard let selected = selectedMint else {
                    throw WalletError.insufficientBalance
                }
                selectedMintURL = selected
            }
            
            // Generate P2PK pubkey for locking
            let p2pkPubkey = try await wallet.getP2PKPubkey()
            
            // Send tokens (creates P2PK locked proofs)
            let (proofs, _) = try await wallet.send(
                amount: amount,
                to: p2pkPubkey,
                mint: selectedMintURL
            )
            
            // Create token from proofs
            let token = CashuSwift.Token(
                proofs: [selectedMintURL.absoluteString: proofs],
                unit: "sat",
                memo: memo
            )
            
            // Encode token
            // Note: JSONCoding.encoder already has sorted keys formatting
            let tokenData = try JSONCoding.encoder.encode(token)
            guard String(data: tokenData, encoding: .utf8) != nil else {
                throw WalletError.encodingError
            }
            
            // Create base64url encoded token
            let base64Token = tokenData.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
            
            let tokenString = "cashuA\(base64Token)"
            
            // Update transaction status to completed
            await MainActor.run {
                if let index = self.transactions.firstIndex(where: { $0.transactionID == transaction.transactionID }) {
                    self.transactions[index].status = .completed
                    self.transactions[index].offlineToken = tokenString
                }
            }
            
            // Create history event for sending ecash
            Task {
                do {
                    guard let ndk = nostrManager.ndk,
                          let signer = ndk.signer else { return }
                    
                    try await wallet.eventManager.createSpendingHistoryEvent(
                        direction: .out,
                        amount: amount,
                        memo: memo ?? "Sent ecash",
                        signer: signer
                    )
                } catch {
                    print("Failed to create history event for send: \(error)")
                }
            }
            
            return tokenString
        } catch {
            // Update transaction status to failed
            await MainActor.run {
                if let index = self.transactions.firstIndex(where: { $0.transactionID == transaction.transactionID }) {
                    self.transactions[index].status = .failed
                }
            }
            throw error
        }
    }
    
    // MARK: - Receive Operations
    
    /// Receive ecash tokens
    func receive(tokenString: String) async throws -> Int64 {
        guard let wallet = activeWallet else {
            throw WalletError.noActiveWallet
        }
        
        // Parse token string to get amount first
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
              let token = try? JSONCoding.decoder.decode(CashuSwift.Token.self, from: tokenData) else {
            throw WalletError.invalidToken
        }
        
        // Calculate total amount from token
        let totalAmount = token.proofsByMint.values.reduce(0) { sum, proofs in
            sum + proofs.reduce(0) { $0 + Int64($1.amount) }
        }
        
        // Create pending transaction immediately
        let transaction = Transaction(
            type: .receive,
            amount: Int(totalAmount),
            memo: token.memo ?? "Received ecash"
        )
        transaction.status = .pending
        
        // Add to transactions list immediately
        await MainActor.run {
            self.transactions.insert(transaction, at: 0)
        }
        
        do {
            var totalReceived: Int64 = 0
            
            // Process proofs from each mint
            for (_, proofs) in token.proofsByMint {
                // Receive the proofs - wallet can handle proofs from any mint
                try await wallet.receive(proofs: proofs)
                
                // Calculate total
                totalReceived += proofs.reduce(0) { $0 + Int64($1.amount) }
            }
            
            // Update transaction status to completed
            await MainActor.run {
                if let index = self.transactions.firstIndex(where: { $0.transactionID == transaction.transactionID }) {
                    self.transactions[index].status = .completed
                }
            }
            
            // Create history event for receiving ecash
            if totalReceived > 0 {
                Task {
                    do {
                        guard let ndk = nostrManager.ndk,
                              let signer = ndk.signer else { return }
                        
                        try await wallet.eventManager.createSpendingHistoryEvent(
                            direction: .in,
                            amount: totalReceived,
                            memo: token.memo ?? "Received ecash",
                            signer: signer
                        )
                    } catch {
                        print("Failed to create history event for receive: \(error)")
                    }
                }
            }
            
            return totalReceived
        } catch {
            // Update transaction status to failed
            await MainActor.run {
                if let index = self.transactions.firstIndex(where: { $0.transactionID == transaction.transactionID }) {
                    self.transactions[index].status = .failed
                }
            }
            throw error
        }
    }
    
    // MARK: - Lightning Operations
    
    /// Pay a Lightning invoice
    func payLightning(invoice: String, amount: Int64) async throws -> String {
        guard let wallet = activeWallet else {
            throw WalletError.noActiveWallet
        }
        
        // Create pending transaction immediately
        let transaction = Transaction(
            type: .melt,
            amount: Int(amount),
            memo: "Lightning payment"
        )
        transaction.status = .pending
        transaction.lightningInvoice = invoice
        
        // Add to transactions list immediately
        await MainActor.run {
            self.transactions.insert(transaction, at: 0)
        }
        
        do {
            let (preimage, feePaid) = try await wallet.payLightning(
                invoice: invoice,
                amount: amount
            )
            
            print("Paid Lightning invoice: \(amount) sats, fee: \(feePaid ?? 0) sats")
            
            // Update transaction status to completed
            await MainActor.run {
                if let index = self.transactions.firstIndex(where: { $0.transactionID == transaction.transactionID }) {
                    self.transactions[index].status = .completed
                    // The history event will provide more details
                }
            }
            
            return preimage
        } catch {
            // Update transaction status to failed
            await MainActor.run {
                if let index = self.transactions.firstIndex(where: { $0.transactionID == transaction.transactionID }) {
                    self.transactions[index].status = .failed
                }
            }
            throw error
        }
    }
    
    // MARK: - Nutzap Operations
    
    /// Send a nutzap
    func sendNutzap(
        to recipient: String,
        amount: Int64,
        comment: String?,
        acceptedMints: [URL]
    ) async throws {
        print("🚀 WalletManager.sendNutzap called - recipient: \(recipient), amount: \(amount), acceptedMints: \(acceptedMints)")
        
        guard let wallet = activeWallet else {
            print("❌ No active wallet!")
            throw WalletError.noActiveWallet
        }
        
        // Create pending transaction immediately
        let transaction = Transaction(
            type: .send,  // Use send type for outgoing nutzaps
            amount: Int(amount),
            memo: comment ?? "Nutzap sent"
        )
        transaction.status = .pending
        // Note: For outgoing nutzaps, we don't set senderPubkey as that's for incoming
        
        // Add to transactions list immediately
        await MainActor.run {
            self.transactions.insert(transaction, at: 0)
        }
        
        do {
            // Create nutzap request
            let request = NutzapPaymentRequest(
                amountSats: amount,
                recipientPubkey: recipient,
                recipientP2PK: "", // Empty P2PK for now, will be set by wallet
                acceptedMints: acceptedMints,
                comment: comment
            )
            
            print("💳 Created NutzapPaymentRequest, calling wallet.pay()")
            
            // Send nutzap
            _ = try await wallet.pay(request)
            
            print("✅ Nutzap completed successfully!")
            
            // Update transaction status to completed
            await MainActor.run {
                if let index = self.transactions.firstIndex(where: { $0.transactionID == transaction.transactionID }) {
                    self.transactions[index].status = .completed
                }
            }
        } catch {
            // Update transaction status to failed
            await MainActor.run {
                if let index = self.transactions.firstIndex(where: { $0.transactionID == transaction.transactionID }) {
                    self.transactions[index].status = .failed
                }
            }
            throw error
        }
    }
    
    // MARK: - Mint Management
    
    
    
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
        guard activeWallet != nil else {
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
        
        // Fetch events from cache or relays using data sources
        let tokenDataSource = ndk.observe(filter: tokenFilter, maxAge: 3600)
        let deletionDataSource = ndk.observe(filter: deletionFilter, maxAge: 3600)
        
        // Collect events
        var tokenEvents: [NDKEvent] = []
        var deletionEvents: [NDKEvent] = []
        
        // Use a timeout for collecting events
        let fetchTask = Task {
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    for await event in tokenDataSource.events {
                        tokenEvents.append(event)
                    }
                }
                group.addTask {
                    for await event in deletionDataSource.events {
                        deletionEvents.append(event)
                    }
                }
                // Wait for a reasonable timeout
                try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
                group.cancelAll()
            }
        }
        
        await fetchTask.value
        
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
        
        return try JSONCoding.decoder.decode(NIP60TokenEvent.self, from: data)
    }
    
    /// Check proof states for specific proofs
    func checkProofStates(for proofs: [CashuSwift.Proof], mint mintURL: String) async throws -> [String: CashuSwift.Proof.ProofState] {
        guard let wallet = activeWallet else {
            throw WalletError.noActiveWallet
        }
        
        guard URL(string: mintURL) != nil else {
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
    
    // MARK: - Session Management
    
    /// Clear all wallet data and cancel active subscriptions (called during logout)
    func clearWalletData() {
        // Cancel active subscriptions
        walletEventTask?.cancel()
        walletEventTask = nil
        
        // Clear data sources
        walletEventDataSource = nil
        walletHistoryDataSource = nil
        nutzapDataSource = nil
        
        // Clear wallet state
        activeWallet = nil
        transactions.removeAll()
        currentBalance = 0
        
        print("WalletManager - Cleared all wallet data and cancelled subscriptions")
    }
    
    // MARK: - Health Monitoring
    
    /// Get wallet reference for health monitoring
    var wallet: NIP60Wallet? {
        return activeWallet
    }
    
    // MARK: - Pending Transactions
    
    /// Calculate total pending amount (outgoing is negative, incoming is positive)
    var pendingAmount: Int64 {
        transactions
            .filter { $0.status == .pending }
            .reduce(0) { sum, transaction in
                switch transaction.type {
                case .send, .melt, .nutzap:
                    return sum - Int64(transaction.amount)
                case .receive, .mint:
                    return sum + Int64(transaction.amount)
                }
            }
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