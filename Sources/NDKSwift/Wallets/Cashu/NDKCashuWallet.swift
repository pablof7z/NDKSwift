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
    
    // Track deleted and superseded token event IDs to filter them out
    internal var deletedTokenEventIds: Set<String> = []
    private var supersededTokenEventIds: Set<String> = [] // Events referenced in del tags
    
    // Relay health monitoring
    internal var walletRelays: [NDKRelay] = []
    private var relayEventSets: [String: Set<String>] = [:] // relay URL -> event IDs
    
    // Unified wallet subscription
    private var walletSubscriptionTask: Task<Void, Never>?
    private var lastWalletConfigTimestamp: Timestamp = 0
    
    // MARK: - Proof State Management
    
    enum ProofState {
        case available
        case reserved   // For concurrent operations
        case deleted    // Spent proofs
    }
    
    private struct ProofEntry {
        let proof: CashuSwift.Proof
        var state: ProofState
        let mint: String
    }
    
    private var proofState: [String: ProofEntry] = [:] // proof.C -> entry
    internal var currentTokenEventIds: Set<String> = []  // Track current events
    
    /// Mint discovery service for finding mints via Nostr
    public let mintDiscovery: MintDiscovery
    
    // MARK: - Initialization
    
    public init(ndk: NDK, walletId: String? = nil, mintCache: MintCache? = nil) {
        self.ndk = ndk
        self.walletId = walletId ?? UUID().uuidString
        self.mintDiscovery = MintDiscovery(ndk: ndk)
        self.p2pkManager = P2PKManager()
        
        // Set up cached mint loader if cache is provided
        if let cache = mintCache {
            self.mintLoader = CachedMintLoader(cache: cache)
        } else {
            self.mintLoader = nil
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
                        recordEventFromRelay(event.id, from: relayUrl)
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
                if event.createdAt > lastWalletConfigTimestamp {
                    print("📝 Processing wallet configuration update")
                    extractWalletRelays(from: event)
                    lastWalletConfigTimestamp = event.createdAt
                    
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
                if deletedTokenEventIds.contains(event.id) || supersededTokenEventIds.contains(event.id) {
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
                    supersededTokenEventIds.formUnion(delIds)
                    // Remove superseded events from current set
                    for delId in delIds {
                        currentTokenEventIds.remove(delId)
                    }
                }
                
                // Add proofs to state
                for proof in nip60Token.proofs {
                    let swiftProof = proof.toCashuSwiftProof()
                    // Store proof if we have the corresponding keyset
                    if keysets[swiftProof.keysetID] != nil {
                        // Find mint for this proof
                        if let mint = try? findMintForProof(swiftProof) {
                            proofState[swiftProof.C] = ProofEntry(
                                proof: swiftProof,
                                state: .available,
                                mint: mint
                            )
                        }
                    }
                }
                
                currentTokenEventIds.insert(event.id)
                
                // Update internal proofs array
                self.proofs = proofState.values
                    .filter { $0.state == .available }
                    .map { $0.proof }
                
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
                    deletedTokenEventIds.insert(deletedEventId)
                    currentTokenEventIds.remove(deletedEventId)
                    
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
        guard ndk.signer != nil else {
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
        
        guard let finalMintURL = selectedMintURL,
              let selectedMintUrl = URL(string: finalMintURL) else {
            throw NDKError.noMintAvailable("No suitable mint found for payment")
        }
        
        // Use the send method to create P2PK locked proofs
        let (lockedProofs, _) = try await send(
            amount: nutzapRequest.amount,
            to: nutzapRequest.recipientPubkey,
            mint: selectedMintUrl
        )
        
        // Convert CashuProof to CashuSwift.Proof for the nutzap event
        let swiftProofs = lockedProofs.toCashuSwiftProofs()
        
        // Create nutzap event with the P2PK locked proofs
        let nutzapEvent = try await createNutzapEvent(
            proofs: swiftProofs,
            recipient: nutzapRequest.recipientPubkey,
            amount: nutzapRequest.amount,
            comment: nutzapRequest.comment
        )
        
        // Publish the nutzap event
        try await ndk.publish(nutzapEvent)
        
        return NDKCashuPaymentConfirmation(
            amount: nutzapRequest.amount,
            recipient: nutzapRequest.recipientPubkey,
            timestamp: Date(),
            nutzap: nutzapEvent
        )
    }
    
    public func getBalance() async throws -> Int64 {
        // Calculate from available proofs in state
        let availableProofs = proofState.values.filter { $0.state == .available }
        let balance = Int64(availableProofs.reduce(0) { $0 + $1.proof.amount })
        print("NDKCashuWallet.getBalance() - Total proofs: \(proofState.count), available: \(availableProofs.count), balance: \(balance)")
        return balance
    }
    
    public func createInvoice(amount: Int64, description: String?) async throws -> String {
        // For nutzaps, we don't create Lightning invoices
        // Instead, we return a cashu token that can be redeemed
        guard let mint = mints.values.first else {
            throw NDKError.noMintAvailable("No mint configured")
        }
        
        // Select proofs for the amount from the first available mint
        let selectedProofs = selectProofs(amount: amount, mint: mint.url.absoluteString)
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
        print("💸 Processing incoming nutzap: \(event.id)")
        
        // Check if we've already processed this nutzap
        if await hasProcessedNutzap(eventId: event.id) {
            print("⏭️ Nutzap already processed: \(event.id)")
            return
        }
        
        // Parse the nutzap content as a Cashu token
        guard let tokenData = event.content.data(using: .utf8),
              let token = try? JSONDecoder().decode(CashuSwift.Token.self, from: tokenData) else {
            throw NDKError.invalidContent("Failed to parse nutzap token")
        }
        
        // Get our P2PK private key
        let p2pkPrivateKey = try await p2pkManager.getOrCreatePrivateKey()
        
        var totalReceived: Int64 = 0
        var receivedProofs: [CashuSwift.Proof] = []
        
        // Process proofs from each mint
        for (mintURL, proofs) in token.proofsByMint {
            print("🏦 Processing \(proofs.count) proofs from mint: \(mintURL)")
            
            // Ensure we have this mint loaded
            if mints[mintURL] == nil {
                guard let url = URL(string: mintURL) else {
                    print("⚠️ Invalid mint URL: \(mintURL)")
                    continue
                }
                
                do {
                    try await addMint(url: url)
                } catch {
                    print("⚠️ Failed to load mint \(mintURL): \(error)")
                    continue
                }
            }
            
            guard let mint = mints[mintURL] else {
                continue
            }
            
            // Unlock the P2PK-locked proofs
            let unlockedProofs = try await unlockProofs(
                proofs: proofs,
                mint: mint,
                privateKey: p2pkPrivateKey
            )
            
            // Add to our wallet
            self.proofs.append(contentsOf: unlockedProofs)
            receivedProofs.append(contentsOf: unlockedProofs)
            
            // Calculate total
            let mintTotal = unlockedProofs.reduce(0) { $0 + Int64($1.amount) }
            totalReceived += mintTotal
            
            print("✅ Unlocked \(mintTotal) sats from \(unlockedProofs.count) proofs")
        }
        
        // Mark nutzap as processed
        try await markNutzapProcessed(eventId: event.id, amount: totalReceived)
        
        // Save updated wallet state
        try await save()
        
        // Create spending history for received nutzap
        if let signer = ndk.signer {
            try await createSpendingHistoryEvent(
                direction: .in,
                amount: totalReceived,
                redeemedEventId: event.id,
                signer: signer
            )
        }
        
        print("💰 Successfully received nutzap: \(totalReceived) sats total")
        
        // Emit notification (optional - could add a delegate or notification)
        await emitNutzapReceived(event: event, amount: totalReceived)
    }
    
    /// Unlock P2PK-locked proofs
    private func unlockProofs(
        proofs: [CashuSwift.Proof],
        mint: CashuSwift.Mint,
        privateKey: String
    ) async throws -> [CashuSwift.Proof] {
        // Create a token with the locked proofs
        let lockedToken = CashuSwift.Token(
            proofs: [mint.url.absoluteString: proofs],
            unit: "sat"
        )
        
        // Use CashuSwift's receive function to unlock
        let (unlockedProofs, _, _) = try await CashuSwift.receive(
            token: lockedToken,
            of: mint,
            seed: nil,
            privateKey: privateKey
        )
        
        return unlockedProofs
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
    
    /// Emit notification for received nutzap
    private func emitNutzapReceived(event: NDKEvent, amount: Int64) async {
        // This could emit a notification, call a delegate, or update UI
        // For now, just log it
        print("📨 Nutzap received notification: \(amount) sats from event \(event.id)")
    }
    
    // MARK: - Additional Methods
    
    /// Get available mints in this wallet
    public func getMints() async -> [MintInfo] {
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
        return Int64(proofState.values
            .filter { entry in
                entry.state == .available && entry.mint == mintURL.absoluteString
            }
            .reduce(0) { $0 + $1.proof.amount }
        )
    }
    
    /// Send P2PK-locked proofs to a recipient
    public func send(
        amount: Int64,
        to recipientP2PK: String,
        mint mintURL: URL
    ) async throws -> (proofs: [CashuProof], change: [CashuProof]?) {
        // Get the mint
        guard let mint = mints[mintURL.absoluteString] else {
            throw NDKError.noMintAvailable("Mint not found: \(mintURL)")
        }
        
        // Get available proofs for fee calculation
        let availableProofs = proofState.values
            .filter { $0.state == .available && $0.mint == mintURL.absoluteString }
            .map { $0.proof }
        
        // Select proofs for the amount (with some extra for fees)
        let inputFee = try CashuSwift.calculateFee(for: availableProofs, of: mint)
        let totalNeeded = amount + Int64(inputFee)
        
        let selectedProofs = selectProofs(amount: totalNeeded, mint: mintURL.absoluteString)
        guard !selectedProofs.isEmpty else {
            throw NDKError.insufficientBalance(amount: totalNeeded)
        }
        
        // Reserve proofs for this operation
        try await reserveProofs(selectedProofs)
        
        do {
            // Use CashuSwift's send function with P2PK locking
            let (token, changeProofs, _) = try await CashuSwift.send(
                inputs: selectedProofs,
                mint: mint,
                amount: Int(amount),
                seed: nil, // No deterministic derivation for P2PK locked proofs
                memo: nil,
                lockToPublicKey: recipientP2PK
            )
            
            // Extract proofs from the token
            var lockedProofs: [CashuProof] = []
            for (_, proofs) in token.proofsByMint {
                lockedProofs.append(contentsOf: proofs.toNDKProofs())
            }
            
            // Update state (this handles EVERYTHING - token event creation/deletion)
            try await update(
                deletedProofs: selectedProofs,
                addedProofs: changeProofs
            )
            
            // Convert change proofs
            let ndkChangeProofs = changeProofs.isEmpty ? nil : changeProofs.toNDKProofs()
            
            return (proofs: lockedProofs, change: ndkChangeProofs)
            
        } catch {
            // Release reservation on failure
            await releaseProofs(selectedProofs)
            throw error
        }
    }
    
    /// Pay a Lightning invoice through a mint
    public func payLightning(invoice: String, amount: Int64) async throws -> (preimage: String, feePaid: Int64?) {
        // Find a mint that can handle the payment
        guard let (mintURL, mint) = mints.first else {
            throw NDKError.noMintAvailable("No mint configured")
        }
        
        // Create melt quote request
        let quoteRequest = CashuSwift.Bolt11.RequestMeltQuote(
            unit: "sat",
            request: invoice,
            options: nil
        )
        
        // Get melt quote from mint
        let quote = try await CashuSwift.getQuote(
            mint: mint,
            quoteRequest: quoteRequest
        ) as! CashuSwift.Bolt11.MeltQuote
        
        // Get available proofs for this mint
        let availableProofs = proofState.values
            .filter { $0.state == .available && $0.mint == mintURL }
            .map { $0.proof }
        
        // Calculate total amount needed (invoice amount + fees)
        let lightningFee = Int64(quote.feeReserve)
        let inputFee = try CashuSwift.calculateFee(for: availableProofs, of: mint)
        let totalNeeded = amount + lightningFee + Int64(inputFee)
        
        // Select proofs to cover the payment
        let selectedProofs = selectProofs(amount: totalNeeded, mint: mintURL)
        guard !selectedProofs.isEmpty else {
            throw NDKError.insufficientBalance(amount: totalNeeded)
        }
        
        // Reserve proofs for this operation
        try await reserveProofs(selectedProofs)
        
        do {
            // Generate blank outputs for potential change
            let (outputs, blindingFactors, secrets) = try CashuSwift.generateBlankOutputs(
                quote: quote,
                proofs: selectedProofs,
                mint: mint,
                unit: "sat",
                seed: nil
            )
            
            let blankOutputs = (
                outputs: outputs,
                blindingFactors: blindingFactors,
                secrets: secrets
            )
            
            // Execute the melt operation
            let (paid, change, dleqValid) = try await CashuSwift.melt(
                with: quote,
                mint: mint,
                proofs: selectedProofs,
                blankOutputs: blankOutputs
            )
            
            guard paid else {
                // Payment failed, release reserved proofs
                await releaseProofs(selectedProofs)
                throw NDKError.paymentFailed(reason: "Lightning payment was not successful")
            }
            
            guard dleqValid else {
                throw NDKError.invalidProof("DLEQ verification failed")
            }
            
            // Update wallet state (removes spent proofs, adds change)
            try await update(
                deletedProofs: selectedProofs,
                addedProofs: change ?? []
            )
            
            // Calculate actual fee paid
            let totalSpent = selectedProofs.reduce(0) { $0 + Int64($1.amount) }
            let changeAmount = (change ?? []).reduce(0) { $0 + Int64($1.amount) }
            let actualFeePaid = totalSpent - amount - changeAmount
            
            // Create spending history for the Lightning payment
            if let signer = ndk.signer {
                try await createSpendingHistoryEvent(
                    direction: .out,
                    amount: amount,
                    signer: signer
                )
            }
            
            // Return preimage and fee
            // Note: CashuSwift melt doesn't return preimage directly, 
            // but payment confirmation is in the 'paid' status
            return (preimage: quote.quote, feePaid: actualFeePaid)
            
        } catch {
            // Release reservation on failure
            await releaseProofs(selectedProofs)
            throw error
        }
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
        let availableProofs = proofState.values
            .filter { $0.state == .available && $0.mint == sourceMintURL.absoluteString }
            .map { $0.proof }
        
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
        // Validate mints exist
        guard let sourceMint = mints[sourceMintURL.absoluteString] else {
            throw NDKError.invalidRequest("Source mint not found in wallet")
        }
        guard let destinationMint = mints[destinationMintURL.absoluteString] else {
            throw NDKError.invalidRequest("Destination mint not found in wallet")
        }
        
        // Step 1: Request a mint quote from destination mint
        let mintQuote = try await requestMint(
            amount: amount,
            mintURL: destinationMintURL.absoluteString,
            persistQuote: false // Don't persist intermediate quotes
        )
        
        // Step 2: Pay the Lightning invoice from source mint
        let (preimage, feePaid) = try await payLightningFromMint(
            invoice: mintQuote.invoice,
            amount: amount,
            mintURL: sourceMintURL
        )
        
        // Step 3: Claim the tokens from destination mint
        let newProofs = try await checkAndMintTokens(quote: mintQuote)
        
        // Step 4: Update wallet state with new proofs
        try await update(
            deletedProofs: [], // Already handled by payLightningFromMint
            addedProofs: newProofs
        )
        
        // Step 5: Create transfer history event
        if let signer = ndk.signer {
            try await createTransferHistoryEvent(
                amount: amount,
                fromMint: sourceMintURL.absoluteString,
                toMint: destinationMintURL.absoluteString,
                feePaid: feePaid ?? 0,
                signer: signer
            )
        }
        
        return TransferResult(
            amountTransferred: amount,
            feePaid: feePaid ?? 0,
            preimage: preimage,
            sourceMint: sourceMintURL,
            destinationMint: destinationMintURL
        )
    }
    
    /// Pay a Lightning invoice from a specific mint
    private func payLightningFromMint(
        invoice: String,
        amount: Int64,
        mintURL: URL
    ) async throws -> (preimage: String, feePaid: Int64?) {
        guard let mint = mints[mintURL.absoluteString] else {
            throw NDKError.noMintAvailable("Mint not found: \(mintURL)")
        }
        
        // Create melt quote request
        let quoteRequest = CashuSwift.Bolt11.RequestMeltQuote(
            unit: "sat",
            request: invoice,
            options: nil
        )
        
        // Get melt quote from mint
        let quote = try await CashuSwift.getQuote(
            mint: mint,
            quoteRequest: quoteRequest
        ) as! CashuSwift.Bolt11.MeltQuote
        
        // Get available proofs for this specific mint
        let availableProofs = proofState.values
            .filter { $0.state == .available && $0.mint == mintURL.absoluteString }
            .map { $0.proof }
        
        // Calculate total amount needed (invoice amount + fees)
        let lightningFee = Int64(quote.feeReserve)
        let inputFee = try CashuSwift.calculateFee(for: availableProofs, of: mint)
        let totalNeeded = amount + lightningFee + Int64(inputFee)
        
        // Select proofs to cover the payment from this specific mint
        let selectedProofs = selectProofs(amount: totalNeeded, mint: mintURL.absoluteString)
        guard !selectedProofs.isEmpty else {
            throw NDKError.insufficientBalance(amount: totalNeeded)
        }
        
        // Reserve proofs for this operation
        try await reserveProofs(selectedProofs)
        
        do {
            // Generate blank outputs for potential change
            let (outputs, blindingFactors, secrets) = try CashuSwift.generateBlankOutputs(
                quote: quote,
                proofs: selectedProofs,
                mint: mint,
                unit: "sat",
                seed: nil
            )
            
            let blankOutputs = (
                outputs: outputs,
                blindingFactors: blindingFactors,
                secrets: secrets
            )
            
            // Execute the melt operation
            let (paid, change, dleqValid) = try await CashuSwift.melt(
                with: quote,
                mint: mint,
                proofs: selectedProofs,
                blankOutputs: blankOutputs
            )
            
            guard paid else {
                // Payment failed, release reserved proofs
                await releaseProofs(selectedProofs)
                throw NDKError.paymentFailed(reason: "Lightning payment was not successful")
            }
            
            guard dleqValid else {
                throw NDKError.invalidProof("DLEQ verification failed")
            }
            
            // Update wallet state (removes spent proofs, adds change)
            try await update(
                deletedProofs: selectedProofs,
                addedProofs: change ?? []
            )
            
            // Calculate actual fee paid
            let totalSpent = selectedProofs.reduce(0) { $0 + Int64($1.amount) }
            let changeAmount = (change ?? []).reduce(0) { $0 + Int64($1.amount) }
            let actualFeePaid = totalSpent - amount - changeAmount
            
            return (preimage: quote.quote, feePaid: actualFeePaid)
            
        } catch {
            // Release reservation on failure
            await releaseProofs(selectedProofs)
            throw error
        }
    }
    
    /// Check proof states with all mints and reconcile wallet state
    /// This queries each mint for the status of our proofs and updates our local state accordingly
    public func checkAndReconcileProofStates() async throws {
        guard let signer = ndk.signer else {
            throw NDKError.notConfigured("No signer configured")
        }
        
        print("🔍 Starting proof state reconciliation...")
        
        // Group proofs by mint for efficient checking
        var proofsByMint: [String: [(proof: CashuSwift.Proof, entryKey: String)]] = [:]
        
        for (key, entry) in proofState where entry.state == .available {
            if proofsByMint[entry.mint] == nil {
                proofsByMint[entry.mint] = []
            }
            proofsByMint[entry.mint]?.append((proof: entry.proof, entryKey: key))
        }
        
        // Track spent proofs we discover
        var spentProofs: [CashuSwift.Proof] = []
        var spentProofsByMint: [String: [CashuSwift.Proof]] = [:]
        
        // Check each mint
        for (mintURL, proofEntries) in proofsByMint {
            guard let mint = mints[mintURL] else {
                print("⚠️ Mint not found for URL: \(mintURL)")
                continue
            }
            
            let proofs = proofEntries.map { $0.proof }
            
            do {
                print("🏦 Checking \(proofs.count) proofs with mint: \(mintURL)")
                
                // Query mint for proof states
                let states = try await CashuSwift.check(proofs, mint: mint)
                
                // Process results
                for (index, state) in states.enumerated() {
                    let proofEntry = proofEntries[index]
                    
                    switch state {
                    case .spent:
                        print("💸 Found spent proof: \(proofEntry.proof.C.suffix(8))")
                        spentProofs.append(proofEntry.proof)
                        if spentProofsByMint[mintURL] == nil {
                            spentProofsByMint[mintURL] = []
                        }
                        spentProofsByMint[mintURL]?.append(proofEntry.proof)
                        
                    case .pending:
                        print("⏳ Found pending proof: \(proofEntry.proof.C.suffix(8))")
                        // For now, treat pending as still available
                        // Could enhance to track pending state separately
                        
                    case .unspent:
                        // Proof is still good, no action needed
                        break
                    }
                }
                
            } catch {
                print("❌ Failed to check proofs with mint \(mintURL): \(error)")
                // Continue with other mints even if one fails
            }
        }
        
        // If we found spent proofs, update our state
        if !spentProofs.isEmpty {
            print("🔄 Found \(spentProofs.count) spent proofs, updating wallet state...")
            
            // For each mint with spent proofs, handle the rollover
            for (mintURL, mintSpentProofs) in spentProofsByMint {
                // Find the token events containing these spent proofs
                let affectedEventIds = try await findTokenEventsContainingProofs(
                    proofs: mintSpentProofs,
                    signer: signer
                )
                
                if !affectedEventIds.isEmpty {
                    print("📝 Affected token events: \(affectedEventIds)")
                    
                    // Get all proofs from affected events
                    let allProofsFromEvents = try await getProofsFromTokenEvents(
                        eventIds: affectedEventIds,
                        signer: signer
                    )
                    
                    // Determine which proofs are still unspent
                    let spentProofCs = Set(mintSpentProofs.map { $0.C })
                    let unspentProofs = allProofsFromEvents.filter { !spentProofCs.contains($0.C) }
                    
                    // Update state: remove spent proofs, keep unspent ones
                    try await update(
                        deletedProofs: mintSpentProofs,
                        addedProofs: [] // Unspent proofs are already in state
                    )
                    
                    print("✅ State updated: removed \(mintSpentProofs.count) spent proofs")
                }
            }
            
            // Create spending history event for reconciliation
            try await createSpendingHistoryEvent(
                direction: .out,
                amount: Int64(spentProofs.reduce(0) { $0 + $1.amount }),
                signer: signer
            )
        } else {
            print("✅ All proofs are unspent, no reconciliation needed")
        }
    }
    
    /// Find token events that contain specific proofs
    private func findTokenEventsContainingProofs(
        proofs: [CashuSwift.Proof],
        signer: NDKSigner
    ) async throws -> [String] {
        let proofCs = Set(proofs.map { $0.C })
        var matchingEventIds: [String] = []
        
        // Check current token events
        for eventId in currentTokenEventIds {
            // We need to decrypt and check each event
            // This is why we track currentTokenEventIds
            matchingEventIds.append(eventId)
        }
        
        return matchingEventIds
    }
    
    /// Get all proofs from specific token events
    private func getProofsFromTokenEvents(
        eventIds: [String],
        signer: NDKSigner
    ) async throws -> [CashuSwift.Proof] {
        var allProofs: [CashuSwift.Proof] = []
        
        // Get proofs from our current state
        for entry in proofState.values {
            allProofs.append(entry.proof)
        }
        
        return allProofs
    }
    
    /// Check proof states for a specific mint
    public func checkProofStates(mintURL: URL) async throws -> [String: CashuSwift.Proof.ProofState] {
        guard let mint = mints[mintURL.absoluteString] else {
            throw NDKError.noMintAvailable("Mint not found: \(mintURL)")
        }
        
        // Get all proofs for this mint
        let mintProofs = proofState.values
            .filter { $0.state == .available && $0.mint == mintURL.absoluteString }
            .map { $0.proof }
        
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
            try await saveQuoteEvent(quote: quote)
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
                                try await self.deleteQuoteEvent(quoteId: quote.quoteId)
                                
                                // Update wallet state properly with the new proofs
                                let createdEventIds = try await self.update(
                                    deletedProofs: [],
                                    addedProofs: proofs
                                )
                                
                                // Create history event for the lightning deposit
                                if let signer = self.ndk.signer {
                                    Task {
                                        do {
                                            try await self.createSpendingHistoryEvent(
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
                                
                                continuation.yield(.minted(proofs: proofs.toNDKProofs()))
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
                    try await self.saveQuoteEvent(quote: quote)
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
    
    /// Save quote event (kind 7374)
    private func saveQuoteEvent(quote: CashuMintQuote) async throws {
        guard let signer = ndk.signer else {
            throw NDKError.notConfigured("No signer configured")
        }
        
        // According to NIP-60: encrypt only the quote ID
        let signerPubkey = try await signer.pubkey
        let recipient = NDKUser(pubkey: signerPubkey)
        print("🔐 [NDKCashuWallet] Encrypting quote ID: '\(quote.quoteId)'")
        let encryptedContent = try await signer.encrypt(
            recipient: recipient,
            value: quote.quoteId,
            scheme: .nip44
        )
        print("🔐 [NDKCashuWallet] Encrypted result: '\(encryptedContent)'")
        
        // Calculate expiration (2 weeks as per NIP-60)
        let expirationTimestamp = Int(Date().addingTimeInterval(14 * 24 * 60 * 60).timeIntervalSince1970)
        
        // Create quote event (kind 7374) - following NIP-60 exactly
        let quoteEvent = try await NDKEventBuilder()
            .content(encryptedContent)
            .kind(7374)
            .tags([
                ["expiration", String(expirationTimestamp)],
                ["mint", quote.mintURL]  // As per NIP-60, mint URL is in clear
            ])
            .build(signer: signer)
        
        try await ndk.publish(quoteEvent, logRawJSON: true)
    }
    
    /// Delete quote event when payment is complete or cancelled
    private func deleteQuoteEvent(quoteId: String) async throws {
        guard let signer = ndk.signer else {
            throw NDKError.notConfigured("No signer configured")
        }
        
        // Find the quote event
        let filter = NDKFilter(
            authors: [try await signer.pubkey],
            kinds: [7374]
        )
        
        let events = try await ndk.fetchEvents(filter)
        
        // Find the event with matching quote ID by decrypting content
        let sender = NDKUser(pubkey: try await signer.pubkey)
        for event in events {
            do {
                print("🔓 [NDKCashuWallet] Decrypting quote event content: '\(event.content)'")
                let decryptedQuoteId = try await signer.decrypt(
                    sender: sender,
                    value: event.content,
                    scheme: .nip44
                )
                print("🔓 [NDKCashuWallet] Decrypted quote ID: '\(decryptedQuoteId)'")
                
                if decryptedQuoteId == quoteId {
                    // Create delete event
                    try await createDeleteEvent(eventId: event.id, signer: signer)
                    return
                }
            } catch {
                // Skip events we can't decrypt
                continue
            }
        }
    }
    
    /// Initialize wallet by subscribing to wallet events
    public func load() async throws {
        guard let signer = ndk.signer else {
            throw NDKError.notConfigured("No signer configured for NDKCashuWallet")
        }
        
        // Clear state before starting
        proofState.removeAll()
        currentTokenEventIds.removeAll()
        deletedTokenEventIds.removeAll()
        supersededTokenEventIds.removeAll()
        
        // Start the subscription - this will load all events including historical ones
        await startWalletSubscription()
    }
    
    
    /// Check if a token event should be filtered out
    private func shouldFilterTokenEvent(eventId: String) -> Bool {
        return deletedTokenEventIds.contains(eventId) || supersededTokenEventIds.contains(eventId)
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
        
        // Only save wallet configuration event
        // Token events are now managed by the update() method
        try await saveWalletEvent(signer: signer)
    }
    
    /// Save wallet state to NIP-60 events with specific relays
    /// If relays is nil, falls back to user's outbox write relays
    public func save(relays: [String]?) async throws {
        guard let signer = ndk.signer else {
            throw NDKError.notConfigured("No signer configured for NDKCashuWallet")
        }
        
        // Only save wallet configuration event
        // Token events are now managed by the update() method
        try await saveWalletEvent(signer: signer, relays: relays)
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
    
    /// Save wallet configuration event (kind 17375)
    private func saveWalletEvent(signer: NDKSigner, relays: [String]? = nil) async throws {
        print("🔍 Preparing wallet event...")
        print("   Mints in wallet: \(mints.count)")
        
        // Create wallet configuration tags
        var walletTags: [[String]] = []
        
        // Add P2PK private key (get from manager)
        let (p2pkPrivateKey, _) = try await p2pkManager.getOrCreateKeypair()
        walletTags.append(["privkey", p2pkPrivateKey])
        print("   Added privkey tag")
        
        // Add mint URLs
        for mintURL in mints.keys {
            walletTags.append(["mint", mintURL])
            print("   Added mint tag: \(mintURL)")
        }
        
        // If no mints, add a default mint
        if mints.isEmpty {
            walletTags.append(["mint", "https://testnut.cashu.space"])
            print("   Added default mint: https://testnut.cashu.space")
        }
        
        // Encrypt the wallet configuration
        let walletDataJSON = try JSONEncoder().encode(walletTags)
        guard let plaintext = String(data: walletDataJSON, encoding: .utf8) else {
            throw NDKError.encodingError("Failed to encode wallet data")
        }
        
        let signerPubkey = try await signer.pubkey
        let recipient = NDKUser(pubkey: signerPubkey)
        print("🔐 [NDKCashuWallet] Encrypting wallet data: '\(plaintext)'")
        let encryptedContent = try await signer.encrypt(
            recipient: recipient, 
            value: plaintext, 
            scheme: .nip44
        )
        print("🔐 [NDKCashuWallet] Encrypted wallet result: '\(encryptedContent)'")
        
        // Get relay tags for the wallet event
        let relayTags = try await getRelayTags(providedRelays: relays, signer: signer)
        
        // Create wallet event (kind 17375) - replaceable by kind
        let walletEvent = try await NDKEventBuilder()
            .content(encryptedContent)
            .kind(17375)
            .tags(relayTags)
            .build(signer: signer)
        
        // Log event ID
        print("📝 Wallet event ID: \(walletEvent.id)")
        
        // Extract relay tags from the wallet event before publishing
        extractWalletRelays(from: walletEvent)
        
        let publishedRelays = try await ndk.publish(walletEvent, logRawJSON: true)
        print("📡 Published to \(publishedRelays.count) relays")
    }
    
    
    /// Save individual token event
    internal func saveTokenEvent(token: CashuSwift.Token, signer: NDKSigner, deletedEventIds: [String]? = nil) async throws -> String {
        // Extract mint URL from token
        guard let mintURL = token.proofsByMint.keys.first else {
            throw NDKError.invalidRequest("Token has no mint URL")
        }
        
        // Convert CashuSwift.Token proofs to our CashuProof format
        let proofs = token.proofsByMint[mintURL]?.toNDKProofs() ?? []
        
        // Create NIP-60 compliant token event structure
        let nip60Token = NIP60TokenEvent(
            mint: mintURL,
            proofs: proofs,
            del: deletedEventIds
        )
        
        // Encode token to JSON
        let tokenData = try JSONEncoder().encode(nip60Token)
        guard let plaintext = String(data: tokenData, encoding: .utf8) else {
            throw NDKError.encodingError("Failed to encode token data")
        }
        
        let signerPubkey = try await signer.pubkey
        let recipient = NDKUser(pubkey: signerPubkey)
        print("🔐 [NDKCashuWallet] Encrypting token data: '\(plaintext)'")
        let encryptedContent = try await signer.encrypt(
            recipient: recipient,
            value: plaintext,
            scheme: .nip44
        )
        print("🔐 [NDKCashuWallet] Encrypted token result: '\(encryptedContent)'")
        
        // Create token event (kind 7375) - no relay tags for token events
        let tokenEvent = try await NDKEventBuilder()
            .content(encryptedContent)
            .kind(7375)
            .build(signer: signer)
        
        let publishedRelays = try await ndk.publish(tokenEvent, logRawJSON: true)
        print("NDKCashuWallet.saveTokenEvent() - Published token event \(tokenEvent.id) to \(publishedRelays.count) relays")
        
        return tokenEvent.id
    }
    
    /// Get relay tags for wallet events according to NIP-60 PR #1839
    /// If no relays provided, use outbox write relays; if no outbox relays, return empty array
    private func getRelayTags(providedRelays: [String]?, signer: NDKSigner) async throws -> [[String]] {
        var relayTags: [[String]] = []
        
        if let relays = providedRelays {
            // Use provided relays
            for relay in relays {
                relayTags.append(["relay", relay])
            }
            print("   Added \(relays.count) provided relay tags")
        } else {
            // Fallback to user's outbox write relays from NIP-65
            do {
                let userPubkey = try await signer.pubkey
                let user = ndk.getUser(userPubkey)
                
                // Use the NDKUser method that returns [NDKRelayInfo] (not NDKRelayList)
                let relayInfoList: [NDKRelayInfo] = try await user.fetchRelayList()
                let writeRelays = relayInfoList.filter { $0.write }
                
                for relay in writeRelays {
                    relayTags.append(["relay", relay.url])
                }
                
                if !writeRelays.isEmpty {
                    print("   Added \(writeRelays.count) outbox write relay tags")
                } else {
                    print("   No outbox write relays configured, no relay tags added")
                }
            } catch {
                print("   Failed to fetch outbox relays: \(error), no relay tags added")
            }
        }
        
        return relayTags
    }
    
    // MARK: - Relay Health Monitoring
    
    /// Get current relay health from existing monitoring data
    public func getRelayHealth() async -> [RelayHealth] {
        guard !walletRelays.isEmpty else { return [] }
        
        // Calculate the canonical event set (what healthy relays should have)
        let canonicalEvents = calculateCanonicalEventSet()
        
        return walletRelays.map { relay in
            let knownEvents = relayEventSets[relay.url] ?? Set()
            let missing = canonicalEvents.subtracting(knownEvents)
            let extra = knownEvents.intersection(deletedTokenEventIds)
            
            return RelayHealth(
                relay: relay,
                knownEvents: knownEvents.count,
                missingEvents: Array(missing),
                extraEvents: Array(extra),
                isHealthy: missing.isEmpty && extra.isEmpty
            )
        }
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
        return events.filter { !deletedTokenEventIds.contains($0.id) }
    }
    
    private func calculateCanonicalEventSet() -> Set<String> {
        // Current wallet state = what we have locally that's not deleted
        return currentTokenEventIds.subtracting(deletedTokenEventIds)
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
    
    
    internal func recordEventFromRelay(_ eventId: String, from relayUrl: String) {
        relayEventSets[relayUrl, default: Set()].insert(eventId)
    }
    
    private func markEventDeleted(_ eventId: String) {
        deletedTokenEventIds.insert(eventId)
        // Remove from all relay tracking since it should no longer exist
        for relayUrl in relayEventSets.keys {
            relayEventSets[relayUrl]?.remove(eventId)
        }
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
    private func update(
        deletedProofs: [CashuSwift.Proof],
        addedProofs: [CashuSwift.Proof]
    ) async throws -> [String] {
        print("NDKCashuWallet.update() - Adding \(addedProofs.count) proofs, deleting \(deletedProofs.count) proofs")
        
        // 1. Update proof states
        for proof in deletedProofs {
            if var entry = proofState[proof.C] {
                entry.state = .deleted
                proofState[proof.C] = entry
            }
        }
        
        for proof in addedProofs {
            let mint = try findMintForProof(proof)
            proofState[proof.C] = ProofEntry(
                proof: proof,
                state: .available,
                mint: mint
            )
            print("  Added proof: amount=\(proof.amount), C=\(proof.C)")
        }
        
        // 2. Group available proofs by mint
        var availableByMint: [String: [CashuSwift.Proof]] = [:]
        for entry in proofState.values where entry.state == .available {
            availableByMint[entry.mint, default: []].append(entry.proof)
        }
        
        // 3. Create new token events for each mint
        var newEventIds: Set<String> = []
        for (mint, proofs) in availableByMint {
            let token = CashuSwift.Token(
                proofs: [mint: proofs],
                unit: "sat"
            )
            
            let eventId = try await saveTokenEvent(
                token: token,
                signer: ndk.signer!,
                deletedEventIds: nil
            )
            newEventIds.insert(eventId)
            print("NDKCashuWallet.update() - Saved token event: \(eventId) for mint: \(mint)")
        }
        
        // 4. Delete old token events
        let eventsToDelete = currentTokenEventIds.subtracting(newEventIds)
        for eventId in eventsToDelete {
            try await createDeleteEvent(eventId: eventId, signer: ndk.signer!)
        }
        
        // 5. Update tracking
        currentTokenEventIds = newEventIds
        
        // 6. Update internal proofs array for compatibility
        self.proofs = availableByMint.values.flatMap { $0 }
        
        // Return the newly created event IDs
        return Array(newEventIds)
    }
    
    /// Reserve proofs for concurrent operations
    private func reserveProofs(_ proofs: [CashuSwift.Proof]) async throws {
        for proof in proofs {
            guard var entry = proofState[proof.C], entry.state == .available else {
                throw NDKError.invalidProof("Proof not available for reservation: \(proof.C)")
            }
            entry.state = .reserved
            proofState[proof.C] = entry
        }
    }
    
    /// Release reserved proofs back to available
    private func releaseProofs(_ proofs: [CashuSwift.Proof]) async {
        for proof in proofs {
            if var entry = proofState[proof.C], entry.state == .reserved {
                entry.state = .available
                proofState[proof.C] = entry
            }
        }
    }
    
    /// Find mint URL for a proof based on its keyset ID
    private func findMintForProof(_ proof: CashuSwift.Proof) throws -> String {
        for (mintUrl, mint) in mints {
            if mint.keysets.contains(where: { $0.keysetID == proof.keysetID }) {
                return mintUrl
            }
        }
        throw NDKError.invalidProof("Proof with unknown keyset: \(proof.keysetID)")
    }
    
    // MARK: - Private Helper Methods
    
    /// Split amount into base 2 numbers
    private func splitIntoBase2(_ n: Int) -> [Int] {
        return (0 ..< Int.bitWidth - n.leadingZeroBitCount)
            .map { 1 << $0 }
            .filter { $0 & n > 0 }
    }
    
    
    /// Select proofs for a given amount from a specific mint
    private func selectProofs(amount: Int64, mint: String) -> [CashuSwift.Proof] {
        var selected: [CashuSwift.Proof] = []
        var total: Int64 = 0
        
        // Get available proofs from state, filtered by mint
        let availableProofs = proofState.values
            .filter { $0.state == .available && $0.mint == mint }
            .map { $0.proof }
        
        // Sort proofs by amount (ascending) to minimize change
        let sortedProofs = availableProofs.sorted { $0.amount < $1.amount }
        
        for proof in sortedProofs {
            if total >= amount {
                break
            }
            selected.append(proof)
            total += Int64(proof.amount)
        }
        
        return total >= amount ? selected : []
    }
    
    
    /// Create a delete event for a spent token event (NIP-09)
    private func createDeleteEvent(eventId: String, signer: NDKSigner) async throws {
        // Add to our deleted set immediately
        deletedTokenEventIds.insert(eventId)
        
        let deleteEvent = try await NDKEventBuilder()
            .content("Spent")
            .kind(5) // Delete event kind
            .tags([
                ["e", eventId],
                ["k", "7375"] // Deleting token events
            ])
            .build(signer: signer)
        
        try await ndk.publish(deleteEvent)
    }
    
    /// Create spending history event (kind 7376)
    private func createSpendingHistoryEvent(
        direction: SpendingDirection,
        amount: Int64,
        destroyedEventIds: [String]? = nil,
        createdEventIds: [String]? = nil,
        redeemedEventId: String? = nil,
        signer: NDKSigner
    ) async throws {
        // Build encrypted tags
        var encryptedTags: [[String]] = []
        encryptedTags.append(["direction", direction.rawValue])
        encryptedTags.append(["amount", String(amount)])
        
        // Add encrypted event references
        if let createdIds = createdEventIds {
            for eventId in createdIds {
                encryptedTags.append(["e", eventId, "", "created"])
            }
        }
        
        if let destroyedIds = destroyedEventIds {
            for eventId in destroyedIds {
                encryptedTags.append(["e", eventId, "", "destroyed"])
            }
        }
        
        // Build clear tags (unencrypted)
        var clearTags: [[String]] = []
        
        // Redeemed tags should be unencrypted according to NIP-60
        if let redeemedId = redeemedEventId {
            clearTags.append(["e", redeemedId, "", "redeemed"])
        }
        
        // Encrypt the content tags
        let tagsData = try JSONEncoder().encode(encryptedTags)
        guard let plaintext = String(data: tagsData, encoding: .utf8) else {
            throw NDKError.encodingError("Failed to encode spending history tags")
        }
        
        let signerPubkey = try await signer.pubkey
        let recipient = NDKUser(pubkey: signerPubkey)
        let encryptedContent = try await signer.encrypt(
            recipient: recipient,
            value: plaintext,
            scheme: .nip44
        )
        
        // Create spending history event
        let historyEvent = try await NDKEventBuilder()
            .content(encryptedContent)
            .kind(7376)
            .tags(clearTags)
            .build(signer: signer)
        
        try await ndk.publish(historyEvent)
    }
    
    /// Spending direction for history events
    private enum SpendingDirection: String {
        case `in` = "in"   // Received funds
        case out = "out"   // Sent funds
    }
    
    /// Create nutzap event
    private func createNutzapEvent(
        proofs: [CashuSwift.Proof],
        recipient: PublicKey,
        amount: Int64,
        comment: String?
    ) async throws -> NDKEvent {
        guard let signer = ndk.signer else {
            throw NDKError.notConfigured("No signer configured")
        }
        
        // Create token for the proofs
        let token = CashuSwift.Token(
            proofs: Dictionary(grouping: proofs) { proof in
                // Find mint URL for this proof
                for (mintURL, mint) in mints {
                    if mint.keysets.contains(where: { $0.keysetID == proof.keysetID }) {
                        return mintURL
                    }
                }
                return ""
            }.filter { !$0.key.isEmpty },
            unit: "sat",
            memo: comment
        )
        
        // Serialize token
        let tokenData = try JSONEncoder().encode(token)
        guard let tokenString = String(data: tokenData, encoding: .utf8) else {
            throw NDKError.encodingError("Failed to encode token")
        }
        
        // Create nutzap event (kind 9321)
        let eventBuilder = NDKEventBuilder()
            .content(tokenString)
            .kind(EventKind.nutzap)
            .tagUser(recipient)
            .tag(["amount", String(amount)])
        
        if let comment = comment {
            _ = eventBuilder.tag(["comment", comment])
        }
        
        let nutzapEvent = try await eventBuilder.build(signer: signer)
        
        return nutzapEvent
    }
    
    // MARK: - Public Types
    
    /// Relay health information for wallet state monitoring
    public struct RelayHealth: Sendable {
        public let relay: NDKRelay
        public let knownEvents: Int
        public let missingEvents: [String]
        public let extraEvents: [String]  // Events that were deleted but relay still has
        public let isHealthy: Bool
        
        public init(relay: NDKRelay, knownEvents: Int, missingEvents: [String], extraEvents: [String], isHealthy: Bool) {
            self.relay = relay
            self.knownEvents = knownEvents
            self.missingEvents = missingEvents
            self.extraEvents = extraEvents
            self.isHealthy = isHealthy
        }
    }
    
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
    case minted(proofs: [CashuProof])  // Tokens successfully minted after deposit
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