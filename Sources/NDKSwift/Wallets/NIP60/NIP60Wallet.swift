import Foundation
import CashuSwift
import secp256k1

/// NIP-60 wallet implementation for Cashu-based wallets
public actor NIP60Wallet: NDKPaymentProvider {
    // MARK: - Properties
    
    public let id = "nip60"
    public let displayName = "Cashu Wallet"
    
    internal let ndk: NDK
    public let p2pkManager: P2PKManager // Manages P2PK keys for receiving nutzaps
    
    // Relay health monitoring
    public internal(set) var walletRelays: [NDKRelay] = []
    
    // Wallet configuration relays (from kind 17375 event)
    public internal(set) var walletConfigRelays: [String] = []
    
    // Wallet subscriptions
    private var configSubscriptionTask: Task<Void, Never>?
    private var walletSubscriptionTask: Task<Void, Never>?
    
    // MARK: - Managers
    
    public let proofStateManager = ProofStateManager()
    public let eventManager: WalletEventManager
    public let healthMonitor: WalletHealthMonitor
    public let mints: MintManager
    private let eventProcessor = WalletEventProcessor()
    public let transactionHistory: WalletTransactionHistory

    private let signer: NDKSigner
    
    // MARK: - Quote Tracking
    
    private var activeQuoteMonitors: [String: Task<Void, Never>] = [:] // quoteId -> monitoring task
    
    // MARK: - Event Stream
    
    public let events = NIP60WalletEventStream()
    
    // MARK: - Blacklist Cache
    
    private var cachedBlacklistedMints: Set<String> = []
    private var blacklistLastFetched: Date?
    
    // MARK: - Configuration State
    
    private var newestConfigTimestamp: Timestamp = 0
    private var hasProcessedInitialConfig = false
    
    // MARK: - Startup Nutzap Redemption
    
    private var startupRedemption: StartupNutzapRedemption?
    
    // MARK: - Initialization
    
    public init(ndk: NDK, cache: NDKCache? = nil) throws {
        let signer: NDKSigner
        do {
            signer = try ndk.requireSigner()
        } catch {
            throw NDKError.notConfigured("NIP60Wallet requires a signer configured on NDK")
        }
        
        self.ndk = ndk
        self.signer = signer
        self.p2pkManager = P2PKManager()
        self.eventManager = WalletEventManager(ndk: ndk)
        self.mints = MintManager(cache: cache ?? ndk.cache)
        self.healthMonitor = WalletHealthMonitor(
            eventManager: eventManager,
            ndk: ndk
        )
        self.transactionHistory = WalletTransactionHistory(
            ndk: ndk,
            signer: signer,
            eventManager: eventManager,
            eventStream: events
        )
    }
    
    // MARK: - Configuration Subscription
    
    
    /// Process configuration events (17375 and 10020)
    private func processConfigurationEvent(_ event: NDKEvent) async {
        switch event.kind {
        case EventKind.cashuWalletConfig:  // 17375
            
            // Only process if this is newer than what we've seen
            if event.createdAt <= newestConfigTimestamp {
                NDKLogger.log(.debug, category: .wallet, "⏭️ Skipping older wallet configuration (timestamp: \(event.createdAt) <= \(newestConfigTimestamp))")
                return
            }
            
            // Update our newest timestamp
            newestConfigTimestamp = event.createdAt
            
            // Process wallet configuration
            await processWalletConfiguration(event: event)
            
            // Only restart wallet subscriptions if we've already processed initial config
            if hasProcessedInitialConfig {
                // Restart wallet event subscriptions with new config
                await startWalletEventSubscription()
            }
            
        case EventKind.blockedMints:  // Blocked mints
            await processBlockedMintsUpdate(event)
            
        default:
            break
        }
    }
    
    // MARK: - Wallet Event Subscription
    
    /// Start the wallet event subscription after receiving configuration
    private func startWalletEventSubscription() async {
        // Cancel any existing wallet subscription
        walletSubscriptionTask?.cancel()
        
        walletSubscriptionTask = Task {
            do {
                let userPubkey = try await signer.pubkey
                let twentyFourHoursAgo = Timestamp.from(Date(timeIntervalSinceNow: -TimeConstants.day))
                
                // Create filters for wallet events
                let filters = [
                    // Recent quotes (kind 7374)
                    NDKFilter(
                        authors: [userPubkey],
                        kinds: [EventKind.cashuQuote],
                        since: twentyFourHoursAgo
                    ),
                    // All tokens (kind 7375)
                    NDKFilter(
                        authors: [userPubkey],
                        kinds: [EventKind.cashuToken]
                    ),
                    // Delete events
                    NDKFilter(
                        authors: [userPubkey],
                        kinds: [EventKind.deletion],
                        tags: ["k": Set([String(EventKind.cashuToken), String(EventKind.cashuQuote)])]
                    ),
                    // Incoming nutzaps
                    NDKFilter(
                        kinds: [EventKind.nutzap],
                        tags: ["p": Set([userPubkey])]
                    ),
                    // Spending history (kind 7376)
                    NDKFilter(
                        authors: [userPubkey],
                        kinds: [EventKind.cashuSpendingHistory]
                    )
                ]
                
                // Use wallet-specific relays if configured from 17375 event
                let relayUrls: Set<String>? = walletConfigRelays.isEmpty ? nil : Set(walletConfigRelays)
                
                NDKLogger.log(.debug, category: .wallet, "📡 Starting wallet event subscription with \(walletConfigRelays.isEmpty ? "default" : "\(walletConfigRelays.count) configured") relays")
                
                // Create NDKDataSource for each filter
                var dataSources: [NDKDataSource<NDKEvent>] = []
                var nutzapDataSource: NDKDataSource<NDKEvent>?
                var spendingHistoryDataSource: NDKDataSource<NDKEvent>?
                
                for (index, filter) in filters.enumerated() {
                    let subscriptionId: String
                    switch index {
                    case 0: subscriptionId = "nip60-quotes"
                    case 1: subscriptionId = "nip60-tokens"
                    case 2: subscriptionId = "nip60-deletes"
                    case 3: subscriptionId = "nip60-nutzaps"
                    case 4: subscriptionId = "nip60-spending-history"
                    default: subscriptionId = "nip60-wallet-\(index)"
                    }
                    
                    let dataSource = NDKDataSource(
                        ndk: self.ndk,
                        filter: filter,
                        maxAge: 0,
                        cachePolicy: .cacheWithNetwork,
                        relays: relayUrls,
                        subscriptionId: subscriptionId
                    )
                    dataSources.append(dataSource)
                    
                    // Track specific data sources for EOSE monitoring
                    if index == 3 { nutzapDataSource = dataSource }
                    if index == 4 { spendingHistoryDataSource = dataSource }
                }
                
                // Monitor EOSE for nutzap and spending history
                if let nutzapDS = nutzapDataSource {
                    Task {
                        for await update in nutzapDS.relayUpdates {
                            if case .eose = update {
                                await self.startupRedemption?.markNutzapEoseReceived()
                                break
                            }
                        }
                    }
                }
                
                if let spendingHistoryDS = spendingHistoryDataSource {
                    Task {
                        for await update in spendingHistoryDS.relayUpdates {
                            if case .eose = update {
                                await self.startupRedemption?.markSpendingHistoryEoseReceived()
                                break
                            }
                        }
                    }
                }
                
                // Process wallet events
                await withTaskGroup(of: Void.self) { group in
                    for dataSource in dataSources {
                        group.addTask {
                            for await event in dataSource.events {
                                await self.processWalletEvent(event)
                            }
                        }
                    }
                }
            } catch {
                if error is CancellationError {
                    NDKLogger.log(.debug, category: .wallet, "🛑 Wallet event subscription cancelled")
                } else {
                    NDKLogger.log(.debug, category: .wallet, "❌ Wallet event subscription error: \(error)")
                }
            }
        }
    }
    
    /// Process a wallet event (tokens, quotes, nutzaps, etc)
    private func processWalletEvent(_ event: NDKEvent) async {
        // During startup, handle nutzaps and spending history specially
        if let startupRedemption = startupRedemption {
            switch event.kind {
            case EventKind.nutzap:
                // Track nutzap for batch redemption after EOSE
                await startupRedemption.trackNutzap(event)
                // Also process normally to track in event manager
                await eventManager.trackNutzap(event)
                return
                
            case EventKind.cashuSpendingHistory:
                // Process spending history to mark redeemed nutzaps
                await startupRedemption.processSpendingHistory(event)
                // Continue with normal processing
                break
                
            default:
                break
            }
        }
        
        // Create context for handlers
        let context = WalletEventContext(
            wallet: self,
            proofStateManager: proofStateManager,
            eventManager: eventManager,
            p2pkManager: p2pkManager,
            signer: signer
        )
        
        // Process event using consolidated processor
        await eventProcessor.processEvent(event, context: context)
        
        // Check if balance changed after processing token events
        if event.kind == EventKind.cashuToken {
            await notifyBalanceChangeIfNeeded()
        }
    }
    
    
    /// Process wallet configuration from event
    /// This method extracts mints, relays, and P2PK keys from a wallet configuration event.
    /// Note: Mints that fail to load (e.g., due to network errors) will be skipped and not added to the wallet.
    internal func processWalletConfiguration(event: NDKEvent) async {
        
        NDKLogger.log(.debug, category: .wallet, "⚙️ Processing wallet configuration")
        NDKLogger.log(.debug, category: .wallet, "⚙️ Event ID: \(event.id)")
        NDKLogger.log(.debug, category: .wallet, "⚙️ Event Kind: \(event.kind)")
        
        let walletEvent = NDKCashuWalletEvent(event: event)
        
        // Process relay tags (unencrypted, no signer needed)
        walletConfigRelays = walletEvent.relays
        walletRelays = walletEvent.relays.compactMap { NDKRelay(url: $0) }
        NDKLogger.log(.debug, category: .wallet, "📡 Extracted \(walletRelays.count) wallet relays from wallet event")
        
        do {
            // Get current mints before update
            let previousMints = Set(await mints.getMintURLs())
            
            // Process P2PK private key
            if let privkey = try await walletEvent.privateKey(signer: signer) {
                NDKLogger.log(.debug, category: .wallet, "🔑 Found P2PK private key in wallet config: \(privkey.prefix(StringConstants.DisplayFormatting.hexPrefixLength))...")
                try? await p2pkManager.restoreFromPrivateKey(privkey)
            } else {
                NDKLogger.log(.debug, category: .wallet, "🔑 No P2PK private key found in wallet config")
            }
            
            // Process mints
            let mintURLs = try await walletEvent.mints(signer: signer)
            NDKLogger.log(.debug, category: .wallet, "🏪 Extracted \(mintURLs.count) mint URLs from wallet config: \(mintURLs)")
            
            // Get current blacklisted mints
            let blacklistedMints = await getBlacklistedMints()
            if !blacklistedMints.isEmpty {
                NDKLogger.log(.info, category: .wallet, "Found \(blacklistedMints.count) blacklisted mints")
            }
            
            // Filter out blacklisted mints
            let configuredMints = Set(mintURLs).subtracting(blacklistedMints)
            
            // Remove mints that are no longer in the configuration
            let mintsToRemove = previousMints.subtracting(configuredMints)
            for mintURL in mintsToRemove {
                guard let url = URL(string: mintURL) else { continue }
                _ = await mints.removeMint(url: url)
                NDKLogger.log(.debug, category: .wallet, "🗑 Removed mint no longer in config: \(mintURL)")
            }
            
            // Add new mints from configuration
            var successfullyAddedMints = Set<String>()
            
            for mintURL in mintURLs {
                guard let url = URL(string: mintURL) else { 
                    NDKLogger.log(.debug, category: .wallet, "⚠️ Invalid mint URL: \(mintURL)")
                    continue 
                }
                
                // Skip if blacklisted
                if blacklistedMints.contains(mintURL) {
                    NDKLogger.log(.debug, category: .wallet, "🚫 Skipping blacklisted mint: \(mintURL)")
                    continue
                }
                
                // Skip if already exists
                if previousMints.contains(mintURL) {
                    successfullyAddedMints.insert(mintURL)
                    continue
                }
                
                await mints.addMintURL(url: url)
                successfullyAddedMints.insert(mintURL)
                NDKLogger.log(.debug, category: .wallet, "✅ Added mint URL: \(mintURL)")
            }
            
            // Get the actual current mints from MintManager after updates
            let actualCurrentMints = Set(await mints.getMintURLs())
            
            // Determine what changed based on actual MintManager state
            let addedMints = actualCurrentMints.subtracting(previousMints)
            let removedMints = previousMints.subtracting(actualCurrentMints)
            
            // Emit events
            if !addedMints.isEmpty || !removedMints.isEmpty {
                let currentMintList = Array(actualCurrentMints)
                
                events.yield(NIP60WalletEvent(type: .configurationUpdated(mints: currentMintList)))
                
                if !addedMints.isEmpty {
                    events.yield(NIP60WalletEvent(type: .mintsAdded(Array(addedMints))))
                }
                
                if !removedMints.isEmpty {
                    events.yield(NIP60WalletEvent(type: .mintsRemoved(Array(removedMints))))
                }
            }
            
            NDKLogger.log(.debug, category: .wallet, "✅ Wallet configuration updated:")
            NDKLogger.log(.debug, category: .wallet, "  - Requested mints: \(mintURLs.count)")
            NDKLogger.log(.debug, category: .wallet, "  - Successfully added: \(successfullyAddedMints.count)")
            NDKLogger.log(.debug, category: .wallet, "  - Total active mints: \(actualCurrentMints.count)")
            NDKLogger.log(.debug, category: .wallet, "  - Active mint URLs: \(actualCurrentMints)")
        } catch {
            NDKLogger.log(.debug, category: .wallet, "❌ Failed to parse wallet configuration: \(error)")
        }
    }
    
    // MARK: - Blacklist Management
    
    /// Get the set of blacklisted mint URLs from the cached blocked mints list
    /// This returns the cached value that is kept up-to-date by the configuration subscription
    public func getBlacklistedMints() async -> Set<String> {
        return cachedBlacklistedMints
    }
    
    /// Add a mint to the blacklist and publish the updated blocked mints event
    public func blacklistMint(_ mintURL: String) async throws {
        NDKLogger.log(.info, category: .wallet, "Adding mint to blacklist: \(mintURL)")
        
        // Get current blocked mints
        var updatedBlockedMints = cachedBlacklistedMints
        updatedBlockedMints.insert(mintURL)
        
        // Publish the updated blocked mints event
        _ = try await NDKBlockedMintsEvent.createAndPublish(
            ndk: ndk,
            blockedMints: Array(updatedBlockedMints),
            signer: signer
        )
        
        // Update local cache
        cachedBlacklistedMints = updatedBlockedMints
        blacklistLastFetched = Date()
        
        // Remove the mint from wallet if it exists
        if let url = URL(string: mintURL) {
            _ = await mints.removeMint(url: url)
        }
        
        // Emit event about mint being removed
        events.yield(NIP60WalletEvent(type: .mintsRemoved([mintURL])))
        
        NDKLogger.log(.info, category: .wallet, "Successfully blacklisted mint: \(mintURL)")
    }
    
    /// Process blocked mints update event (kind 10020)
    private func processBlockedMintsUpdate(_ event: NDKEvent) async {
        NDKLogger.log(.info, category: .wallet, "Processing blocked mints update")
        
        // Update cached blacklisted mints
        let blockedMintsEvent = NDKBlockedMintsEvent(event: event)
        let newBlacklistedMints = Set(blockedMintsEvent.blockedMints)
        let oldBlacklistedMints = cachedBlacklistedMints
        
        cachedBlacklistedMints = newBlacklistedMints
        blacklistLastFetched = Date()
        
        // Find newly blacklisted mints
        let newlyBlacklisted = newBlacklistedMints.subtracting(oldBlacklistedMints)
        
        if !newlyBlacklisted.isEmpty {
            NDKLogger.log(.info, category: .wallet, "Found \(newlyBlacklisted.count) newly blacklisted mints")
            
            // Remove any newly blacklisted mints from wallet
            let currentMints = await mints.getMintURLs()
            for mintURL in newlyBlacklisted {
                if currentMints.contains(mintURL) {
                    NDKLogger.log(.warning, category: .wallet, "Removing newly blacklisted mint from wallet: \(mintURL)")
                    if let url = URL(string: mintURL) {
                        _ = await mints.removeMint(url: url)
                    }
                }
            }
            
            // Emit event about mints being removed
            if !newlyBlacklisted.isEmpty {
                events.yield(NIP60WalletEvent(type: .mintsRemoved(Array(newlyBlacklisted))))
            }
        }
    }
    
    // MARK: - NDKPaymentProvider Protocol
    
    public func isAvailable() async -> Bool {
        // Check if wallet has any mints configured and balance
        let mintURLs = await mints.getMintURLs()
        guard !mintURLs.isEmpty else { return false }
        
        // Check if we have any balance
        let balance = await proofStateManager.getTotalBalance()
        return balance > 0
    }
    
    public func fulfill(_ request: PaymentRequest) async throws -> PaymentConfirmation {
        return try await WalletPaymentRouter.executePayment(
            request,
            wallet: self,
            mints: mints,
            proofStateManager: proofStateManager,
            eventManager: eventManager,
            ndk: ndk,
            signer: signer
        )
    }
    
    public func canFulfill(_ request: PaymentRequest) async -> Bool {
        // We can handle nutzap payments
        if request is NutzapPaymentRequest {
            return true
        }
        
        // We can handle lightning invoice payments via melt
        if request is LightningInvoiceRequest {
            return true
        }
        
        return false
    }
    
    public func getBalance() async throws -> Int64? {
        let balance = await proofStateManager.getTotalBalance()
        return balance
    }
    
    /// Get balance for a specific mint
    public func getBalance(mint: URL) async -> Int64 {
        let proofs = await proofStateManager.getAvailableProofs(mint: mint.absoluteString)
        return proofs.reduce(0) { $0 + Int64($1.amount) }
    }
    
    /// Get balances grouped by mint
    /// Returns a dictionary mapping mint URLs to their balances
    public func getBalancesByMint() async -> [String: Int64] {
        var balancesByMint: [String: Int64] = [:]
        
        // Get proofs already grouped by mint from the proof state manager
        let proofsByMint = await proofStateManager.getAvailableProofsByMint()
        
        // Calculate balance for each mint
        for (mint, proofs) in proofsByMint {
            let balance = proofs.reduce(0) { $0 + Int64($1.amount) }
            if balance > 0 {
                balancesByMint[mint] = balance
            }
        }
        
        return balancesByMint
    }
    
    public func createInvoice(amount: Int64, description: String?) async throws -> String {
        // Create a Lightning invoice through one of our mints
        let mintURLs = await mints.getMintURLs()
        guard let mintURL = mintURLs.first else {
            throw NDKError.noMintAvailable("No mint configured")
        }
        
        // Request a mint quote (Lightning invoice) from the mint
        let quote = try await requestMint(
            amount: amount,
            mintURL: mintURL,
            persistQuote: true // Save the quote so we can check payment status later
        )
        
        // Return the Lightning invoice
        return quote.invoice
    }
    
    
    
    // MARK: - Nutzap Receiving
    
    /// Process an incoming nutzap event
    internal func processIncomingNutzap(_ event: NDKEvent) async throws {
        do {
            let mints = await mints.getAllMints()
            let keysets = mints.values.flatMap { $0.keysets }.reduce(into: [:]) { result, keyset in
                result[keyset.keysetID] = keyset
            }
            
            // Process the nutzap
            _ = try await Nutzap.processIncoming(
                wallet: self,
                event: event,
                mints: mints,
            keysets: keysets,
            proofStateManager: proofStateManager,
            eventManager: eventManager,
            p2pkManager: p2pkManager,
            ndk: ndk,
            signer: signer
        )
        
        // Success - the status is already updated by processIncoming
        } catch {
            // Map error and update status
            let redemptionError = Nutzap.mapToRedemptionError(error)
            
            // Update status with error
            await eventManager.updateNutzapStatus(
                event.id,
                status: .failed(
                    error: redemptionError,
                    attempts: 1,
                    lastAttempt: .now
                )
            )
            
            // Update transaction status to failed with error details
            await transactionHistory.updateNutzapTransactionStatus(
                nutzapEventId: event.id,
                status: .failed,
                errorDetails: redemptionError.localizedDescription
            )
            
            // Re-throw the error for upstream handling
            throw error
        }
    }
    
    // MARK: - Additional Methods
    
    /// Get the P2PK pubkey for receiving nutzaps
    public func getP2PKPubkey() async throws -> String {
        return try await p2pkManager.getCashuPublicKey()
    }
    
    /// Get P2PK private key - needed for wallet configuration events
    public func getP2PKPrivateKey() async throws -> String {
        let (privateKey, _) = try await p2pkManager.getOrCreateKeypair()
        return privateKey
    }
    
    /// NDKPaymentProvider compatibility - pay a payment request
    public func pay(_ request: PaymentRequest) async throws -> PaymentConfirmation {
        return try await fulfill(request)
    }
    
    
    
    /// Send P2PK-locked proofs to a recipient
    public func send(
        amount: Int64,
        to recipientP2PK: String,
        mint mintURL: URL
    ) async throws -> (proofs: [CashuSwift.Proof], change: [CashuSwift.Proof]?) {
        let mints = await mints.getAllMints()
        return try await Payment.sendP2PK(
            wallet: self,
            amount: amount,
            to: recipientP2PK,
            mint: mintURL,
            mints: mints,
            proofStateManager: proofStateManager,
            signer: signer
        )
    }
    
    /// Pay a Lightning invoice through a mint
    public func payLightning(invoice: String, amount: Int64) async throws -> (preimage: String, feePaid: Int64?) {
        let mints = await mints.getAllMints()
        return try await Payment.payLightning(
            wallet: self,
            invoice: invoice,
            amount: amount,
            mints: mints,
            proofStateManager: proofStateManager,
            eventManager: eventManager,
            signer: signer
        )
    }
    
    
    /// Transfer funds between mints using Lightning as a bridge
    /// This performs a melt operation on the source mint and a mint operation on the destination mint
    public func transferBetweenMints(
        amount: Int64,
        fromMint sourceMintURL: URL,
        toMint destinationMintURL: URL
    ) async throws -> TransferResult {
        return try await CrossMintTransfer.transferBetweenMints(
            amount: amount,
            from: sourceMintURL,
            to: destinationMintURL,
            wallet: self,
            proofStateManager: proofStateManager,
            eventManager: eventManager,
            mints: mints,
            signer: signer
        )
    }
    
    
    /// Check proof states with all mints and reconcile wallet state
    /// This queries each mint for the status of our proofs and updates our local state accordingly
    public func checkAndReconcileProofStates() async throws {
        let mints = await mints.getAllMints()
        let result = try await healthMonitor.checkAndReconcileProofStates(
            proofStateManager: proofStateManager,
            mints: mints,
            mintManager: self.mints,
            signer: signer
        )
        
        NDKLogger.log(.debug, category: .wallet, "🔍 Reconciliation complete - Checked: \(result.totalChecked), Spent: \(result.spentProofs.count), Pending: \(result.pendingProofs.count), Errors: \(result.errors)")
    }
    
    
    
    
    /// Check proof states for a specific mint
    public func checkProofStates(mintURL: URL) async throws -> [String: CashuSwift.Proof.ProofState] {
        let allMints = await mints.getAllMints()
        let mint: CashuSwift.Mint
        
        if let existingMint = allMints[mintURL.absoluteString] {
            mint = existingMint
        } else {
            // Mint not configured - load it on demand
            NDKLogger.log(.info, category: .wallet, "Loading unconfigured mint on-demand: \(mintURL)")
            mint = try await mints.loadMint(url: mintURL)
        }
        
        // Get all proofs for this mint
        let mintProofs = await proofStateManager.getAvailableProofs(mint: mintURL.absoluteString)
        
        guard !mintProofs.isEmpty else {
            return [:]
        }
        
        // Check with mint
        let states = try await CashuSwift.check(mintProofs, mint: mint)
        
        // Build result dictionary
        var result: [String: CashuSwift.Proof.ProofState] = [:]
        for (index, proof) in mintProofs.enumerated() {
            result[proof.C] = states[index]
        }
        
        return result
    }
    
    
    /// Request a mint quote for depositing via Lightning
    public func requestMint(
        amount: Int64,
        mintURL: String,
        persistQuote: Bool = false
    ) async throws -> CashuMintQuote {
        let (quote, _) = try await CashuDeposit.requestMintQuote(
            amount: amount,
            mintURL: mintURL,
            mints: mints,
            eventManager: eventManager,
            persistQuote: persistQuote,
            signer: signer
        )
        return quote
    }
    
    /// Monitor deposit status for a mint quote (checking if Lightning invoice was paid)
    /// 
    /// This method monitors a mint quote to check if the associated Lightning invoice has been paid.
    /// It automatically checks at progressive intervals (starting at 2 minutes, increasing based on quote age).
    /// 
    /// - Parameters:
    ///   - quote: The mint quote to monitor
    ///   - timeout: Maximum time to monitor before giving up (default: 600 seconds / 10 minutes)
    ///   - manualCheckTrigger: Optional AsyncStream that allows manual triggering of status checks.
    ///                         Yield a value to this stream to immediately check the payment status
    ///                         instead of waiting for the automatic interval.
    /// 
    /// - Returns: An AsyncThrowingStream that yields DepositStatus updates
    /// 
    /// Example with manual check trigger:
    /// ```swift
    /// // Create a manual trigger stream
    /// let (triggerStream, triggerContinuation) = AsyncStream<Void>.makeStream()
    /// 
    /// // Monitor with manual trigger
    /// let monitorTask = Task {
    ///     for try await status in wallet.monitorDeposit(
    ///         quote: quote,
    ///         manualCheckTrigger: triggerStream
    ///     ) {
    ///         switch status {
    ///         case .pending:
    ///             NDKLogger.log(.debug, category: .wallet, "Waiting for payment...")
    ///         case .minted(let proofs):
    ///             NDKLogger.log(.debug, category: .wallet, "Payment received!")
    ///         // ... handle other cases
    ///         }
    ///     }
    /// }
    /// 
    /// // Trigger immediate check (e.g., from button press)
    /// triggerContinuation.yield()
    /// ```
    public func monitorDeposit(
        quote: CashuMintQuote,
        timeout: TimeInterval = 600.0,
        manualCheckTrigger: AsyncStream<Void>? = nil
    ) -> AsyncThrowingStream<DepositStatus, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let stream = CashuDeposit.monitorDeposit(
                        quote: quote,
                        quoteEventId: nil, // New quote, no event ID yet
                        mints: self.mints,
                        eventManager: self.eventManager,
                        signer: signer,
                        timeout: timeout,
                        quoteAge: 0, // New quote, no age
                        onProofsReceived: { proofs in
                            // Update wallet state with new proofs
                            let stateChange = WalletStateChange(
                                store: proofs,
                                destroy: [],
                                mint: quote.mintURL,
                                memo: "Deposit"
                            )
                            return try await self.update(stateChange: stateChange)
                        },
                        manualCheckTrigger: manualCheckTrigger
                    )
                    
                    for try await status in stream {
                        continuation.yield(status)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    
    
    /// Initialize wallet by subscribing to wallet events
    public func load() async throws {
        // Clear state before starting
        await proofStateManager.clear()
        await eventManager.clearTrackedEvents()
        await transactionHistory.clear()
        walletConfigRelays = []
        newestConfigTimestamp = 0
        hasProcessedInitialConfig = false
        
        
        // Cancel any existing subscriptions
        configSubscriptionTask?.cancel()
        walletSubscriptionTask?.cancel()
        
        // Stop any existing quote monitors
        await stopQuoteMonitors()
        
        let userPubkey = try await signer.pubkey
        
        NDKLogger.log(.debug, category: .wallet, "📡 Starting wallet configuration subscription...")
        
        // Start configuration subscription and wait for EOSE
        configSubscriptionTask = Task {
            // Create filter for configuration events (17375 and 10020)
            let configFilter = NDKFilter(
                authors: [userPubkey],
                kinds: [EventKind.cashuWalletConfig, EventKind.blockedMints]
            )
            
            NDKLogger.log(.info, category: .wallet, "Starting wallet configuration subscription for kinds [17375, \(EventKind.blockedMints)]")
            
            // Create NDKDataSource for configuration events
            let dataSource = NDKDataSource(
                ndk: self.ndk,
                filter: configFilter,
                maxAge: 0,
                cachePolicy: .cacheWithNetwork,
                subscriptionId: "nip60-wallet-config"
            )
            
            // Track EOSE status
            var receivedEOSE = false
            var eoseTask: Task<Void, Never>?
            
            // Monitor relay updates for EOSE
            eoseTask = Task {
                for await update in dataSource.relayUpdates {
                    if case .eose = update, !receivedEOSE {
                        receivedEOSE = true
                        NDKLogger.log(.info, category: .wallet, "📡 Configuration EOSE received. Starting wallet event subscriptions...")
                        
                        // Log the initial balance
                        let initialBalance = await self.proofStateManager.getTotalBalance()
                        NDKLogger.log(.info, category: .wallet, "💰 Initial wallet balance: \(initialBalance) sats")
                        
                        // Emit balance change event if we have a non-zero balance
                        await self.notifyBalanceChangeIfNeeded()
                        
                        // Start transaction history observation
                        try? await self.transactionHistory.startObserving()
                        
                        // Start wallet event subscription with proper relays
                        await self.startWalletEventSubscription()
                        
                        // Mark that we've processed initial config
                        self.hasProcessedInitialConfig = true
                        
                        NDKLogger.log(.info, category: .wallet, "✅ Wallet loading complete. Monitoring for updates.")
                    }
                }
            }
            
            // Process configuration events as they arrive
            for await event in dataSource.events {
                await self.processConfigurationEvent(event)
            }
            
            // Clean up EOSE monitoring task
            eoseTask?.cancel()
        }
    }
    
    // MARK: - Quote Tracking Methods
    
    /// Start tracking a quote for automatic minting when paid
    public func trackQuote(quote: CashuMintQuote, event: NDKEvent) async {
        await startQuoteTracking(quote: quote, event: event)
    }
    
    /// Internal method to start quote tracking
    private func startQuoteTracking(quote: CashuMintQuote, event: NDKEvent) async {
        // Calculate age from event's created_at
        let eventDate = Date(nostrTimestamp: event.createdAt)
        let age = Date().timeIntervalSince(eventDate)
        
        // Skip if older than 24 hours
        guard age < TimeConstants.day else { 
            NDKLogger.log(.debug, category: .wallet, "📜 Skipping quote tracking for \(quote.quoteId) - older than 24 hours")
            return 
        }
        
        // Cancel existing monitor if any
        activeQuoteMonitors[quote.quoteId]?.cancel()
        
        NDKLogger.log(.debug, category: .wallet, "📜 Starting quote tracking for \(quote.quoteId) - age: \(Int(age/60)) minutes")
        
        // Start monitoring with dynamic interval
        let task = Task { [weak self] in
            guard let self = self else { return }
            
            do {
                for try await status in await CashuDeposit.monitorDeposit(
                    quote: quote,
                    quoteEventId: event.id,
                    mints: self.mints,
                    eventManager: self.eventManager,
                    signer: self.signer,
                    timeout: TimeConstants.day - age, // Remaining time until 24h
                    quoteAge: age,
                    onProofsReceived: { proofs in
                        // Let the wallet handle proof state updates
                        let stateChange = WalletStateChange(
                            store: proofs, 
                            destroy: [], 
                            mint: quote.mintURL,
                            memo: StringConstants.Transactions.lightningDeposit
                        )
                        return try await self.update(stateChange: stateChange)
                    }
                ) {
                    switch status {
                    case .minted:
                        // Success - delete the quote event
                        NDKLogger.log(.debug, category: .wallet, "✅ Quote \(quote.quoteId) successfully minted - deleting quote event")
                        try? await self.eventManager.deleteQuoteEvent(eventId: event.id, signer: self.signer)
                        await self.clearQuoteMonitor(quoteId: quote.quoteId)
                        return
                        
                    case .expired, .cancelled:
                        NDKLogger.log(.debug, category: .wallet, "❌ Quote \(quote.quoteId) expired or cancelled")
                        await self.clearQuoteMonitor(quoteId: quote.quoteId)
                        return
                        
                    case .pending:
                        // Continue monitoring
                        continue
                    }
                }
            } catch {
                NDKLogger.log(.debug, category: .wallet, "❌ Error monitoring quote \(quote.quoteId): \(error)")
                await self.clearQuoteMonitor(quoteId: quote.quoteId)
            }
        }
        
        activeQuoteMonitors[quote.quoteId] = task
    }
    
    /// Clear a specific quote monitor
    private func clearQuoteMonitor(quoteId: String) async {
        activeQuoteMonitors[quoteId] = nil
    }
    
    /// Stop all active quote monitors
    public func stopQuoteMonitors() async {
        activeQuoteMonitors.forEach { $0.value.cancel() }
        activeQuoteMonitors.removeAll()
    }
    
    /// Receive proofs from another user or source
    public func receive(proofs proofsToAdd: [CashuSwift.Proof]) async throws {
        // Validate proofs have corresponding keysets
        for proof in proofsToAdd {
            guard await mints.hasKeyset(id: proof.keysetID) else {
                throw NDKError.invalidProof("Unknown keyset ID: \(proof.keysetID)")
            }
        }
        
        // Group proofs by mint for state update
        var proofsByMint: [String: [CashuSwift.Proof]] = [:]
        for proof in proofsToAdd {
            if let mint = await mints.findMintForKeyset(proof.keysetID) {
                proofsByMint[mint, default: []].append(proof)
            }
        }
        
        // Update state for each mint
        for (mintURL, proofs) in proofsByMint {
            let stateChange = WalletStateChange(
                store: proofs,
                destroy: [],
                mint: mintURL,
                memo: "Receive ecash"
            )
            _ = try await update(stateChange: stateChange)
        }
    }
    
    /// Setup wallet with mints and relays, optionally publishing mint list (kind 10019)
    /// THIS IS THE MAIN AND CORRECT WAY TO CREATE A CASHU WALLET AND SETUP NUTZAPS
    /// - Parameters:
    ///   - mints: Array of mint URLs to configure
    ///   - relays: Array of relay URLs to publish wallet events to
    ///   - publishMintList: Whether to publish a public mint list event (kind 10019)
    public func setup(mints: [String], relays: [String], publishMintList: Bool = true) async throws {
        
        // Update wallet configuration relays immediately
        self.walletConfigRelays = relays
        
        // Get or create P2PK keypair
        let (p2pkPrivateKey, _) = try await p2pkManager.getOrCreateKeypair()
        
        // Create and publish wallet configuration (kind 17375)
        try await NDKCashuWalletEvent.createAndPublish(
            ndk: ndk,
            mints: mints,
            relays: relays,
            p2pkPrivateKey: p2pkPrivateKey,
            signer: signer
        )
        
        // Optionally publish mint list (kind 10019)
        if publishMintList {
            
            // Get P2PK public key for nutzaps
            let p2pkPubkey = try await getP2PKPubkey()
            
            try await NDKCashuMintList.createAndPublish(
                ndk: ndk,
                mints: mints,
                signer: signer,
                p2pkPubkey: p2pkPubkey,
                relays: relays
            )
        }
        
        // The wallet event processor will handle the incoming event and configure the mints
    }
    
    
    
    
    // MARK: - Centralized State Management
    
    /// Handles all proof state changes using explicit state change instructions
    public func update(stateChange: WalletStateChange) async throws -> [String] {
        NDKLogger.log(.debug, category: .wallet, "NIP60Wallet.update() - Storing \(stateChange.store.count) proofs, destroying \(stateChange.destroy.count) proofs")
        
        // Update internal state immediately
        await updateInternalState(stateChange)
        
        // Update external state (token events on relays)
        let eventIds = try await updateExternalState(stateChange)
        
        // Notify balance change if needed
        await notifyBalanceChangeIfNeeded()
        
        return eventIds
    }
    
    /// Updates the internal proof state
    private func updateInternalState(_ stateChange: WalletStateChange) async {
        // Mark proofs as deleted
        await proofStateManager.markProofsAsDeleted(stateChange.destroy)
        
        // Add new proofs
        for proof in stateChange.store {
            await proofStateManager.addProof(proof, mint: stateChange.mint)
            NDKLogger.log(.debug, category: .wallet, "  Added proof: amount=\(proof.amount), C=\(proof.C)")
        }
    }
    
    /// Updates token events on relays based on state changes
    private func updateExternalState(_ stateChange: WalletStateChange) async throws -> [String] {
        // Calculate what tokens need to change
        let tokenChange = await WalletStateCalculator.calculateNewState(
            stateChange: stateChange,
            proofStateManager: proofStateManager
        )
        
        // Update token events
        let eventIds = try await eventManager.updateTokenEvents(
            tokenChange: tokenChange,
            proofStateManager: proofStateManager,
            signer: signer
        )
        
        // Update tracking
        await eventManager.setCurrentTokenEventIds(Set(eventIds))
        
        return eventIds
    }
    
    /// Check and notify if balance changed
    private func notifyBalanceChangeIfNeeded() async {
        let currentBalance = await proofStateManager.getTotalBalance()
        if currentBalance != lastNotifiedBalance {
            lastNotifiedBalance = currentBalance
            events.yield(NIP60WalletEvent(type: .balanceChanged(currentBalance)))
        }
    }
    
    private var lastNotifiedBalance: Int64 = -1 // Start with -1 to ensure first balance notification
    
    
    
    
    
    // MARK: - Proof Access
    
    /// Get all unspent proofs grouped by mint
    /// Returns a dictionary mapping mint URLs to their unspent proofs
    public func getUnspentProofs() async -> [String: [CashuSwift.Proof]] {
        return await proofStateManager.getAvailableProofsByMint()
    }
    
    
    /// Create a token from specific proofs without P2PK locking
    /// This is used for offline token generation where exact proofs are specified
    public func createTokenFromProofs(
        proofs: [CashuSwift.Proof],
        mint: URL,
        memo: String? = nil
    ) async throws -> String {
        // Create the token
        let token = CashuSwift.Token(
            proofs: [mint.absoluteString: proofs],
            unit: "sat",
            memo: memo
        )
        
        // Serialize token using CashuSwift's built-in method
        let tokenString = try token.serialize(to: .V3)
        
        // Update wallet state (mark proofs as spent)
        let stateChange = WalletStateChange(
            store: [],  // No new proofs to store
            destroy: proofs,  // Mark these proofs as spent
            mint: mint.absoluteString
        )
        
        _ = try await update(stateChange: stateChange)
        
        // Create spending history event with the token
        try await eventManager.createSpendingHistoryEvent(
            direction: .out,
            amount: proofs.reduce(0) { $0 + Int64($1.amount) },
            memo: memo ?? "Offline token",
            token: tokenString,
            signer: signer
        )
        
        return tokenString
    }
    
    // MARK: - Relay Health
    
    /// Get relay health status for wallet synchronization
    public func getRelayHealth() async -> [WalletHealthMonitor.RelayHealth] {
        // Use wallet-configured relays from kind 17375 event
        let status = await healthMonitor.getWalletHealthStatus(walletRelays: walletRelays)
        return status.relayHealth
    }
    
    /// Repair relay by re-publishing missing events
    public func repairRelay(_ relay: NDKRelay, missingEventIds: [String]) async throws {
        let relayURLs = Set([relay.url])
        var repairedCount = 0
        var failedCount = 0
        
        // Group missing events by current token events
        let currentTokenEventIds = await eventManager.getCurrentTokenEventIds()
        
        for eventId in missingEventIds {
            if currentTokenEventIds.contains(eventId) {
                // This is a current token event - recreate it from proofs
                let proofs = await proofStateManager.getProofsForEvent(eventId)
                
                if !proofs.isEmpty {
                    // Group proofs by mint
                    var proofsByMint: [String: [CashuSwift.Proof]] = [:]
                    for proof in proofs {
                        if let mint = await proofStateManager.getMintForProof(proof) {
                            proofsByMint[mint, default: []].append(proof)
                        }
                    }
                    
                    // Create token event for each mint
                    for (mint, mintProofs) in proofsByMint {
                        let token = CashuSwift.Token(
                            proofs: [mint: mintProofs],
                            unit: "sat"
                        )
                        
                        do {
                            let tokenEvent = try await NDKCashuTokenEvent.create(
                                ndk: ndk,
                                token: token,
                                signer: signer
                            )
                            
                            // Republish to specific relay
                            let published = try await ndk.publish(tokenEvent.event, to: relayURLs)
                            if published.contains(relay) {
                                repairedCount += 1
                                NDKLogger.log(.debug, category: .wallet, "✅ Repaired token event \(eventId) on relay \(relay.url)")
                            } else {
                                failedCount += 1
                                NDKLogger.log(.debug, category: .wallet, "❌ Failed to repair token event \(eventId) on relay \(relay.url)")
                            }
                        } catch {
                            failedCount += 1
                            NDKLogger.log(.debug, category: .wallet, "❌ Error creating token event for repair: \(error)")
                        }
                    }
                }
            } else {
                // Try to fetch non-token events from cache (wallet config, etc.)
                let filter = NDKFilter(ids: [eventId])
                let cachedEvents = try await ndk.cache.queryEvents(filter)
                if let event = cachedEvents.first {
                    let published = try await ndk.publish(event, to: relayURLs)
                    if published.contains(relay) {
                        repairedCount += 1
                        NDKLogger.log(.debug, category: .wallet, "✅ Repaired event \(eventId) on relay \(relay.url)")
                    } else {
                        failedCount += 1
                    }
                } else {
                    failedCount += 1
                    NDKLogger.log(.debug, category: .wallet, "⚠️ Event \(eventId) not found in cache")
                }
            }
        }
        
        NDKLogger.log(.debug, category: .wallet, "🔧 Relay repair complete: \(repairedCount) repaired, \(failedCount) failed")
    }
    
    // MARK: - Internal Helpers
    
    
    /// Stop the wallet and clean up resources
    public func stop() async {
        // Cancel subscriptions
        configSubscriptionTask?.cancel()
        walletSubscriptionTask?.cancel()
        
        // Stop quote monitors
        await stopQuoteMonitors()
        
        // Stop transaction history observation
        await transactionHistory.stopObserving()
        
        // Clear wallet configuration
        walletConfigRelays = []
        
        NDKLogger.log(.debug, category: .wallet, "🛑 NIP60Wallet stopped")
    }
    
    /// Check wallet health status
    public func checkWalletHealth() async throws -> WalletHealthMonitor.WalletHealthStatus {
        // Use wallet-configured relays from kind 17375 event
        return await healthMonitor.getWalletHealthStatus(walletRelays: walletRelays)
    }
    
    /// Validate proofs with their respective mints
    public func validateProofs() async throws -> ProofReconciliationResult {
        let allMints = await mints.getAllMints()
        return try await healthMonitor.checkAndReconcileProofStates(
            proofStateManager: proofStateManager,
            mints: allMints,
            mintManager: self.mints,
            signer: signer
        )
    }
    
    // MARK: - Backup and Restore
    
    /// Create a backup of the wallet configuration (kind 375)
    /// - Returns: The published backup event
    @discardableResult
    public func createBackup() async throws -> NDKCashuWalletBackupEvent {
        NDKLogger.log(.info, category: .wallet, "📦 Creating wallet backup (kind 375)")
        
        // Get current wallet configuration
        let currentMints = await mints.getMintURLs()
        let currentRelays = walletConfigRelays
        let (p2pkPrivateKey, _) = try await p2pkManager.getOrCreateKeypair()
        
        // Create and publish backup event
        let backupEvent = try await NDKCashuWalletBackupEvent.createAndPublish(
            ndk: ndk,
            mints: currentMints,
            relays: currentRelays.isEmpty ? nil : currentRelays,
            p2pkPrivateKey: p2pkPrivateKey,
            signer: signer
        )
        
        NDKLogger.log(.info, category: .wallet, "✅ Wallet backup created successfully: \(backupEvent.event.id)")
        
        return backupEvent
    }
    
    /// Check if a backup exists for the current user
    public func hasBackup() async throws -> Bool {
        let pubkey = try await signer.pubkey
        
        let backupFilter = NDKFilter(
            authors: [pubkey],
            kinds: [EventKind.cashuWalletBackup],
            limit: 1,
            tags: ["p": Set([pubkey])]
        )
        
        let dataSource = NDKDataSource(
            ndk: ndk,
            filter: backupFilter,
            maxAge: 0,
            cachePolicy: .networkOnly,
            subscriptionId: "nip60-check-backup"
        )
        
        let backupEvents = await dataSource.collect()
        return !backupEvents.isEmpty
    }
    
    // MARK: - Nutzap Management
    
    /// Get all nutzaps (both pending and redeemed)
    /// - Returns: Array of NutzapInfo sorted by creation date (newest first)
    public func getNutzaps() async -> [NutzapInfo] {
        return await eventManager.getNutzaps()
    }
    
    /// Get pending (unredeemed) nutzaps
    /// - Returns: Array of pending NutzapInfo sorted by creation date (newest first)
    public func getPendingNutzaps() async -> [NutzapInfo] {
        return await eventManager.getPendingNutzaps()
    }
    
    /// Get redeemed nutzaps
    /// - Returns: Array of redeemed NutzapInfo sorted by creation date (newest first)
    public func getRedeemedNutzaps() async -> [NutzapInfo] {
        return await eventManager.getRedeemedNutzaps()
    }
    
    /// Check if a specific nutzap has been redeemed
    /// - Parameter eventId: The event ID of the nutzap
    /// - Returns: True if the nutzap has been redeemed, false otherwise
    public func isNutzapRedeemed(_ eventId: String) async -> Bool {
        return await eventManager.isNutzapRedeemed(eventId)
    }
    
    /// Get the total amount of pending nutzaps
    /// - Returns: Total amount in satoshis of all pending nutzaps
    public func getTotalPendingNutzapAmount() async -> Int64 {
        let pendingNutzaps = await eventManager.getPendingNutzaps()
        return pendingNutzaps.reduce(0) { $0 + $1.amount }
    }
    
    /// Get the total amount of redeemed nutzaps
    /// - Returns: Total amount in satoshis of all redeemed nutzaps
    public func getTotalRedeemedNutzapAmount() async -> Int64 {
        let redeemedNutzaps = await eventManager.getRedeemedNutzaps()
        return redeemedNutzaps.reduce(0) { $0 + $1.amount }
    }
    
    /// Get nutzaps by status filter
    /// - Parameter filter: Status filter to apply
    /// - Returns: Array of filtered NutzapInfo sorted by creation date (newest first)
    public func getNutzapsByStatus(_ filter: NutzapStatusFilter) async -> [NutzapInfo] {
        return await eventManager.getNutzapsByStatus(filter)
    }
    
    /// Manually redeem a nutzap
    /// - Parameter eventId: The event ID of the nutzap to redeem
    /// - Returns: Redemption result with success status and details
    /// - Throws: NutzapRedemptionError if redemption fails
    public func redeemNutzap(_ eventId: String) async throws -> NutzapRedemptionResult {
        guard let nutzapInfo = await eventManager.getNutzapInfo(eventId) else {
            throw NutzapRedemptionError.unknownError("Nutzap not found")
        }
        
        // Don't retry if already redeemed
        if case .redeemed = nutzapInfo.status {
            return NutzapRedemptionResult(
                success: true,
                proofsRedeemed: [],
                error: nil,
                amount: nutzapInfo.amount
            )
        }
        
        // Update attempt timestamp
        await eventManager.updateNutzapAttemptTimestamp(eventId)
        
        do {
            // Process with internal retry for transient errors
            let result = try await redeemWithRetry(nutzapInfo.event, maxAttempts: 3)
            
            // Update status to redeemed
            await eventManager.updateNutzapStatus(
                eventId,
                status: .redeemed(at: .now, proofsCount: result.proofsRedeemed?.count ?? 0)
            )
            
            // Update transaction history
            await updateTransactionForNutzap(eventId, status: .completed)
            
            return result
        } catch {
            // Map error to NutzapRedemptionError
            let redemptionError = Nutzap.mapToRedemptionError(error)
            
            // Get current attempts count
            let currentAttempts = getCurrentAttempts(nutzapInfo.status) + 1
            
            // Update status with error
            await eventManager.updateNutzapStatus(
                eventId,
                status: .failed(
                    error: redemptionError,
                    attempts: currentAttempts,
                    lastAttempt: .now
                )
            )
            
            // Update transaction history
            await updateTransactionForNutzap(eventId, status: .failed)
            
            throw redemptionError
        }
    }
    
    /// Retry all failed nutzaps that have retryable errors
    /// - Returns: Array of tuples with event ID and redemption result
    public func retryFailedNutzaps() async -> [(eventId: String, result: NutzapRedemptionResult)] {
        let failedNutzaps = await eventManager.getFailedNutzaps()
        var results: [(String, NutzapRedemptionResult)] = []
        
        for nutzap in failedNutzaps {
            // Only retry if the error is retryable
            if case .failed(let error, _, _) = nutzap.status, error.isRetryable {
                do {
                    let result = try await redeemNutzap(nutzap.eventId)
                    results.append((nutzap.eventId, result))
                } catch {
                    // Continue with next nutzap
                    let failureResult = NutzapRedemptionResult(
                        success: false,
                        proofsRedeemed: nil,
                        error: Nutzap.mapToRedemptionError(error),
                        amount: 0
                    )
                    results.append((nutzap.eventId, failureResult))
                }
            }
        }
        
        return results
    }
    
    // MARK: - Private Nutzap Redemption Helpers
    
    /// Redeem nutzap with automatic retry for transient errors
    private func redeemWithRetry(_ event: NDKEvent, maxAttempts: Int) async throws -> NutzapRedemptionResult {
        var lastError: Error?
        
        for attempt in 1...maxAttempts {
            do {
                // Get mints and construct keysets dictionary
                let allMints = await mints.getAllMints()
                let keysets = allMints.values.flatMap { $0.keysets }.reduce(into: [:]) { result, keyset in
                    result[keyset.keysetID] = keyset
                }
                
                // Call the existing processIncoming method
                let result = try await Nutzap.processIncoming(
                    wallet: self,
                    event: event,
                    mints: allMints,
                    keysets: keysets,
                    proofStateManager: proofStateManager,
                    eventManager: eventManager,
                    p2pkManager: p2pkManager,
                    ndk: ndk,
                    signer: signer
                )
                
                return result
            } catch {
                lastError = error
                let redemptionError = Nutzap.mapToRedemptionError(error)
                
                // Only retry transient errors
                if redemptionError.isRetryable && attempt < maxAttempts {
                    // Exponential backoff: 1s, 2s, 4s...
                    let delay = UInt64(pow(2.0, Double(attempt - 1))) * 1_000_000_000
                    try? await Task.sleep(nanoseconds: delay)
                    continue
                }
                
                throw error
            }
        }
        
        throw lastError ?? NutzapRedemptionError.unknownError("All retry attempts failed")
    }
    
    /// Get current attempt count from status
    private func getCurrentAttempts(_ status: NutzapRedemptionStatus) -> Int {
        if case .failed(_, let attempts, _) = status {
            return attempts
        }
        return 0
    }
    
    /// Update transaction status for a nutzap
    private func updateTransactionForNutzap(_ eventId: String, status: TransactionStatus) async {
        // Find transaction with this nutzap event ID
        if let transaction = await transactionHistory.getTransactionForEvent(eventId: eventId) {
            // Update transaction status
            let updated = transaction.with(status: status)
            await transactionHistory.updateTransaction(updated)
        }
    }
    
    // MARK: - Transaction History
    
    /// Get complete transaction history
    /// - Returns: Array of all wallet transactions sorted by date (newest first)
    public func getTransactionHistory() async -> [WalletTransaction] {
        return await transactionHistory.getAllTransactions()
    }
    
    /// Get transactions filtered by type
    /// - Parameter types: Set of transaction types to include
    /// - Returns: Filtered transactions sorted by date (newest first)
    public func getTransactions(types: Set<WalletTransactionType>) async -> [WalletTransaction] {
        return await transactionHistory.getTransactions(types: types)
    }
    
    /// Get transactions filtered by direction
    /// - Parameter direction: Transaction direction (incoming/outgoing/neutral)
    /// - Returns: Filtered transactions sorted by date (newest first)
    public func getTransactions(direction: TransactionDirection) async -> [WalletTransaction] {
        return await transactionHistory.getTransactions(direction: direction)
    }
    
    /// Get a specific transaction by ID
    /// - Parameter id: Transaction ID
    /// - Returns: The transaction if found
    public func getTransaction(id: String) async -> WalletTransaction? {
        return await transactionHistory.getTransaction(id: id)
    }
    
    /// Get transaction associated with a specific Nostr event
    /// - Parameter eventId: Nostr event ID
    /// - Returns: The transaction if found
    public func getTransactionForEvent(eventId: String) async -> WalletTransaction? {
        return await transactionHistory.getTransactionForEvent(eventId: eventId)
    }
    
    /// Get recent transactions
    /// - Parameter limit: Maximum number of transactions to return
    /// - Returns: Most recent transactions up to the limit
    public func getRecentTransactions(limit: Int = 10) async -> [WalletTransaction] {
        let allTransactions = await transactionHistory.getAllTransactions()
        return Array(allTransactions.prefix(limit))
    }
    
    /// Get transaction summary statistics
    /// - Returns: Summary of transaction counts and amounts by type
    public func getTransactionSummary() async -> TransactionSummary {
        let transactions = await transactionHistory.getAllTransactions()
        
        var summary = TransactionSummary()
        
        for transaction in transactions {
            // Count by type
            summary.countByType[transaction.type, default: 0] += 1
            
            // Sum amounts by type
            summary.amountByType[transaction.type, default: 0] += transaction.amount
            
            // Track totals by direction
            switch transaction.direction {
            case .incoming:
                summary.totalReceived += transaction.amount
            case .outgoing:
                summary.totalSent += transaction.amount
            case .neutral:
                break
            }
        }
        
        summary.totalTransactions = transactions.count
        summary.netBalance = summary.totalReceived - summary.totalSent
        
        return summary
    }
}

// MARK: - Transaction Summary

/// Summary statistics for wallet transactions
public struct TransactionSummary: Sendable {
    public var totalTransactions: Int = 0
    public var totalReceived: Int64 = 0
    public var totalSent: Int64 = 0
    public var netBalance: Int64 = 0
    public var countByType: [WalletTransactionType: Int] = [:]
    public var amountByType: [WalletTransactionType: Int64] = [:]
}