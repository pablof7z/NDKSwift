import Foundation
import CashuSwift
import secp256k1

/// NIP-60 Cashu wallet implementation
public actor NDKCashuWallet: NDKWallet {
    // MARK: - Properties
    
    internal let ndk: NDK
    internal var proofs: [CashuSwift.Proof] = []
    private let p2pkManager: P2PKManager // Manages P2PK keys for receiving nutzaps
    
    // Relay health monitoring
    internal var walletRelays: [NDKRelay] = []
    
    // Unified wallet subscription
    private var walletSubscriptionTask: Task<Void, Never>?
    
    // MARK: - Managers
    
    private let proofStateManager = ProofStateManager()
    private let eventManager: WalletEventManager
    private let paymentProcessor: PaymentProcessor
    private let nutzapProcessor: NutzapProcessor
    private let healthMonitor: WalletHealthMonitor
    private let eventProcessor = WalletEventProcessor()
    private let mintManager: MintManager
    private let depositManager: CashuDepositManager
    private let crossMintTransferService: CrossMintTransferService
    
    // MARK: - Initialization
    
    public init(ndk: NDK, cache: NDKCache? = nil) {
        self.ndk = ndk
        self.p2pkManager = P2PKManager()
        self.eventManager = WalletEventManager(ndk: ndk)
        self.mintManager = MintManager(cache: cache ?? ndk.cache)
        
        // Initialize processors
        self.paymentProcessor = PaymentProcessor(
            proofStateManager: proofStateManager,
            eventManager: eventManager
        )
        self.nutzapProcessor = NutzapProcessor(
            proofStateManager: proofStateManager,
            eventManager: eventManager,
            p2pkManager: p2pkManager,
            ndk: ndk
        )
        self.healthMonitor = WalletHealthMonitor(
            eventManager: eventManager,
            ndk: ndk
        )
        
        self.depositManager = CashuDepositManager(
            eventManager: eventManager,
            proofStateManager: proofStateManager
        )
        self.crossMintTransferService = CrossMintTransferService(
            paymentProcessor: paymentProcessor,
            depositManager: depositManager,
            mintManager: mintManager,
            proofStateManager: proofStateManager
        )
    }
    
    // MARK: - Helper Methods
    
    /// Get the signer or throw if not configured
    private func requireSigner() async throws -> NDKSigner {
        guard let signer = ndk.signer else {
            throw NDKError.notConfigured("No signer configured")
        }
        return signer
    }
    
    // MARK: - Unified Wallet State Subscription
    
    /// Start the unified wallet subscription that monitors all wallet-related events
    public func startWalletSubscription() async {
        guard let signer = try? await requireSigner() else {
            print("❌ Cannot start wallet subscription: No signer configured")
            return
        }
        
        // Cancel any existing subscription
        walletSubscriptionTask?.cancel()
        
        walletSubscriptionTask = Task {
            do {
                let userPubkey = try await signer.pubkey
                
                // Create filters for all wallet-related events
                let filters = [
                    // Our own wallet events
                    NDKFilter(
                        authors: [userPubkey],
                        kinds: [
                            7375,  // Token events
                            7374,  // Quote events
                            7376,  // Spending history
                            17375  // Wallet configuration
                        ]
                    ),
                    // Delete events for our wallet
                    NDKFilter(
                        authors: [userPubkey],
                        kinds: [5],  // Delete events
                        tags: ["k": Set(["7375", "7374"])]  // For token and quote events
                    ),
                    // Incoming nutzaps
                    NDKFilter(
                        kinds: [EventKind.nutzap],
                        tags: ["p": Set([userPubkey])]
                    )
                ]
                
                // Subscribe with wallet-specific relays if configured
                var options = NDKSubscriptionOptions()
                options.closeOnEose = false  // Keep subscription open
                if !walletRelays.isEmpty {
                    options.relays = Set(walletRelays)
                }
                
                print("📡 Starting unified wallet subscription with \(walletRelays.count) relays")
                
                for try await event in ndk.subscribe(filters: filters, options: options) {
                    // Track relay health
                    let seenOnRelays = await ndk.eventTracker.getSeenOnRelays(eventId: event.id)
                    for relayUrl in seenOnRelays {
                        await recordEventFromRelay(event.id, from: relayUrl)
                    }
                    
                    // Process event
                    await processWalletEvent(event)
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
        guard let signer = try? await requireSigner() else {
            print("❌ Cannot process event without signer")
            return
        }
        
        // Special handling for wallet config timestamp check
        if event.kind == 17375 {
            let lastTimestamp = await eventManager.getLastWalletConfigTimestamp()
            if event.createdAt <= lastTimestamp {
                print("⏭️ Skipping older wallet configuration")
                return
            }
            extractWalletRelays(from: event)
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
    
    
    /// Process wallet configuration tags
    internal func processWalletTags(_ walletTags: [[String]]) async {
        for tag in walletTags {
            guard tag.count >= 2 else { continue }
            
            switch tag[0] {
            case "privkey":
                // Restore P2PK private key to the manager
                let privateKey = tag[1]
                // Derive public key from private key
                if let privateKeyData = Data(hexString: privateKey),
                   let privKey = try? secp256k1.Schnorr.PrivateKey(dataRepresentation: privateKeyData) {
                    let publicKey = privKey.publicKey.dataRepresentation.hexString
                    try? await p2pkManager.setKeypair(privateKey: privateKey, publicKey: publicKey)
                }
                
            case "mint":
                let mintURLString = tag[1]
                await mintManager.loadMintFromTag(mintURLString)
                
            default:
                // Unknown tag type
                break
            }
        }
    }
    
    // MARK: - NDKWallet Protocol
    
    public func pay(_ request: PaymentRequest) async throws -> PaymentConfirmation {
        let signer = try await requireSigner()
        
        guard let nutzapRequest = request as? NutzapPaymentRequest else {
            throw NDKError.invalidRequest("NDKCashuWallet only supports nutzap payments")
        }
        
        // Find the best payment route
        let acceptedMintURLs = Set(nutzapRequest.acceptedMints.map { $0.absoluteString })
        let paymentRoute = await crossMintTransferService.findBestPaymentRoute(
            amount: nutzapRequest.amountSats,
            acceptedMints: acceptedMintURLs,
            preferDirectPayment: true
        )
        
        // Determine which mint to use and perform any necessary transfers
        switch paymentRoute {
        case .direct(let mint):
            print("💸 Direct payment using mint: \(mint)")
            // No transfer needed, mint already has sufficient balance
            
        case .crossMint(let sourceMint, let targetMint, let estimatedFee):
            print("💱 Cross-mint transfer required from \(sourceMint) to \(targetMint)")
            if let fee = estimatedFee {
                print("   Estimated fee: \(fee) sats")
            }
            
            // Perform the transfer
            guard let sourceURL = URL(string: sourceMint),
                  let targetURL = URL(string: targetMint) else {
                throw NDKError.invalidRequest("Invalid mint URLs for transfer")
            }
            
            _ = try await crossMintTransferService.transferBetweenMints(
                amount: nutzapRequest.amountSats,
                from: sourceURL,
                to: targetURL,
                wallet: self,
                signer: signer
            )
            
            // Funds are now in the target mint
            
        case .impossible(let reason):
            print("❌ Payment impossible: \(reason)")
            throw NDKError.insufficientBalance(amount: nutzapRequest.amountSats)
        }
        
        // Send nutzap using the processor
        let mints = await mintManager.getAllMints()
        let nutzapEvent = try await nutzapProcessor.sendNutzap(
            wallet: self,
            amount: nutzapRequest.amountSats,
            to: nutzapRequest.recipientPubkey,
            comment: nutzapRequest.comment,
            eventId: nil,
            mints: mints,
            signer: signer
        )
        
        // Use the appropriate mint URL from the route
        let mintUsed: URL
        switch paymentRoute {
        case .direct(let mint):
            mintUsed = URL(string: mint) ?? nutzapRequest.acceptedMints[0]
        case .crossMint(_, let targetMint, _):
            mintUsed = URL(string: targetMint) ?? nutzapRequest.acceptedMints[0]
        case .impossible:
            mintUsed = nutzapRequest.acceptedMints[0]
        }
        
        return NutzapConfirmation(
            amountSats: nutzapRequest.amountSats,
            timestamp: Date(),
            nutzapEvent: nutzapEvent,
            mintUsed: mintUsed
        )
    }
    
    public func getBalance() async throws -> Int64 {
        let balance = await proofStateManager.getTotalBalance()
        print("NDKCashuWallet.getBalance() - balance: \(balance)")
        return balance
    }
    
    public func createInvoice(amount: Int64, description: String?) async throws -> String {
        // For nutzaps, we don't create Lightning invoices
        // Instead, we return a cashu token that can be redeemed
        let mints = await mintManager.getAllMints()
        guard let mint = mints.values.first else {
            throw NDKError.noMintAvailable("No mint configured")
        }
        
        // Select proofs for the amount from the first available mint
        let selectedProofs = await proofStateManager.selectProofs(amount: amount, mint: mint.url.absoluteString)
        guard !selectedProofs.isEmpty else {
            throw NDKError.insufficientBalance(amount: amount)
        }
        
        // Create a token
        let token = CashuSwift.Token(
            proofs: [mint.url.absoluteString: selectedProofs],
            unit: "sat",
            memo: description
        )
        
        // Update state to mark these proofs as deleted
        _ = try await update(
            deletedProofs: selectedProofs,
            addedProofs: []
        )
        
        // Convert token to JSON string (adjust method name based on actual CashuSwift API)
        let tokenData = try JSONEncoder().encode(token)
        guard let tokenString = String(data: tokenData, encoding: .utf8) else {
            throw NDKError.encodingError("Failed to encode token")
        }
        return tokenString
    }
    
    nonisolated public func supports(method: NDKPaymentMethod) -> Bool {
        switch method {
        case .nutzap:
            return true
        case .lightning:
            return true // Now supported via melt
        }
    }
    
    // MARK: - Nutzap Receiving
    
    /// Process an incoming nutzap event
    private func processIncomingNutzap(_ event: NDKEvent) async throws {
        let signer = try await requireSigner()
        
        let mints = await mintManager.getAllMints()
        let keysets = mints.values.flatMap { $0.keysets }.reduce(into: [:]) { result, keyset in
            result[keyset.keysetID] = keyset
        }
        try await nutzapProcessor.processIncomingNutzap(
            wallet: self,
            event,
            mints: mints,
            keysets: keysets,
            signer: signer
        )
    }
    
    // MARK: - Additional Methods
    
    /// Get available mints in this wallet
    public func getMintsInfo() async -> [MintInfo] {
        return await mintManager.getMintsInfo()
    }
    
    /// Find a mint with sufficient balance from a set of accepted mints
    /// - Parameters:
    ///   - acceptedMints: Set of mint URLs that are acceptable
    ///   - requiredAmount: Minimum amount needed
    /// - Returns: Mint URL with sufficient balance, or nil if none found
    public func findMintWithBalance(
        acceptedMints: Set<String>,
        requiredAmount: Int64
    ) async -> String? {
        return await crossMintTransferService.findMintWithSufficientBalance(
            acceptedMints: acceptedMints,
            requiredAmount: requiredAmount
        )
    }
    
    /// Find the best payment route for a given amount and accepted mints
    /// - Parameters:
    ///   - amount: Payment amount
    ///   - acceptedMints: Mints accepted by the recipient
    /// - Returns: Payment route information
    public func findPaymentRoute(
        amount: Int64,
        acceptedMints: Set<String>
    ) async -> PaymentRoute {
        return await crossMintTransferService.findBestPaymentRoute(
            amount: amount,
            acceptedMints: acceptedMints
        )
    }
    
    /// Get the wallet's P2PK pubkey for receiving nutzaps
    public func getP2PKPubkey() async throws -> String {
        return try await p2pkManager.getCashuPublicKey()
    }
    
    /// Publish nutzap preferences (kind 10019) so others know how to send nutzaps to this wallet
    public func publishNutzapPreferences(relays: [String]? = nil) async throws {
        let signer = try await requireSigner()
        
        // Get the P2PK pubkey from the manager
        let p2pkPubkey = try await p2pkManager.getCashuPublicKey()
        
        // Get the relays to publish to (use user's relays if not specified)
        let publishRelays = relays ?? []
        
        var tags: [[String]] = []
        
        // Add relay tags where the user will be reading nutzap events from
        if publishRelays.isEmpty {
            // If no relays specified, use the NDK's current relays
            let currentRelays = await ndk.pool.relays
            for relay in currentRelays {
                tags.append(["relay", relay.url])
            }
        } else {
            for relay in publishRelays {
                tags.append(["relay", relay])
            }
        }
        
        // Add mint tags for all configured mints
        for mintURL in await mintManager.getMintURLs() {
            tags.append(["mint", mintURL])
        }
        
        // Add the P2PK pubkey tag - CRITICAL: This must be the wallet's P2PK key, not the user's Nostr key
        tags.append(["pubkey", p2pkPubkey])
        
        // Create the nutzap preferences event (kind 10019)
        let preferencesEvent = try await NDKEventBuilder()
            .kind(EventKind.nutzapPreferences)
            .tags(tags)
            .build(signer: signer)
        
        // Publish the event
        try await ndk.publish(preferencesEvent)
        
        print("📢 Published nutzap preferences with P2PK pubkey: \(p2pkPubkey)")
    }
    
    /// Check if nutzap preferences have been published
    public func hasPublishedNutzapPreferences() async throws -> Bool {
        let signer = try await requireSigner()
        
        let userPubkey = try await signer.pubkey
        let filter = NDKFilter(
            authors: [userPubkey],
            kinds: [EventKind.nutzapPreferences],
            limit: 1
        )
        
        let events = try await ndk.fetchEvents(filter)
        return !events.isEmpty
    }
    
    /// Get balance for a specific mint
    public func getBalance(mint mintURL: URL) async -> Int64 {
        return await proofStateManager.getBalance(mint: mintURL.absoluteString)
    }
    
    /// Send P2PK-locked proofs to a recipient
    public func send(
        amount: Int64,
        to recipientP2PK: String,
        mint mintURL: URL
    ) async throws -> (proofs: [CashuSwift.Proof], change: [CashuSwift.Proof]?) {
        let signer = try await requireSigner()
        
        let mints = await mintManager.getAllMints()
        return try await paymentProcessor.sendP2PK(
            wallet: self,
            amount: amount,
            to: recipientP2PK,
            mint: mintURL,
            mints: mints,
            signer: signer
        )
    }
    
    /// Pay a Lightning invoice through a mint
    public func payLightning(invoice: String, amount: Int64) async throws -> (preimage: String, feePaid: Int64?) {
        let signer = try await requireSigner()
        
        let mints = await mintManager.getAllMints()
        return try await paymentProcessor.payLightning(
            wallet: self,
            invoice: invoice,
            amount: amount,
            mints: mints,
            signer: signer
        )
    }
    
    /// Estimate fees for a cross-mint transfer
    public func estimateCrossMintTransferFees(
        amount: Int64,
        fromMint sourceMintURL: URL,
        toMint destinationMintURL: URL
    ) async throws -> (lightningFee: Int64, inputFee: Int64, totalFee: Int64) {
        return try await crossMintTransferService.estimateTransferFees(
            amount: amount,
            from: sourceMintURL,
            to: destinationMintURL
        )
    }
    
    /// Transfer funds between mints using Lightning as a bridge
    /// This performs a melt operation on the source mint and a mint operation on the destination mint
    public func transferBetweenMints(
        amount: Int64,
        fromMint sourceMintURL: URL,
        toMint destinationMintURL: URL
    ) async throws -> TransferResult {
        let signer = try await requireSigner()
        
        return try await crossMintTransferService.transferBetweenMints(
            amount: amount,
            from: sourceMintURL,
            to: destinationMintURL,
            wallet: self,
            signer: signer
        )
    }
    
    
    /// Check proof states with all mints and reconcile wallet state
    /// This queries each mint for the status of our proofs and updates our local state accordingly
    public func checkAndReconcileProofStates() async throws {
        let signer = try await requireSigner()
        
        let mints = await mintManager.getAllMints()
        let result = try await healthMonitor.checkAndReconcileProofStates(
            proofStateManager: proofStateManager,
            mints: mints,
            signer: signer
        )
        
        print("🔍 Reconciliation complete - Checked: \(result.totalChecked), Spent: \(result.spentProofs.count), Pending: \(result.pendingProofs.count), Errors: \(result.errors)")
    }
    
    /// Get the health status of wallet relays
    public func getRelayHealthStatus() async -> WalletHealthMonitor.WalletHealthStatus {
        return await healthMonitor.getWalletHealthStatus(walletRelays: walletRelays)
    }
    
    /// Check the health of specific relays
    public func checkRelayHealth() async -> [WalletHealthMonitor.RelayHealth] {
        return await healthMonitor.checkRelayHealth(walletRelays: walletRelays)
    }
    
    
    /// Check proof states for a specific mint
    public func checkProofStates(mintURL: URL) async throws -> [String: CashuSwift.Proof.ProofState] {
        let mints = await mintManager.getAllMints()
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
    
    /// Create a transfer history event for cross-mint transfers
    private func createTransferHistoryEvent(
        amount: Int64,
        fromMint: String,
        toMint: String,
        feePaid: Int64,
        signer: NDKSigner
    ) async throws {
        // Build encrypted tags for transfer details
        var encryptedTags: [[String]] = []
        encryptedTags.append(["direction", "transfer"])
        encryptedTags.append(["amount", String(amount)])
        encryptedTags.append(["fee", String(feePaid)])
        
        // Encrypt the content tags
        let tagsData = try JSONEncoder().encode(encryptedTags)
        guard let plaintext = String(data: tagsData, encoding: .utf8) else {
            throw NDKError.encodingError("Failed to encode transfer history tags")
        }
        
        let signerPubkey = try await signer.pubkey
        let recipient = NDKUser(pubkey: signerPubkey)
        let encryptedContent = try await signer.encrypt(
            recipient: recipient,
            value: plaintext,
            scheme: .nip44
        )
        
        // Create transfer history event (using kind 7376 for spending history)
        let historyEvent = try await NDKEventBuilder()
            .content(encryptedContent)
            .kind(7376)
            .build(signer: signer)
        
        try await ndk.publish(historyEvent)
    }
    
    /// Request a mint quote for depositing via Lightning
    public func requestMint(
        amount: Int64,
        mintURL: String,
        persistQuote: Bool = false
    ) async throws -> CashuMintQuote {
        let signer = persistQuote ? try await requireSigner() : nil
        return try await depositManager.requestMintQuote(
            amount: amount,
            mintURL: mintURL,
            mintManager: mintManager,
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
                    let signer = try await self.requireSigner()
                    let stream = await self.depositManager.monitorDeposit(
                        quote: quote,
                        mintManager: self.mintManager,
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
        _ = try await requireSigner() // Verify signer exists
        
        // Clear state before starting
        await proofStateManager.clear()
        await eventManager.clearTrackedEvents()
        
        // Start the subscription - this will load all events including historical ones
        await startWalletSubscription()
    }
    
    
    
    /// Add mint to wallet
    public func addMint(url: URL) async throws {
        try await mintManager.addMint(url: url)
        
        // Save updated wallet configuration
        try await save()
    }
    
    /// Get mint info (uses cache if available)
    public func getMintInfo(url: URL) async throws -> NDKMintInfo {
        return try await mintManager.getMintInfo(url: url)
    }
    
    
    /// Refresh mint keysets from network (useful when keysets change)
    public func refreshMintKeysets(url: URL) async throws {
        try await mintManager.refreshMintKeysets(url: url)
    }
    
    /// Remove mint from wallet
    public func removeMint(url: URL) async throws {
        // Remove proofs associated with this mint
        let mintKeysetIds = await mintManager.removeMint(url: url)
        proofs.removeAll { proof in
            mintKeysetIds.contains(proof.keysetID)
        }
        
        // Save updated wallet configuration
        try await save()
    }
    
    /// Receive proofs from another user or source
    public func receive(proofs proofsToAdd: [CashuSwift.Proof]) async throws {
        // Validate proofs have corresponding keysets
        for proof in proofsToAdd {
            guard await mintManager.hasKeyset(id: proof.keysetID) else {
                throw NDKError.invalidProof("Unknown keyset ID: \(proof.keysetID)")
            }
        }
        
        // Update state (this handles token event creation)
        _ = try await update(
            deletedProofs: [],
            addedProofs: proofsToAdd
        )
    }
    
    /// Save wallet state to NIP-60 events
    /// If relays is nil, falls back to user's outbox write relays
    public func save(relays: [String]? = nil) async throws {
        let signer = try await requireSigner()
        
        // Build wallet configuration tags
        var walletTags: [[String]] = []
        
        // Add P2PK private key
        let (p2pkPrivateKey, _) = try await p2pkManager.getOrCreateKeypair()
        walletTags.append(["privkey", p2pkPrivateKey])
        
        // Add mint URLs
        let mintURLs = await mintManager.getMintURLs()
        for mintURL in mintURLs {
            walletTags.append(["mint", mintURL])
        }
        
        // If no mints, add a default mint
        if mintURLs.isEmpty {
            walletTags.append(["mint", "https://testnut.cashu.space"])
        }
        
        // Only save wallet configuration event
        // Token events are now managed by the update() method
        try await eventManager.saveWalletEvent(signer: signer, relays: relays, walletTags: walletTags)
    }
    
    /// Process a new token event (used when monitoring real-time events)
    public func processIncomingTokenEvent(_ event: NDKEvent) async throws {
        let signer = try await requireSigner()
        
        // Only process events from ourselves
        let userPubkey = try await signer.pubkey
        guard event.pubkey == userPubkey else {
            return
        }
        
        // Process the token event if it's not filtered
        try await processIncomingTokenEvent(event)
    }
    
    
    // MARK: - Relay Health Monitoring
    
    /// Get current relay health from existing monitoring data
    public func getRelayHealth() async -> [WalletHealthMonitor.RelayHealth] {
        return await checkRelayHealth()
    }
    
    /// Republish missing events to a specific relay
    public func repairRelay(_ targetRelay: NDKRelay, missingEventIds: [String]) async throws {
        let signer = try await requireSigner()
        
        for eventId in missingEventIds {
            // Find the event in our current state
            if let event = try await findWalletEvent(eventId, signer: signer) {
                try await ndk.publish(event)
                print("📡 Republished event \(eventId)")
            }
        }
    }
    
    private func findWalletEvent(_ eventId: String, signer: NDKSigner) async throws -> NDKEvent? {
        let userPubkey = try await signer.pubkey
        let filter = NDKFilter(
            ids: [eventId],
            authors: [userPubkey]
        )
        
        let events = try await ndk.fetchEvents(filter)
        return events.first
    }
    
    
    internal func recordEventFromRelay(_ eventId: String, from relayUrl: String) async {
        await healthMonitor.trackEventOnRelay(eventId: eventId, relay: relayUrl)
    }
    
    
    private func extractWalletRelays(from walletEvent: NDKEvent) {
        walletRelays = walletEvent.tags
            .filter { $0.first == "relay" && $0.count > 1 }
            .compactMap { tag in
                guard tag.count > 1 else { return nil }
                let url = tag[1]
                return NDKRelay(url: url)
            }
        print("📡 Extracted \(walletRelays.count) wallet relays from wallet event")
    }
    
    
    // MARK: - Centralized State Management
    
    /// The heart of the system - handles all proof state changes
    internal func update(
        deletedProofs: [CashuSwift.Proof],
        addedProofs: [CashuSwift.Proof]
    ) async throws -> [String] {
        print("NDKCashuWallet.update() - Adding \(addedProofs.count) proofs, deleting \(deletedProofs.count) proofs")
        
        // 1. Update proof states
        await proofStateManager.markProofsAsDeleted(deletedProofs)
        
        for proof in addedProofs {
            // Find mint for this proof
            guard let mint = await mintManager.findMintForKeyset(proof.keysetID) else {
                throw NDKError.invalidProof("Proof with unknown keyset: \(proof.keysetID)")
            }
            await proofStateManager.addProof(proof, mint: mint)
            print("  Added proof: amount=\(proof.amount), C=\(proof.C)")
        }
        
        // 2. Group available proofs by mint
        let availableByMint = await proofStateManager.getAvailableProofsByMint()
        
        // 3. Update token events through the event manager
        let signer = try await requireSigner()
        
        let newEventIds = try await eventManager.updateTokenEvents(
            availableProofsByMint: availableByMint,
            proofStateManager: proofStateManager,
            signer: signer
        )
        
        // 4. Update tracking
        await eventManager.setCurrentTokenEventIds(Set(newEventIds))
        
        // 6. Update internal proofs array for compatibility
        self.proofs = availableByMint.values.flatMap { $0 }
        
        // Return the newly created event IDs
        return Array(newEventIds)
    }
    
    
    
    
    
    // MARK: - Public Types
    
    /// Get the mints dictionary for processors to use
    public func getMints() async -> [String: CashuSwift.Mint] {
        return await mintManager.getAllMints()
    }
    
    // MARK: - Helper Methods for Event Handlers
    
    /// Check if wallet has a specific keyset
    internal func hasKeyset(_ keysetId: String) async -> Bool {
        return await mintManager.hasKeyset(id: keysetId)
    }
    
    /// Find mint URL for a given keyset ID
    internal func findMintForKeyset(_ keysetId: String) async -> String? {
        return await mintManager.findMintForKeyset(keysetId)
    }
    
    /// Update internal proofs array from state manager
    internal func updateProofsFromStateManager() async {
        self.proofs = await proofStateManager.getAvailableProofs()
    }
    
    /// Load mint (with caching if available)
    internal func loadMint(url: URL) async throws -> CashuSwift.Mint {
        return try await mintManager.loadMint(url: url)
    }
    
    /// Add mint to wallet
    internal func addMint(_ mint: CashuSwift.Mint, url: String) async throws {
        if let mintUrl = URL(string: url) {
            try await mintManager.addMint(url: mintUrl)
        }
    }
    
    /// Add keyset to wallet
    internal func addKeyset(_ keyset: CashuSwift.Keyset) async {
        await mintManager.addKeyset(keyset)
    }
    
    /// Process incoming nutzap event (for handler)
    internal func processIncomingNutzapEvent(_ event: NDKEvent) async throws {
        try await processIncomingNutzap(event)
    }
}

// MARK: - Payment Types

/// Mint quote for Lightning deposits
public struct CashuMintQuote: Codable {
    public let quoteId: String
    public let mintURL: String
    public let amount: Int64
    public let invoice: String
    public let expiry: Date
    public let requestedAt: Date
    
    public init(quoteId: String, mintURL: String, amount: Int64, invoice: String, expiry: Date, requestedAt: Date) {
        self.quoteId = quoteId
        self.mintURL = mintURL
        self.amount = amount
        self.invoice = invoice
        self.expiry = expiry
        self.requestedAt = requestedAt
    }
}

/// Deposit status for monitoring Lightning deposits to mint
public enum DepositStatus {
    case pending
    case minted(proofs: [CashuSwift.Proof])  // Tokens successfully minted after deposit
    case expired
    case cancelled
}

/// Result of a cross-mint transfer operation
public struct TransferResult {
    public let amountTransferred: Int64
    public let feePaid: Int64
    public let preimage: String
    public let sourceMint: URL
    public let destinationMint: URL
}

// MARK: - Error Extensions

extension NDKError {
    static func invalidProof(_ message: String) -> NDKError {
        return NDKError.walletError(message: "Invalid proof: \(message)")
    }
    
    static func depositNotReady(_ message: String) -> NDKError {
        return NDKError.walletError(message: "Deposit not ready: \(message)")
    }
}