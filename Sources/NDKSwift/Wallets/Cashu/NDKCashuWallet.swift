import Foundation
import CashuSwift
import secp256k1

/// NIP-60 Cashu wallet implementation
public actor NDKCashuWallet: NDKWallet {
    // MARK: - Properties
    
    internal let ndk: NDK
    public let walletId: String // For API compatibility, but not used in NIP-60
    internal var proofs: [CashuSwift.Proof] = []
    internal var mints: [String: CashuSwift.Mint] = [:] // URL string to Mint
    internal var keysets: [String: CashuSwift.Keyset] = [:] // Keyset ID to Keyset
    private let p2pkManager: P2PKManager // Manages P2PK keys for receiving nutzaps
    private let mintLoader: CachedMintLoader? // Cached mint loader for performance
    
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
    
    /// Mint discovery service for finding mints via Nostr
    public let mintDiscovery: MintDiscovery
    
    // MARK: - Initialization
    
    public init(ndk: NDK, walletId: String? = nil, mintCache: MintCache? = nil) {
        self.ndk = ndk
        self.walletId = walletId ?? UUID().uuidString
        self.mintDiscovery = MintDiscovery(ndk: ndk)
        self.p2pkManager = P2PKManager()
        self.eventManager = WalletEventManager(ndk: ndk)
        
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
        
        // Set up cached mint loader if cache is provided
        if let cache = mintCache {
            self.mintLoader = CachedMintLoader(cache: cache)
        } else {
            self.mintLoader = nil
        }
        
        // Complete initialization by setting wallet references
        Task {
            await paymentProcessor.setWallet(self)
            await nutzapProcessor.setWallet(self)
        }
    }
    
    // MARK: - Unified Wallet State Subscription
    
    /// Start the unified wallet subscription that monitors all wallet-related events
    public func startWalletSubscription() async {
        guard let signer = ndk.signer else {
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
        do {
            switch event.kind {
            case 17375:  // Wallet configuration
                let lastTimestamp = await eventManager.getLastWalletConfigTimestamp()
                if event.createdAt > lastTimestamp {
                    print("📝 Processing wallet configuration update")
                    extractWalletRelays(from: event)
                    await eventManager.updateLastWalletConfigTimestamp(event.createdAt)
                    
                    // Process wallet configuration
                    let sender = NDKUser(pubkey: event.pubkey)
                    let decryptedContent = try await ndk.signer!.decrypt(
                        sender: sender,
                        value: event.content,
                        scheme: .nip44
                    )
                    
                    // Parse and process wallet tags
                    if let walletData = decryptedContent.data(using: .utf8),
                       let walletTags = try? JSONDecoder().decode([[String]].self, from: walletData) {
                        await processWalletTags(walletTags)
                    }
                    
                    // Restart subscription with new relays
                    await startWalletSubscription()
                }
                
            case 7375:  // Token event
                // First check if we should process this event
                if await eventManager.shouldFilterEvent(event.id) {
                    print("⏭️ Skipping deleted or superseded token event: \(event.id)")
                    return
                }
                
                print("💰 Processing token event: \(event.id)")
                
                // Decrypt and process token
                let sender = NDKUser(pubkey: event.pubkey)
                let decryptedContent = try await ndk.signer!.decrypt(
                    sender: sender,
                    value: event.content,
                    scheme: .nip44
                )
                
                // Parse token data
                guard let tokenData = decryptedContent.data(using: .utf8),
                      let nip60Token = try? JSONDecoder().decode(NIP60TokenEvent.self, from: tokenData) else {
                    throw NDKError.invalidContent("Failed to parse NIP-60 token event data")
                }
                
                // Update superseded events if this event has del tags
                if let delIds = nip60Token.del {
                    await eventManager.markEventsSuperseded(delIds)
                    // Remove superseded events from current set
                    for delId in delIds {
                        let current = await eventManager.getCurrentTokenEventIds()
                        await eventManager.setCurrentTokenEventIds(current.subtracting([delId]))
                    }
                }
                
                // Add proofs to state
                for proof in nip60Token.proofs {
                    // Store proof if we have the corresponding keyset
                    if keysets[proof.keysetID] != nil {
                        // Find mint for this proof
                        var foundMint: String?
                        for (mintUrl, mint) in mints {
                            if mint.keysets.contains(where: { $0.keysetID == proof.keysetID }) {
                                foundMint = mintUrl
                                break
                            }
                        }
                        if let mint = foundMint {
                            await proofStateManager.addProof(proof, mint: mint)
                        }
                    }
                }
                
                await eventManager.addCurrentTokenEventId(event.id)
                
                // Update internal proofs array
                self.proofs = await proofStateManager.getAvailableProofs()
                
            case 7374:  // Quote event
                print("📋 Processing quote event: \(event.id)")
                // Quote events are handled separately for now
                // TODO: Add quote event processing if needed
                
            case 7376:  // Spending history
                print("📊 Processing spending history event: \(event.id)")
                // History events are informational only
                
            case 5:  // Delete event
                print("🗑️ Processing delete event")
                for tag in event.tags where tag.count >= 2 && tag[0] == "e" {
                    let deletedEventId = tag[1]
                    await eventManager.markEventDeleted(deletedEventId)
                    let current = await eventManager.getCurrentTokenEventIds()
                    await eventManager.setCurrentTokenEventIds(current.subtracting([deletedEventId]))
                    
                    // Remove proofs from deleted token event
                    if tag.count >= 4 && tag[3] == "7375" {
                        // This is a token event deletion
                        await removeProofsFromDeletedEvent(deletedEventId)
                    }
                }
                
            case EventKind.nutzap:  // Incoming nutzap
                print("💸 Processing incoming nutzap: \(event.id)")
                try await processIncomingNutzap(event)
                
            default:
                // Ignore other event kinds
                break
            }
        } catch {
            print("❌ Failed to process wallet event \(event.id): \(error)")
        }
    }
    
    /// Remove proofs associated with a deleted token event from state
    private func removeProofsFromDeletedEvent(_ eventId: String) async {
        // Since we don't track which proofs belong to which event ID,
        // we need to re-evaluate our proof state
        // This is handled by the update() method when new events arrive
        print("🗑️ Marked token event as deleted: \(eventId)")
    }
    
    /// Process wallet configuration tags
    private func processWalletTags(_ walletTags: [[String]]) async {
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
                guard let mintURL = URL(string: mintURLString) else { continue }
                
                do {
                    let mint: CashuSwift.Mint
                    if let loader = mintLoader {
                        mint = try await loader.loadMint(url: mintURL)
                    } else {
                        mint = try await CashuSwift.loadMint(url: mintURL)
                    }
                    mints[mintURLString] = mint
                    
                    // Store keysets
                    for keyset in mint.keysets {
                        keysets[keyset.keysetID] = keyset
                    }
                } catch {
                    print("Failed to load mint \(mintURLString): \(error)")
                }
                
            default:
                // Unknown tag type
                break
            }
        }
    }
    
    // MARK: - NDKWallet Protocol
    
    public func pay(_ request: NDKPaymentRequest) async throws -> NDKPaymentConfirmation {
        guard let signer = ndk.signer else {
            throw NDKError.notConfigured("No signer configured for NDKCashuWallet")
        }
        
        guard let nutzapRequest = request as? NDKNutzapRequest else {
            throw NDKError.invalidRequest("NDKCashuWallet only supports nutzap payments")
        }
        
        // Find a common mint between our wallet and the accepted mints
        let acceptedMintURLs = Set(nutzapRequest.mints.map { $0.absoluteString })
        let ourMintURLs = Set(mints.keys)
        let commonMintURLs = ourMintURLs.intersection(acceptedMintURLs)
        
        // First, try to find a common mint with sufficient balance
        var selectedMintURL: String? = nil
        for mintURL in commonMintURLs {
            let balance = await getBalance(mint: URL(string: mintURL)!)
            if balance >= nutzapRequest.amount {
                selectedMintURL = mintURL
                break
            }
        }
        
        // If no common mint has sufficient balance, try cross-mint transfer
        if selectedMintURL == nil {
            // Find any accepted mint we can transfer to
            guard let targetMintURL = acceptedMintURLs.first,
                  let targetMint = URL(string: targetMintURL) else {
                throw NDKError.noMintAvailable("No valid recipient mint found")
            }
            
            // Find a source mint with sufficient balance
            var sourceMint: URL? = nil
            for (mintURL, _) in mints {
                let balance = await getBalance(mint: URL(string: mintURL)!)
                // Need extra balance for fees
                if balance >= nutzapRequest.amount + 1000 { // Add 1000 sats buffer for fees
                    sourceMint = URL(string: mintURL)
                    break
                }
            }
            
            guard let sourceMintURL = sourceMint else {
                throw NDKError.insufficientBalance(amount: nutzapRequest.amount)
            }
            
            // Perform cross-mint transfer
            print("💱 Performing cross-mint transfer from \(sourceMintURL) to \(targetMintURL)")
            _ = try await transferBetweenMints(
                amount: nutzapRequest.amount,
                fromMint: sourceMintURL,
                toMint: targetMint
            )
            
            selectedMintURL = targetMintURL
        }
        
        // Send nutzap using the processor
        let nutzapEvent = try await nutzapProcessor.sendNutzap(
            amount: nutzapRequest.amount,
            to: nutzapRequest.recipientPubkey,
            comment: nutzapRequest.comment,
            eventId: nil,
            mints: mints,
            signer: signer
        )
        
        return NDKCashuPaymentConfirmation(
            amount: nutzapRequest.amount,
            recipient: nutzapRequest.recipientPubkey,
            timestamp: Date(),
            nutzap: nutzapEvent
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
        try await update(
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
        case .nwc:
            return false // We don't support NWC
        }
    }
    
    // MARK: - Nutzap Receiving
    
    /// Process an incoming nutzap event
    private func processIncomingNutzap(_ event: NDKEvent) async throws {
        guard let signer = ndk.signer else {
            throw NDKError.notConfigured("No signer configured")
        }
        
        try await nutzapProcessor.processIncomingNutzap(
            event,
            mints: mints,
            keysets: keysets,
            signer: signer
        )
    }
    
    
    /// Check if a nutzap has already been processed
    private func hasProcessedNutzap(eventId: String) async -> Bool {
        // Check for a processed nutzap marker event (kind 7377)
        guard let signer = ndk.signer else { return false }
        
        do {
            let filter = NDKFilter(
                authors: [try await signer.pubkey],
                kinds: [7377], // Processed nutzap marker
                tags: ["e": Set([eventId])]
            )
            
            let events = try await ndk.fetchEvents(filter)
            return !events.isEmpty
        } catch {
            return false
        }
    }
    
    /// Mark a nutzap as processed
    private func markNutzapProcessed(eventId: String, amount: Int64) async throws {
        guard let signer = ndk.signer else {
            throw NDKError.notConfigured("No signer configured")
        }
        
        // Create a marker event
        let markerEvent = try await NDKEventBuilder()
            .content(String(amount)) // Store amount for reference
            .kind(7377) // Processed nutzap marker
            .tags([
                ["e", eventId],
                ["amount", String(amount)]
            ])
            .build(signer: signer)
        
        try await ndk.publish(markerEvent)
    }
    
    
    // MARK: - Additional Methods
    
    /// Get available mints in this wallet
    public func getMintsInfo() async -> [MintInfo] {
        return mints.values.map { mint in
            MintInfo(
                url: mint.url
            )
        }
    }
    
    /// Get the wallet's P2PK pubkey for receiving nutzaps
    public func getP2PKPubkey() async throws -> String {
        return try await p2pkManager.getCashuPublicKey()
    }
    
    /// Publish nutzap preferences (kind 10019) so others know how to send nutzaps to this wallet
    public func publishNutzapPreferences(relays: [String]? = nil) async throws {
        guard let signer = ndk.signer else {
            throw NDKError.notConfigured("No signer configured")
        }
        
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
        for mintURL in mints.keys {
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
        guard let signer = ndk.signer else {
            throw NDKError.notConfigured("No signer configured")
        }
        
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
        guard let signer = ndk.signer else {
            throw NDKError.notConfigured("No signer configured")
        }
        
        return try await paymentProcessor.sendP2PK(
            amount: amount,
            to: recipientP2PK,
            mint: mintURL,
            mints: mints,
            signer: signer
        )
    }
    
    /// Pay a Lightning invoice through a mint
    public func payLightning(invoice: String, amount: Int64) async throws -> (preimage: String, feePaid: Int64?) {
        guard let signer = ndk.signer else {
            throw NDKError.notConfigured("No signer configured")
        }
        
        return try await paymentProcessor.payLightning(
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
        // Validate mints exist
        guard let sourceMint = mints[sourceMintURL.absoluteString] else {
            throw NDKError.invalidRequest("Source mint not found in wallet")
        }
        guard let destinationMint = mints[destinationMintURL.absoluteString] else {
            throw NDKError.invalidRequest("Destination mint not found in wallet")
        }
        
        // Request a mint quote to get the Lightning invoice
        let mintQuote = try await requestMint(
            amount: amount,
            mintURL: destinationMintURL.absoluteString,
            persistQuote: false
        )
        
        // Create melt quote request to estimate fees
        let quoteRequest = CashuSwift.Bolt11.RequestMeltQuote(
            unit: "sat",
            request: mintQuote.invoice,
            options: nil
        )
        
        // Get melt quote from source mint
        let meltQuote = try await CashuSwift.getQuote(
            mint: sourceMint,
            quoteRequest: quoteRequest
        ) as! CashuSwift.Bolt11.MeltQuote
        
        // Get available proofs for fee calculation
        let availableProofs = await proofStateManager.getAvailableProofs(mint: sourceMintURL.absoluteString)
        
        // Calculate fees
        let lightningFee = Int64(meltQuote.feeReserve)
        let inputFee = try CashuSwift.calculateFee(for: availableProofs, of: sourceMint)
        let totalFee = lightningFee + Int64(inputFee)
        
        return (lightningFee: lightningFee, inputFee: Int64(inputFee), totalFee: totalFee)
    }
    
    /// Transfer funds between mints using Lightning as a bridge
    /// This performs a melt operation on the source mint and a mint operation on the destination mint
    public func transferBetweenMints(
        amount: Int64,
        fromMint sourceMintURL: URL,
        toMint destinationMintURL: URL
    ) async throws -> TransferResult {
        guard let signer = ndk.signer else {
            throw NDKError.notConfigured("No signer configured")
        }
        
        let result = try await paymentProcessor.transferBetweenMints(
            from: sourceMintURL,
            to: destinationMintURL,
            amount: amount,
            mints: mints,
            signer: signer
        )
        
        return TransferResult(
            amountTransferred: amount,
            feePaid: result.feePaid,
            preimage: result.preimage,
            sourceMint: sourceMintURL,
            destinationMint: destinationMintURL
        )
    }
    
    
    /// Check proof states with all mints and reconcile wallet state
    /// This queries each mint for the status of our proofs and updates our local state accordingly
    public func checkAndReconcileProofStates() async throws {
        guard let signer = ndk.signer else {
            throw NDKError.notConfigured("No signer configured")
        }
        
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
    
    /// Start periodic proof state checking
    /// This will check proof states at regular intervals and reconcile any discrepancies
    public func startPeriodicProofStateCheck(interval: TimeInterval = 300) async { // Default 5 minutes
        print("🔄 Starting periodic proof state checking every \(interval) seconds")
        
        while true {
            do {
                try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                
                print("⏰ Running periodic proof state check...")
                try await checkAndReconcileProofStates()
                
            } catch {
                if error is CancellationError {
                    print("🛑 Periodic proof state checking cancelled")
                    break
                } else {
                    print("❌ Error in periodic proof check: \(error)")
                    // Continue checking even if there's an error
                }
            }
        }
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
        encryptedTags.append(["from_mint", fromMint])
        encryptedTags.append(["to_mint", toMint])
        encryptedTags.append(["fee", String(feePaid)])
        encryptedTags.append(["timestamp", String(Timestamp.now)])
        
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
            .tags([["type", "cross_mint_transfer"]]) // Clear tag to identify transfer type
            .build(signer: signer)
        
        try await ndk.publish(historyEvent)
    }
    
    /// Request a mint quote for depositing via Lightning
    public func requestMint(
        amount: Int64,
        mintURL: String,
        persistQuote: Bool = false
    ) async throws -> CashuMintQuote {
        guard let mintUrl = URL(string: mintURL) else {
            throw NDKError.invalidRequest("Invalid mint URL")
        }
        
        // Load mint if we don't have it yet
        if mints[mintURL] == nil {
            let mint = try await CashuSwift.loadMint(url: mintUrl)
            mints[mintURL] = mint
            
            // Store keysets
            for keyset in mint.keysets {
                keysets[keyset.keysetID] = keyset
            }
        }
        
        guard let mint = mints[mintURL] else {
            throw NDKError.noMintAvailable("Failed to load mint")
        }
        
        // Request mint quote from the mint
        let quoteRequest = CashuSwift.Bolt11.RequestMintQuote(
            unit: "sat",
            amount: Int(amount)
        )
        
        let quoteResponse = try await CashuSwift.getQuote(
            mint: mint,
            quoteRequest: quoteRequest
        ) as! CashuSwift.Bolt11.MintQuote
        
        // Create our quote structure
        let quote = CashuMintQuote(
            quoteId: quoteResponse.quote,
            mintURL: mintURL,
            amount: amount,
            invoice: quoteResponse.request,
            expiry: Date().addingTimeInterval(TimeInterval(quoteResponse.expiry ?? 600)),
            requestedAt: Date()
        )
        
        // If persistQuote is true, save it as a NIP-60 quote event (kind 7374)
        if persistQuote {
            guard let signer = ndk.signer else {
                throw NDKError.notConfigured("No signer configured")
            }
            try await eventManager.saveQuoteEvent(quote: quote, signer: signer)
        }
        
        return quote
    }
    
    /// Monitor deposit status for a mint quote (checking if Lightning invoice was paid)
    public func monitorDeposit(
        quote: CashuMintQuote,
        pollingInterval: TimeInterval = 5.0,
        timeout: TimeInterval = 600.0
    ) -> AsyncThrowingStream<DepositStatus, Error> {
        return AsyncThrowingStream { continuation in
            let task = Task {
                let startTime = Date()
                
                do {
                    while Date().timeIntervalSince(startTime) < timeout {
                        // Check if Lightning invoice has been paid to the mint
                        do {
                            let proofs = try await self.checkAndMintTokens(quote: quote)
                            
                            if !proofs.isEmpty {
                                // Deposit successful - tokens minted, delete the quote event
                                guard let signer = self.ndk.signer else {
                                    throw NDKError.notConfigured("No signer configured")
                                }
                                try await self.eventManager.deleteQuoteEvent(quoteId: quote.quoteId, signer: signer)
                                
                                // Update wallet state properly with the new proofs
                                let createdEventIds = try await self.update(
                                    deletedProofs: [],
                                    addedProofs: proofs
                                )
                                
                                // Create history event for the lightning deposit
                                if let signer = self.ndk.signer {
                                    Task {
                                        do {
                                            try await self.eventManager.createSpendingHistoryEvent(
                                                direction: .in,
                                                amount: Int64(quote.amount),
                                                createdEventIds: createdEventIds,
                                                signer: signer
                                            )
                                            print("✅ Created NIP-60 history event for lightning deposit of \(quote.amount) sats")
                                        } catch {
                                            print("⚠️ Failed to create history event for deposit: \(error)")
                                        }
                                    }
                                }
                                
                                continuation.yield(.minted(proofs: proofs))
                                continuation.finish()
                                return
                            }
                        } catch {
                            // If it's a specific error indicating deposit not ready, continue polling
                            // Otherwise, it might be a real error
                            if case CashuError.quoteNotPaid = error {
                                // Expected - deposit not ready yet, continue polling
                            } else {
                                throw error
                            }
                        }
                        
                        // Still pending
                        continuation.yield(.pending)
                        
                        // Wait before next check
                        try await Task.sleep(nanoseconds: UInt64(pollingInterval * 1_000_000_000))
                    }
                    
                    // Timeout reached - persist quote and mark as expired
                    guard let signer = self.ndk.signer else {
                        throw NDKError.notConfigured("No signer configured")
                    }
                    try await self.eventManager.saveQuoteEvent(quote: quote, signer: signer)
                    continuation.yield(.expired)
                    continuation.finish()
                    
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
    
    /// Check if Lightning deposit has been made and mint tokens
    private func checkAndMintTokens(quote: CashuMintQuote) async throws -> [CashuSwift.Proof] {
        guard let mint = mints[quote.mintURL] else {
            throw NDKError.noMintAvailable("Mint not found")
        }
        
        // Check mint quote status
        let statusResponse = try await CashuSwift.mintQuoteState(
            for: quote.quoteId,
            mint: mint
        )
        
        // Check if Lightning invoice has been paid
        guard statusResponse.paid == true else {
            throw NDKError.depositNotReady("Deposit not yet received by mint")
        }
        
        // Generate outputs for minting
        let distribution = splitIntoBase2(Int(quote.amount))
        
        // Create mint quote with request details for issue function
        var mintQuote = statusResponse
        mintQuote.requestDetail = CashuSwift.Bolt11.RequestMintQuote(
            unit: "sat",
            amount: Int(quote.amount)
        )
        
        // Issue tokens using the quote
        let (proofs, validDLEQ) = try await CashuSwift.issue(
            for: mintQuote,
            with: mint,
            seed: nil,
            preferredDistribution: distribution
        )
        
        // Check DLEQ verification
        guard validDLEQ else {
            throw NDKError.invalidProof("DLEQ verification failed")
        }
        
        return proofs
    }
    
    
    /// Initialize wallet by subscribing to wallet events
    public func load() async throws {
        guard let signer = ndk.signer else {
            throw NDKError.notConfigured("No signer configured for NDKCashuWallet")
        }
        
        // Clear state before starting
        await proofStateManager.clear()
        await eventManager.clearTrackedEvents()
        
        // Start the subscription - this will load all events including historical ones
        await startWalletSubscription()
    }
    
    
    
    /// Add mint to wallet
    public func addMint(url: URL) async throws {
        let mint: CashuSwift.Mint
        
        // Use cached loader if available, otherwise load directly
        if let loader = mintLoader {
            mint = try await loader.loadMint(url: url)
        } else {
            mint = try await CashuSwift.loadMint(url: url)
        }
        
        mints[url.absoluteString] = mint
        
        // Store keysets
        for keyset in mint.keysets {
            keysets[keyset.keysetID] = keyset
        }
        
        // Save updated wallet configuration
        try await save()
    }
    
    /// Get mint info (uses cache if available)
    public func getMintInfo(url: URL) async throws -> NDKMintInfo {
        if let loader = mintLoader {
            return try await loader.loadMintInfo(url: url)
        } else {
            // Fallback to direct network fetch
            let infoUrl = url.appending(path: "/v1/info")
            let data = try await URLSession.shared.data(from: infoUrl).0
            return try JSONDecoder().decode(NDKMintInfo.self, from: data)
        }
    }
    
    /// Get mint info as raw data (for backward compatibility)
    public func getMintInfoData(url: URL) async throws -> Data {
        let mintInfo = try await getMintInfo(url: url)
        return try mintInfo.toJSONData()
    }
    
    /// Refresh mint keysets from network (useful when keysets change)
    public func refreshMintKeysets(url: URL) async throws {
        // If we have a loader, use it with forceRefresh
        if let loader = mintLoader {
            let mint = try await loader.loadMint(url: url, forceRefresh: true)
            mints[url.absoluteString] = mint
            
            // Update keysets
            for keyset in mint.keysets {
                keysets[keyset.keysetID] = keyset
            }
        } else {
            // Direct load without cache
            let mint = try await CashuSwift.loadMint(url: url)
            mints[url.absoluteString] = mint
            
            // Update keysets
            for keyset in mint.keysets {
                keysets[keyset.keysetID] = keyset
            }
        }
    }
    
    /// Remove mint from wallet
    public func removeMint(url: URL) async throws {
        // Remove proofs associated with this mint
        let mintKeysetIds = mints[url.absoluteString]?.keysets.map { $0.keysetID } ?? []
        proofs.removeAll { proof in
            mintKeysetIds.contains(proof.keysetID)
        }
        
        // Remove keysets
        for keysetId in mintKeysetIds {
            keysets.removeValue(forKey: keysetId)
        }
        
        // Remove mint
        mints.removeValue(forKey: url.absoluteString)
        
        // Save updated wallet configuration
        try await save()
    }
    
    /// Receive proofs from another user or source
    public func receive(proofs proofsToAdd: [CashuSwift.Proof]) async throws {
        // Validate proofs have corresponding keysets
        for proof in proofsToAdd {
            guard keysets[proof.keysetID] != nil else {
                throw NDKError.invalidProof("Unknown keyset ID: \(proof.keysetID)")
            }
        }
        
        // Update state (this handles token event creation)
        try await update(
            deletedProofs: [],
            addedProofs: proofsToAdd
        )
    }
    
    /// Save wallet state to NIP-60 events
    public func save() async throws {
        guard let signer = ndk.signer else {
            throw NDKError.notConfigured("No signer configured for NDKCashuWallet")
        }
        
        // Build wallet configuration tags
        var walletTags: [[String]] = []
        
        // Add P2PK private key
        let (p2pkPrivateKey, _) = try await p2pkManager.getOrCreateKeypair()
        walletTags.append(["privkey", p2pkPrivateKey])
        
        // Add mint URLs
        for mintURL in mints.keys {
            walletTags.append(["mint", mintURL])
        }
        
        // If no mints, add a default mint
        if mints.isEmpty {
            walletTags.append(["mint", "https://testnut.cashu.space"])
        }
        
        // Only save wallet configuration event
        // Token events are now managed by the update() method
        try await eventManager.saveWalletEvent(signer: signer, walletTags: walletTags)
    }
    
    /// Save wallet state to NIP-60 events with specific relays
    /// If relays is nil, falls back to user's outbox write relays
    public func save(relays: [String]?) async throws {
        guard let signer = ndk.signer else {
            throw NDKError.notConfigured("No signer configured for NDKCashuWallet")
        }
        
        // Build wallet configuration tags
        var walletTags: [[String]] = []
        
        // Add P2PK private key
        let (p2pkPrivateKey, _) = try await p2pkManager.getOrCreateKeypair()
        walletTags.append(["privkey", p2pkPrivateKey])
        
        // Add mint URLs
        for mintURL in mints.keys {
            walletTags.append(["mint", mintURL])
        }
        
        // If no mints, add a default mint
        if mints.isEmpty {
            walletTags.append(["mint", "https://testnut.cashu.space"])
        }
        
        // Only save wallet configuration event
        // Token events are now managed by the update() method
        try await eventManager.saveWalletEvent(signer: signer, relays: relays, walletTags: walletTags)
    }
    
    /// Process a new token event (used when monitoring real-time events)
    public func processIncomingTokenEvent(_ event: NDKEvent) async throws {
        guard let signer = ndk.signer else {
            throw NDKError.notConfigured("No signer configured")
        }
        
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
        guard let signer = ndk.signer else {
            throw NDKError.notConfigured("No signer configured")
        }
        
        for eventId in missingEventIds {
            // Find the event in our current state
            if let event = try await findWalletEvent(eventId, signer: signer) {
                try await ndk.publish(event)
                print("📡 Republished event \(eventId)")
            }
        }
    }
    
    /// Get all current wallet events for manual repair operations
    public func getCurrentWalletEvents() async throws -> [NDKEvent] {
        guard let signer = ndk.signer else {
            throw NDKError.notConfigured("No signer configured")
        }
        
        let userPubkey = try await signer.pubkey
        let filter = NDKFilter(
            authors: [userPubkey],
            kinds: [17375, 7375, 7374, 7376] // All wallet-related kinds
        )
        
        let events = try await ndk.fetchEvents(filter)
        var filtered: [NDKEvent] = []
        for event in events {
            if !(await eventManager.shouldFilterEvent(event.id)) {
                filtered.append(event)
            }
        }
        return filtered
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
            var foundMint: String?
            for (mintUrl, mint) in mints {
                if mint.keysets.contains(where: { $0.keysetID == proof.keysetID }) {
                    foundMint = mintUrl
                    break
                }
            }
            guard let mint = foundMint else {
                throw NDKError.invalidProof("Proof with unknown keyset: \(proof.keysetID)")
            }
            await proofStateManager.addProof(proof, mint: mint)
            print("  Added proof: amount=\(proof.amount), C=\(proof.C)")
        }
        
        // 2. Group available proofs by mint
        let availableByMint = await proofStateManager.getAvailableProofsByMint()
        
        // 3. Update token events through the event manager
        guard let signer = ndk.signer else {
            throw NDKError.notConfigured("No signer configured")
        }
        
        let newEventIds = try await eventManager.updateTokenEvents(
            availableProofsByMint: availableByMint,
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
    
    /// Mint information
    public struct MintInfo: Hashable, Equatable {
        public let url: URL
    }
    
    /// Cashu payment confirmation
    public struct NDKCashuPaymentConfirmation: NDKPaymentConfirmation {
        public let amount: Int64
        public let recipient: PublicKey
        public let timestamp: Date
        public let nutzap: NDKEvent
    }
    
    /// Get the mints dictionary for processors to use
    public func getMints() -> [String: CashuSwift.Mint] {
        return mints
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