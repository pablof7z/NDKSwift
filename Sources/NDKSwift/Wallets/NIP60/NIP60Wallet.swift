import Foundation
import CashuSwift
import secp256k1

/// NIP-60 wallet implementation for Cashu-based wallets
public actor NIP60Wallet: NDKPaymentProvider {
    // MARK: - Properties
    
    public let id = "nip60"
    public let displayName = "Cashu Wallet"
    
    internal let ndk: NDK
    internal var proofs: [CashuSwift.Proof] = []
    public let p2pkManager: P2PKManager // Manages P2PK keys for receiving nutzaps
    
    // Relay health monitoring
    public internal(set) var walletRelays: [NDKRelay] = []
    
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
    
    // MARK: - Event Stream
    
    public let events = NIP60WalletEventStream()
    
    // MARK: - Initialization
    
    public init(ndk: NDK, cache: NDKCache? = nil) {
        self.ndk = ndk
        self.p2pkManager = P2PKManager()
        self.eventManager = WalletEventManager(ndk: ndk)
        self.mints = MintManager(cache: cache ?? ndk.cache)
        self.healthMonitor = WalletHealthMonitor(
            eventManager: eventManager,
            ndk: ndk
        )
        guard let signer = ndk.signer else {
            fatalError("NIP60Wallet requires a signer configured on NDK")
        }
        self.signer = signer
    }
    
    // MARK: - Unified Wallet State Subscription
    
    /// Start the unified wallet subscription that monitors all wallet-related events
    public func startWalletSubscription() async {
        // Cancel any existing subscription
        walletSubscriptionTask?.cancel()
        
        walletSubscriptionTask = Task {
            do {
                let userPubkey = try await signer.pubkey
                
                // Create filters for all wallet-related events
                let filters = [
                    // Our own wallet events (tokens and quotes)
                    NDKFilter(
                        authors: [userPubkey],
                        kinds: [
                            EventKind.cashuToken,
                            EventKind.cashuQuote
                        ]
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
    internal func processWalletConfiguration(event: NDKEvent, decryptedTags: [[String]]) async {
        let walletEvent = NDKCashuWalletEvent(event: event)
        
        // Process relay tags (unencrypted, no signer needed)
        walletRelays = walletEvent.relays.compactMap { NDKRelay(url: $0) }
        print("📡 Extracted \(walletRelays.count) wallet relays from wallet event")
        
        do {
            // Get current mints before update
            let previousMints = Set(await mints.getMintURLs())
            
            // Process P2PK private key
            if let privkey = try await walletEvent.privateKey(signer: signer) {
                try? await p2pkManager.restoreFromPrivateKey(privkey)
            }
            
            // Process mints
            let mintURLs = try await walletEvent.mints(signer: signer)
            var newMints = Set<String>()
            
            for mintURL in mintURLs {
                guard let url = URL(string: mintURL) else { continue }
                try? await mints.addMint(url: url)
                newMints.insert(mintURL)
            }
            
            // Determine what changed
            let addedMints = newMints.subtracting(previousMints)
            let removedMints = previousMints.subtracting(newMints)
            
            // Emit events
            if !addedMints.isEmpty || !removedMints.isEmpty {
                let currentMintList = Array(newMints)
                
                events.yield(NIP60WalletEvent(type: .configurationUpdated(mints: currentMintList)))
                
                if !addedMints.isEmpty {
                    events.yield(NIP60WalletEvent(type: .mintsAdded(Array(addedMints))))
                }
                
                if !removedMints.isEmpty {
                    events.yield(NIP60WalletEvent(type: .mintsRemoved(Array(removedMints))))
                }
            }
            
            print("✅ Wallet configuration updated with \(newMints.count) mints")
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
        return balance
    }
    
    /// Get balance for a specific mint
    public func getBalance(mint: URL) async -> Int64 {
        let proofs = await proofStateManager.getAvailableProofs(mint: mint.absoluteString)
        return proofs.reduce(0) { $0 + Int64($1.amount) }
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
    private func processIncomingNutzap(_ event: NDKEvent) async throws {
        let mints = await mints.getAllMints()
        let keysets = mints.values.flatMap { $0.keysets }.reduce(into: [:]) { result, keyset in
            result[keyset.keysetID] = keyset
        }
        
        // Process the nutzap
        let result = try await Nutzap.processIncoming(
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
                events.yield(NIP60WalletEvent(type: .nutzapReceived(amount: totalAmount, from: sender)))
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
        pollingInterval: TimeInterval = 5.0,
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
                        pollingInterval: pollingInterval,
                        timeout: timeout,
                        onProofsReceived: { proofs in
                            // Update wallet state with new proofs
                            return try await self.update(
                                deletedProofs: [],
                                addedProofs: proofs
                            )
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
        
        // Cancel any existing subscriptions
        configSubscriptionTask?.cancel()
        walletSubscriptionTask?.cancel()
        
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
        
        // Now start the long-lived subscription for any future updates
        await self.startWalletSubscription()
        print("✅ Wallet loading complete. Monitoring for updates.")
    }
    
    
    
    
    
    
    
    
    /// Receive proofs from another user or source
    public func receive(proofs proofsToAdd: [CashuSwift.Proof]) async throws {
        // Validate proofs have corresponding keysets
        for proof in proofsToAdd {
            guard await mints.hasKeyset(id: proof.keysetID) else {
                throw NDKError.invalidProof("Unknown keyset ID: \(proof.keysetID)")
            }
        }
        
        // Update state (this handles token event creation)
        _ = try await update(
            deletedProofs: [],
            addedProofs: proofsToAdd
        )
    }
    
    /// Setup wallet with mints and relays, optionally publishing mint list (kind 10019)
    /// - Parameters:
    ///   - mints: Array of mint URLs to configure
    ///   - relays: Array of relay URLs to publish wallet events to
    ///   - publishMintList: Whether to publish a public mint list event (kind 10019)
    public func setup(mints: [String], relays: [String], publishMintList: Bool = true) async throws {
        print("NIP60Wallet - setup() called with \(mints.count) mints, \(relays.count) relays")
        
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
            try await NDKCashuMintList.createAndPublish(
                ndk: ndk,
                mints: mints,
                signer: signer
            )
            print("NIP60Wallet - Mint list published successfully")
        }
        
        // The wallet event processor will handle the incoming event and configure the mints
        print("NIP60Wallet - Setup complete, waiting for event processing")
    }
    
    
    
    
    // MARK: - Centralized State Management
    
    /// The heart of the system - handles all proof state changes
    internal func update(
        deletedProofs: [CashuSwift.Proof],
        addedProofs: [CashuSwift.Proof]
    ) async throws -> [String] {
        print("NIP60Wallet.update() - Adding \(addedProofs.count) proofs, deleting \(deletedProofs.count) proofs")
        
        // Get balance before update
        let previousBalance = await proofStateManager.getTotalBalance()
        
        // 1. Update proof states
        await proofStateManager.markProofsAsDeleted(deletedProofs)
        
        for proof in addedProofs {
            // Find mint for this proof
            guard let mint = await mints.findMintForKeyset(proof.keysetID) else {
                throw NDKError.invalidProof("Proof with unknown keyset: \(proof.keysetID)")
            }
            await proofStateManager.addProof(proof, mint: mint)
            print("  Added proof: amount=\(proof.amount), C=\(proof.C)")
        }
        
        // 2. Group available proofs by mint
        let availableByMint = await proofStateManager.getAvailableProofsByMint()
        
        // 3. Update token events through the event manager
        let newEventIds = try await eventManager.updateTokenEvents(
            availableProofsByMint: availableByMint,
            proofStateManager: proofStateManager,
            signer: signer
        )
        
        // 4. Update tracking
        await eventManager.setCurrentTokenEventIds(Set(newEventIds))
        
        // 5. Update internal proofs array for compatibility
        self.proofs = availableByMint.values.flatMap { $0 }
        
        // 6. Check if balance changed and notify
        let newBalance = await proofStateManager.getTotalBalance()
        if newBalance != previousBalance {
            events.yield(NIP60WalletEvent(type: .balanceChanged(newBalance)))
        }
        
        // Return the newly created event IDs
        return Array(newEventIds)
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
        // Re-publish missing events to the relay
        let relayURLs = Set([relay.url])
        
        // For each missing event ID, we need to fetch it from our local cache
        // and republish it to the specific relay
        for eventId in missingEventIds {
            // Try to fetch the event from cache
            let filter = NDKFilter(ids: [eventId])
            let cache = ndk.cache
            let cachedEvents = try await cache.queryEvents(filter)
            if let event = cachedEvents.first {
                _ = try await ndk.publish(event: event, to: relayURLs)
            }
        }
    }
    
    // MARK: - Internal Helpers
    
    /// Update internal proofs array from state manager
    internal func updateProofsFromStateManager() async {
        self.proofs = await proofStateManager.getAvailableProofs()
    }
    
    /// Process incoming nutzap event (for handler)
    internal func processIncomingNutzapEvent(_ event: NDKEvent) async throws {
        try await processIncomingNutzap(event)
    }
}