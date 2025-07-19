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

    private let signer: NDKSigner
    
    // MARK: - Quote Tracking
    
    private var activeQuoteMonitors: [String: Task<Void, Never>] = [:] // quoteId -> monitoring task
    
    // MARK: - Event Stream
    
    public let events = NIP60WalletEventStream()
    
    // MARK: - Initialization
    
    public init(ndk: NDK, cache: NDKCache? = nil) throws {
        guard let signer = ndk.signer else {
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
    }
    
    // MARK: - Unified Wallet State Subscription
    
    /// Start the unified wallet subscription that monitors all wallet-related events
    public func startWalletSubscription() async {
        // Cancel any existing subscription
        walletSubscriptionTask?.cancel()
        
        walletSubscriptionTask = Task {
            do {
                let userPubkey = try await signer.pubkey
                let twentyFourHoursAgo = Int64(Date(timeIntervalSinceNow: -60 * 60 * 24).timeIntervalSince1970)
                
                // Create filters for all wallet-related events
                let filters = [
                    // Our own wallet events (tokens and quotes)
                    NDKFilter(
                        authors: [userPubkey],
                        kinds: [
                            EventKind.cashuToken,
                        ]
                    ),
                    NDKFilter(
                        authors: [userPubkey],
                        kinds: [
                            EventKind.cashuQuote
                        ],
                        since: twentyFourHoursAgo,
                        limit: 20
                    ),
                    // Wallet config with limit: 0 to only get future updates
                    NDKFilter(
                        authors: [userPubkey],
                        kinds: [EventKind.cashuWalletConfig],
                        limit: 0  // Only get new events, not historical ones
                    ),
                    // Delete events for our wallet
                    NDKFilter(
                        authors: [userPubkey],
                        kinds: [EventKind.deletion],  // Delete events
                        tags: ["k": Set([String(EventKind.cashuToken), String(EventKind.cashuQuote)])]
                    ),
                    // Incoming nutzaps
                    NDKFilter(
                        kinds: [EventKind.nutzap],
                        tags: ["p": Set([userPubkey])]
                    )
                ]
                
                // Subscribe with wallet-specific relays if configured
                let relayUrls = walletRelays.isEmpty ? nil : Set(walletRelays.map { $0.url })
                
                print("📡 Starting unified wallet subscription with \(walletRelays.count) relays")
                
                let subscription = await self.ndk.subscribe(filters: filters, relays: relayUrls, closeOnEose: false)
                
                do {
                    for try await event in subscription {
                        // Process event
                        await self.processWalletEvent(event)
                    }
                } catch {
                    if error is CancellationError {
                        print("🛑 Wallet subscription cancelled")
                    } else {
                        print("❌ Wallet subscription error: \(error)")
                    }
                }
            } catch {
                if error is CancellationError {
                    print("🛑 Wallet subscription cancelled")
                } else {
                    print("❌ Wallet subscription error: \(error)")
                }
            }
        }
    }
    
    /// Process a wallet-related event from the unified subscription
    private func processWalletEvent(_ event: NDKEvent) async {
        // Special handling for wallet config timestamp check
        if event.kind == EventKind.cashuWalletConfig {
            let lastTimestamp = await eventManager.getLastWalletConfigTimestamp()
            if event.createdAt <= lastTimestamp {
                print("⏭️ Skipping older wallet configuration")
                return
            }
            await eventManager.updateLastWalletConfigTimestamp(event.createdAt)
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
    }
    
    
    /// Process wallet configuration from event
    /// This method extracts mints, relays, and P2PK keys from a wallet configuration event.
    /// Note: Mints that fail to load (e.g., due to network errors) will be skipped and not added to the wallet.
    internal func processWalletConfiguration(event: NDKEvent) async {
        print("⚙️ Processing wallet configuration")
        print("⚙️ Event ID: \(event.id)")
        print("⚙️ Event Kind: \(event.kind)")
        
        let walletEvent = NDKCashuWalletEvent(event: event)
        
        // Process relay tags (unencrypted, no signer needed)
        walletConfigRelays = walletEvent.relays
        walletRelays = walletEvent.relays.compactMap { NDKRelay(url: $0) }
        print("📡 Extracted \(walletRelays.count) wallet relays from wallet event")
        
        do {
            // Get current mints before update
            let previousMints = Set(await mints.getMintURLs())
            
            // Process P2PK private key
            if let privkey = try await walletEvent.privateKey(signer: signer) {
                print("🔑 Found P2PK private key in wallet config: \(privkey.prefix(8))...")
                try? await p2pkManager.restoreFromPrivateKey(privkey)
            } else {
                print("🔑 No P2PK private key found in wallet config")
            }
            
            // Process mints
            let mintURLs = try await walletEvent.mints(signer: signer)
            print("🏪 Extracted \(mintURLs.count) mint URLs from wallet config: \(mintURLs)")
            
            let configuredMints = Set(mintURLs)
            
            // Remove mints that are no longer in the configuration
            let mintsToRemove = previousMints.subtracting(configuredMints)
            for mintURL in mintsToRemove {
                guard let url = URL(string: mintURL) else { continue }
                _ = await mints.removeMint(url: url)
                print("🗑 Removed mint no longer in config: \(mintURL)")
            }
            
            // Add new mints from configuration
            var successfullyAddedMints = Set<String>()
            
            for mintURL in mintURLs {
                guard let url = URL(string: mintURL) else { 
                    print("⚠️ Invalid mint URL: \(mintURL)")
                    continue 
                }
                
                // Skip if already exists
                if previousMints.contains(mintURL) {
                    successfullyAddedMints.insert(mintURL)
                    continue
                }
                
                await mints.addMintURL(url: url)
                successfullyAddedMints.insert(mintURL)
                print("✅ Added mint URL: \(mintURL)")
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
            
            print("✅ Wallet configuration updated:")
            print("  - Requested mints: \(mintURLs.count)")
            print("  - Successfully added: \(successfullyAddedMints.count)")
            print("  - Total active mints: \(actualCurrentMints.count)")
            print("  - Active mint URLs: \(actualCurrentMints)")
        } catch {
            print("❌ Failed to parse wallet configuration: \(error)")
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
        print("NIP60Wallet.getBalance() - balance: \(balance)")
        print("NIP60Wallet.getBalance() - proofStateManager: \(ObjectIdentifier(proofStateManager))")
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
        
        // Extract amount from the nutzap event
        if let proofTag = event.tags.first(where: { $0.count >= 2 && $0[0] == "proof" }) {
            if let proofData = proofTag[1].data(using: .utf8),
               let proofJSON = try? JSONSerialization.jsonObject(with: proofData) as? [String: Any],
               let proofArray = proofJSON["proofs"] as? [[String: Any]] {
                let totalAmount = proofArray.reduce(0) { sum, proofDict in
                    sum + (proofDict["amount"] as? Int64 ?? 0)
                }
                
                // Emit event
                let sender = event.pubkey
                events.yield(NIP60WalletEvent(type: .nutzapReceived(amount: totalAmount, from: sender, eventId: event.id)))
            }
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
        
        print("🔍 Reconciliation complete - Checked: \(result.totalChecked), Spent: \(result.spentProofs.count), Pending: \(result.pendingProofs.count), Errors: \(result.errors)")
    }
    
    
    
    
    /// Check proof states for a specific mint
    public func checkProofStates(mintURL: URL) async throws -> [String: CashuSwift.Proof.ProofState] {
        let mints = await mints.getAllMints()
        guard let mint = mints[mintURL.absoluteString] else {
            throw NDKError.noMintAvailable("Mint not found: \(mintURL)")
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
        return try await CashuDeposit.requestMintQuote(
            amount: amount,
            mintURL: mintURL,
            mints: mints,
            eventManager: eventManager,
            persistQuote: persistQuote,
            signer: signer
        )
    }
    
    /// Monitor deposit status for a mint quote (checking if Lightning invoice was paid)
    public func monitorDeposit(
        quote: CashuMintQuote,
        timeout: TimeInterval = 600.0
    ) -> AsyncThrowingStream<DepositStatus, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let stream = CashuDeposit.monitorDeposit(
                        quote: quote,
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
                        }
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
        walletConfigRelays = []
        
        // Cancel any existing subscriptions
        configSubscriptionTask?.cancel()
        walletSubscriptionTask?.cancel()
        
        // Stop any existing quote monitors
        await stopQuoteMonitors()
        
        let userPubkey = try await signer.pubkey
        
        // Use fetchEvent for a one-shot, reliable fetch of the latest config
        let configFilter = NDKFilter(
            authors: [userPubkey],
            kinds: [EventKind.cashuWalletConfig],
            limit: 1
        )
        
        print("📡 Fetching initial wallet configuration...")
        
        // Try to fetch existing configuration with a timeout
        if let configEvent = try? await ndk.fetchEvent(configFilter, timeoutSeconds: 5) {
            // Process the latest configuration event found
            await self.processWalletEvent(configEvent)
            print("✅ Loaded existing wallet configuration")
        } else {
            print("ℹ️ No existing wallet configuration found for user \(userPubkey)")
        }
        
        // Fetch historical token events before starting subscription
        print("📡 Fetching historical token events...")
        let tokenFilter = NDKFilter(
            authors: [userPubkey],
            kinds: [EventKind.cashuToken]
        )
        
        // Fetch all token events that represent wallet state
        let tokenEvents = try await ndk.fetchEvents([tokenFilter], timeoutSeconds: 10)
        print("📦 Found \(tokenEvents.count) token events")
        
        // Process each token event to load proofs
        for event in tokenEvents {
            await self.processWalletEvent(event)
        }
        
        // Log the initial balance after loading historical events
        let initialBalance = await proofStateManager.getTotalBalance()
        print("💰 Initial wallet balance after loading: \(initialBalance) sats")
        
        // Emit balance change event if we have a non-zero balance after loading
        await notifyBalanceChangeIfNeeded()
        
        // Now start the long-lived subscription for any future updates
        await self.startWalletSubscription()
        print("✅ Wallet loading complete. Monitoring for updates.")
    }
    
    // MARK: - Quote Tracking Methods
    
    /// Start tracking a quote for automatic minting when paid
    public func trackQuote(quote: CashuMintQuote, event: NDKEvent) async {
        await startQuoteTracking(quote: quote, event: event)
    }
    
    /// Internal method to start quote tracking
    private func startQuoteTracking(quote: CashuMintQuote, event: NDKEvent) async {
        // Calculate age from event's created_at
        let eventDate = Date(timeIntervalSince1970: TimeInterval(event.createdAt))
        let age = Date().timeIntervalSince(eventDate)
        
        // Skip if older than 24 hours
        guard age < 86400 else { 
            print("📜 Skipping quote tracking for \(quote.quoteId) - older than 24 hours")
            return 
        }
        
        // Cancel existing monitor if any
        activeQuoteMonitors[quote.quoteId]?.cancel()
        
        print("📜 Starting quote tracking for \(quote.quoteId) - age: \(Int(age/60)) minutes")
        
        // Start monitoring with dynamic interval
        let task = Task { [weak self] in
            guard let self = self else { return }
            
            do {
                for try await status in await CashuDeposit.monitorDeposit(
                    quote: quote,
                    mints: self.mints,
                    eventManager: self.eventManager,
                    signer: self.signer,
                    timeout: 86400 - age, // Remaining time until 24h
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
                        print("✅ Quote \(quote.quoteId) successfully minted - deleting quote event")
                        try? await self.eventManager.deleteQuoteEvent(eventId: event.id, signer: self.signer)
                        await self.clearQuoteMonitor(quoteId: quote.quoteId)
                        return
                        
                    case .expired, .cancelled:
                        print("❌ Quote \(quote.quoteId) expired or cancelled")
                        await self.clearQuoteMonitor(quoteId: quote.quoteId)
                        return
                        
                    case .pending:
                        // Continue monitoring
                        continue
                    }
                }
            } catch {
                print("❌ Error monitoring quote \(quote.quoteId): \(error)")
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
        print("🛑 Stopping all quote monitors")
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
        print("NIP60Wallet - setup() called with \(mints.count) mints, \(relays.count) relays")
        
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
        print("NIP60Wallet - Published wallet configuration event")
        
        // Optionally publish mint list (kind 10019)
        if publishMintList {
            print("NIP60Wallet - Publishing mint list event")
            
            // Get P2PK public key for nutzaps
            let p2pkPubkey = try await getP2PKPubkey()
            print("NIP60Wallet - P2PK pubkey for mint list: \(p2pkPubkey)")
            
            try await NDKCashuMintList.createAndPublish(
                ndk: ndk,
                mints: mints,
                signer: signer,
                p2pkPubkey: p2pkPubkey
            )
            print("NIP60Wallet - Mint list published successfully with p2pk tag")
        }
        
        // The wallet event processor will handle the incoming event and configure the mints
        print("NIP60Wallet - Setup complete, waiting for event processing")
    }
    
    
    
    
    // MARK: - Centralized State Management
    
    /// Handles all proof state changes using explicit state change instructions
    public func update(stateChange: WalletStateChange) async throws -> [String] {
        print("NIP60Wallet.update() - Storing \(stateChange.store.count) proofs, destroying \(stateChange.destroy.count) proofs")
        
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
            print("  Added proof: amount=\(proof.amount), C=\(proof.C)")
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
    
    private var lastNotifiedBalance: Int64 = 0
    
    
    
    
    
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
        
        // Create spending history event
        try await eventManager.createSpendingHistoryEvent(
            direction: .out,
            amount: proofs.reduce(0) { $0 + Int64($1.amount) },
            memo: memo ?? "Offline token",
            signer: signer
        )
        
        return tokenString
    }
    
    // MARK: - Relay Health
    
    /// Get relay health status for wallet synchronization
    public func getRelayHealth() async -> [WalletHealthMonitor.RelayHealth] {
        // Get wallet relays from NDK
        let walletRelays = await ndk.pool.relays
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
                                print("✅ Repaired token event \(eventId) on relay \(relay.url)")
                            } else {
                                failedCount += 1
                                print("❌ Failed to repair token event \(eventId) on relay \(relay.url)")
                            }
                        } catch {
                            failedCount += 1
                            print("❌ Error creating token event for repair: \(error)")
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
                        print("✅ Repaired event \(eventId) on relay \(relay.url)")
                    } else {
                        failedCount += 1
                    }
                } else {
                    failedCount += 1
                    print("⚠️ Event \(eventId) not found in cache")
                }
            }
        }
        
        print("🔧 Relay repair complete: \(repairedCount) repaired, \(failedCount) failed")
    }
    
    // MARK: - Internal Helpers
    
    
    /// Stop the wallet and clean up resources
    public func stop() async {
        // Cancel subscriptions
        configSubscriptionTask?.cancel()
        walletSubscriptionTask?.cancel()
        
        // Stop quote monitors
        await stopQuoteMonitors()
        
        // Clear wallet configuration
        walletConfigRelays = []
        
        print("🛑 NIP60Wallet stopped")
    }
    
    /// Debug method to diagnose mint synchronization state
    public func debugMintState() async -> (configured: [String], loaded: [String], failed: [String]) {
        // Get the latest wallet configuration event
        let userPubkey = try? await signer.pubkey
        guard let userPubkey = userPubkey else {
            return ([], await mints.getMintURLs(), [])
        }
        
        let configFilter = NDKFilter(
            authors: [userPubkey],
            kinds: [EventKind.cashuWalletConfig],
            limit: 1
        )
        
        guard let configEvent = try? await ndk.fetchEvent(configFilter, timeoutSeconds: 5) else {
            return ([], await mints.getMintURLs(), [])
        }
        
        let walletEvent = NDKCashuWalletEvent(event: configEvent)
        let configuredMints = (try? await walletEvent.mints(signer: signer)) ?? []
        let loadedMints = await mints.getMintURLs()
        let failedMints = configuredMints.filter { !loadedMints.contains($0) }
        
        return (configuredMints, loadedMints, failedMints)
    }
    
    // MARK: - Health Monitoring
    
    /// Check wallet health status
    public func checkWalletHealth() async throws -> WalletHealthMonitor.WalletHealthStatus {
        let walletRelays = await ndk.pool.relays
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
}