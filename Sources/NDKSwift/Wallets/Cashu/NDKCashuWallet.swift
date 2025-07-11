import Foundation
import CashuSwift
import secp256k1

/// NIP-60 Cashu wallet implementation
public actor NDKCashuWallet: NDKWallet {
    // MARK: - Properties
    
    private let ndk: NDK
    public let walletId: String // For API compatibility, but not used in NIP-60
    private var proofs: [CashuSwift.Proof] = []
    private var mints: [String: CashuSwift.Mint] = [:] // URL string to Mint
    private var keysets: [String: CashuSwift.Keyset] = [:] // Keyset ID to Keyset
    private let p2pkManager: P2PKManager // Manages P2PK keys for receiving nutzaps
    
    // Track deleted and superseded token event IDs to filter them out
    private var deletedTokenEventIds: Set<String> = []
    private var supersededTokenEventIds: Set<String> = [] // Events referenced in del tags
    
    /// Mint discovery service for finding mints via Nostr
    public let mintDiscovery: MintDiscovery
    
    // MARK: - Initialization
    
    public init(ndk: NDK, walletId: String? = nil) {
        self.ndk = ndk
        self.walletId = walletId ?? UUID().uuidString
        self.mintDiscovery = MintDiscovery(ndk: ndk)
        self.p2pkManager = P2PKManager()
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
        
        guard let selectedMintURL = commonMintURLs.first else {
            throw NDKError.noMintAvailable("No common mint found between wallet and recipient")
        }
        
        guard let selectedMintUrl = URL(string: selectedMintURL) else {
            throw NDKError.invalidRequest("Invalid mint URL")
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
        return Int64(proofs.reduce(0) { $0 + $1.amount })
    }
    
    public func createInvoice(amount: Int64, description: String?) async throws -> String {
        // For nutzaps, we don't create Lightning invoices
        // Instead, we return a cashu token that can be redeemed
        guard let mint = mints.values.first else {
            throw NDKError.noMintAvailable("No mint configured")
        }
        
        // Select proofs for the amount
        let selectedProofs = selectProofs(amount: amount)
        guard !selectedProofs.isEmpty else {
            throw NDKError.insufficientBalance(amount: amount)
        }
        
        // Create a token
        let token = CashuSwift.Token(
            proofs: [mint.url.absoluteString: selectedProofs],
            unit: "sat",
            memo: description
        )
        
        // Remove the proofs from wallet as they're now in the token
        removeProofs(selectedProofs)
        
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
            return false // We only support nutzaps for now
        case .nwc:
            return false // We don't support NWC
        }
    }
    
    // MARK: - Nutzap Receiving
    
    /// Start monitoring for incoming nutzaps
    public func startNutzapMonitor() async {
        guard let signer = ndk.signer else {
            print("❌ Cannot start nutzap monitor: No signer configured")
            return
        }
        
        do {
            let userPubkey = try await signer.pubkey
            
            // Start monitoring for delete events in parallel
            Task {
                await startDeleteEventMonitor()
            }
            
            let filter = NDKFilter(
                kinds: [EventKind.nutzap],
                tags: ["p": Set([userPubkey])]
            )
            
            print("👀 Starting nutzap monitor for pubkey: \(userPubkey)")
            
            // Subscribe to nutzap events
            do {
                for try await event in ndk.subscribe(filters: [filter]) {
                    Task {
                        do {
                            try await processIncomingNutzap(event)
                        } catch {
                            print("❌ Failed to process nutzap \(event.id): \(error)")
                        }
                    }
                }
            } catch {
                print("❌ Subscription error: \(error)")
            }
        } catch {
            print("❌ Failed to start nutzap monitor: \(error)")
        }
    }
    
    /// Start monitoring for delete events affecting our token events
    private func startDeleteEventMonitor() async {
        guard let signer = ndk.signer else { return }
        
        do {
            let userPubkey = try await signer.pubkey
            let filter = NDKFilter(
                authors: [userPubkey],
                kinds: [5], // Delete events
                tags: ["k": Set(["7375"])] // Specifically for token events
            )
            
            print("🗑️ Starting delete event monitor")
            
            for try await event in ndk.subscribe(filters: [filter]) {
                // Extract deleted event IDs and add to our set
                for tag in event.tags where tag.count >= 2 && tag[0] == "e" {
                    let deletedEventId = tag[1]
                    deletedTokenEventIds.insert(deletedEventId)
                    print("🗑️ Added deleted token event to filter: \(deletedEventId)")
                }
            }
        } catch {
            print("❌ Failed to monitor delete events: \(error)")
        }
    }
    
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
    
    /// Get balance for a specific mint
    public func getBalance(mint mintURL: URL) async -> Int64 {
        let mintProofs = proofs.filter { proof in
            // Check if proof belongs to this mint by matching keyset
            if let keyset = keysets[proof.keysetID] {
                return mints[mintURL.absoluteString]?.keysets.contains(where: { $0.keysetID == keyset.keysetID }) ?? false
            }
            return false
        }
        return Int64(mintProofs.reduce(0) { $0 + $1.amount })
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
        
        // Select proofs for the amount (with some extra for fees)
        let inputFee = try CashuSwift.calculateFee(for: proofs, of: mint)
        let totalNeeded = amount + Int64(inputFee)
        
        let selectedProofs = selectProofs(amount: totalNeeded)
        guard !selectedProofs.isEmpty else {
            throw NDKError.insufficientBalance(amount: totalNeeded)
        }
        
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
        
        // Update our proof list
        removeProofs(selectedProofs)
        if !changeProofs.isEmpty {
            self.proofs.append(contentsOf: changeProofs)
        }
        
        // Convert change proofs
        let ndkChangeProofs = changeProofs.isEmpty ? nil : changeProofs.toNDKProofs()
        
        return (proofs: lockedProofs, change: ndkChangeProofs)
    }
    
    /// Pay a Lightning invoice through a mint
    public func payLightning(invoice: String, amount: Int64) async throws -> (preimage: String, feePaid: Int64?) {
        // This would require the melt functionality from CashuSwift
        // For now, we don't support Lightning payments
        throw NDKError.notImplemented("Lightning payments not yet supported")
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
                                
                                // Add proofs to wallet
                                self.proofs.append(contentsOf: proofs)
                                
                                // Save wallet state
                                try await self.save()
                                
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
    
    /// Load wallet state from NIP-60 events
    public func load() async throws {
        guard let signer = ndk.signer else {
            throw NDKError.notConfigured("No signer configured for NDKCashuWallet")
        }
        
        try await loadWalletEvent(signer: signer)
        try await loadTokenEvents(signer: signer)
    }
    
    /// Load wallet configuration from kind 17375 event
    private func loadWalletEvent(signer: NDKSigner) async throws {
        let filter = NDKFilter(
            authors: [try await signer.pubkey],
            kinds: [17375] // NIP-60 wallet event kind - replaceable by kind
        )
        
        let events = try await ndk.fetchEvents(filter)
        guard let latestEvent = events.first else {
            return // No wallet data found
        }
        
        // Decrypt wallet configuration
        let sender = NDKUser(pubkey: try await signer.pubkey)
        print("🔓 [NDKCashuWallet] Decrypting wallet event content: '\(latestEvent.content)'")
        let decryptedContent = try await signer.decrypt(
            sender: sender,
            value: latestEvent.content,
            scheme: .nip44
        )
        print("🔓 [NDKCashuWallet] Decrypted wallet content: '\(decryptedContent)'")
        
        // Parse wallet configuration tags
        guard let walletData = decryptedContent.data(using: String.Encoding.utf8),
              let walletTags = try? JSONDecoder().decode([[String]].self, from: walletData) else {
            throw NDKError.invalidContent("Failed to parse wallet configuration")
        }
        
        // Process wallet tags
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
                    Task {
                        try? await p2pkManager.setKeypair(privateKey: privateKey, publicKey: publicKey)
                    }
                }
                break
                
            case "mint":
                let mintURLString = tag[1]
                guard let mintURL = URL(string: mintURLString) else { continue }
                
                do {
                    let mint = try await CashuSwift.loadMint(url: mintURL)
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
    
    /// Load token events containing encrypted proofs
    private func loadTokenEvents(signer: NDKSigner) async throws {
        let signerPubkey = try await signer.pubkey
        
        // First, fetch all delete events to know which token events are deleted
        let deleteFilter = NDKFilter(
            authors: [signerPubkey],
            kinds: [5], // Delete events
            tags: ["k": Set(["7375"])] // Specifically for token events
        )
        
        let deleteEvents = try await ndk.fetchEvents(deleteFilter)
        
        // Extract deleted event IDs and add to our persistent set
        for deleteEvent in deleteEvents {
            for tag in deleteEvent.tags where tag.count >= 2 && tag[0] == "e" {
                deletedTokenEventIds.insert(tag[1])
            }
        }
        
        // Now fetch token events
        let filter = NDKFilter(
            authors: [signerPubkey],
            kinds: [7375] // NIP-60 token event kind
        )
        
        let events = try await ndk.fetchEvents(filter)
        
        // First pass: identify events referenced in del tags
        for event in events {
            // Skip if this event has been deleted
            if deletedTokenEventIds.contains(event.id) {
                continue
            }
            
            do {
                // Decrypt and parse to check del field
                let sender = NDKUser(pubkey: signerPubkey)
                let decryptedContent = try await signer.decrypt(
                    sender: sender,
                    value: event.content,
                    scheme: .nip44
                )
                
                if let tokenData = decryptedContent.data(using: .utf8),
                   let nip60Token = try? JSONDecoder().decode(NIP60TokenEvent.self, from: tokenData),
                   let delIds = nip60Token.del {
                    // Add to our persistent set of superseded events
                    supersededTokenEventIds.formUnion(delIds)
                }
            } catch {
                // Skip events we can't decrypt or parse
                continue
            }
        }
        
        // Second pass: load only valid events
        for event in events {
            // Skip if this event has been deleted or is referenced in a del tag
            if deletedTokenEventIds.contains(event.id) || supersededTokenEventIds.contains(event.id) {
                print("⏭️ Skipping deleted or superseded token event: \(event.id)")
                continue
            }
            
            do {
                try await loadTokenEvent(event: event, signer: signer)
            } catch {
                print("Failed to load token event \(event.id): \(error)")
            }
        }
    }
    
    /// Load individual token event and extract proofs
    private func loadTokenEvent(event: NDKEvent, signer: NDKSigner) async throws {
        // Check if this event should be filtered out
        if shouldFilterTokenEvent(eventId: event.id) {
            print("⏭️ Filtering out deleted or superseded token event: \(event.id)")
            return
        }
        
        // Decrypt token event content
        let sender = NDKUser(pubkey: try await signer.pubkey)
        print("🔓 [NDKCashuWallet] Decrypting token event content: '\(event.content)'")
        let decryptedContent = try await signer.decrypt(
            sender: sender,
            value: event.content,
            scheme: .nip44
        )
        print("🔓 [NDKCashuWallet] Decrypted token content: '\(decryptedContent)'")
        
        // Parse token data as NIP60TokenEvent
        guard let tokenData = decryptedContent.data(using: .utf8),
              let nip60Token = try? JSONDecoder().decode(NIP60TokenEvent.self, from: tokenData) else {
            throw NDKError.invalidContent("Failed to parse NIP-60 token event data")
        }
        
        // Update our superseded events set if this event has del tags
        if let delIds = nip60Token.del {
            supersededTokenEventIds.formUnion(delIds)
        }
        
        // Convert CashuProof to CashuSwift.Proof
        for proof in nip60Token.proofs {
            let swiftProof = proof.toCashuSwiftProof()
            // Store proof if we have the corresponding keyset
            if keysets[swiftProof.keysetID] != nil {
                proofs.append(swiftProof)
            }
        }
    }
    
    /// Check if a token event should be filtered out
    private func shouldFilterTokenEvent(eventId: String) -> Bool {
        return deletedTokenEventIds.contains(eventId) || supersededTokenEventIds.contains(eventId)
    }
    
    /// Add mint to wallet
    public func addMint(url: URL) async throws {
        let mint = try await CashuSwift.loadMint(url: url)
        mints[url.absoluteString] = mint
        
        // Store keysets
        for keyset in mint.keysets {
            keysets[keyset.keysetID] = keyset
        }
        
        // Save updated wallet configuration
        try await save()
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
        
        // Add proofs to wallet
        proofs.append(contentsOf: proofsToAdd)
        
        // Save updated proofs
        try await save()
    }
    
    /// Save wallet state to NIP-60 events
    public func save() async throws {
        guard let signer = ndk.signer else {
            throw NDKError.notConfigured("No signer configured for NDKCashuWallet")
        }
        
        try await saveWalletEvent(signer: signer)
        try await saveTokenEvents(signer: signer)
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
        
        // Load the token event if it's not filtered
        try await loadTokenEvent(event: event, signer: signer)
    }
    
    /// Save wallet configuration event (kind 17375)
    private func saveWalletEvent(signer: NDKSigner) async throws {
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
        
        // Create wallet event (kind 17375) - replaceable by kind
        let walletEvent = try await NDKEventBuilder()
            .content(encryptedContent)
            .kind(17375)
            .build(signer: signer)
        
        // Log event ID
        print("📝 Wallet event ID: \(walletEvent.id)")
        
        let publishedRelays = try await ndk.publish(walletEvent, logRawJSON: true)
        print("📡 Published to \(publishedRelays.count) relays")
    }
    
    /// Save token events (kind 7375) containing encrypted proofs
    private func saveTokenEvents(signer: NDKSigner) async throws {
        try await saveTokenEventsWithDeleted(signer: signer, deletedEventIds: nil)
    }
    
    /// Save token events with optional deleted event IDs
    private func saveTokenEventsWithDeleted(signer: NDKSigner, deletedEventIds: [String]?) async throws {
        // Group proofs by mint for separate token events
        var proofsByMint: [String: [CashuSwift.Proof]] = [:]
        
        for proof in proofs {
            // Find which mint this proof belongs to
            for (mintURL, mint) in mints {
                if mint.keysets.contains(where: { $0.keysetID == proof.keysetID }) {
                    if proofsByMint[mintURL] == nil {
                        proofsByMint[mintURL] = []
                    }
                    proofsByMint[mintURL]?.append(proof)
                    break
                }
            }
        }
        
        // Create token event for each mint's proofs
        for (mintURL, mintProofs) in proofsByMint {
            let token = CashuSwift.Token(
                proofs: [mintURL: mintProofs],
                unit: "sat"
            )
            
            _ = try await saveTokenEvent(token: token, signer: signer, deletedEventIds: deletedEventIds)
        }
    }
    
    /// Save individual token event
    private func saveTokenEvent(token: CashuSwift.Token, signer: NDKSigner, deletedEventIds: [String]? = nil) async throws -> String {
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
        
        // Create token event (kind 7375)
        let tokenEvent = try await NDKEventBuilder()
            .content(encryptedContent)
            .kind(7375)
            .build(signer: signer)
        
        try await ndk.publish(tokenEvent, logRawJSON: true)
        
        return tokenEvent.id
    }
    
    
    // MARK: - Private Helper Methods
    
    /// Split amount into base 2 numbers
    private func splitIntoBase2(_ n: Int) -> [Int] {
        return (0 ..< Int.bitWidth - n.leadingZeroBitCount)
            .map { 1 << $0 }
            .filter { $0 & n > 0 }
    }
    
    /// Select proofs for a given amount
    private func selectProofs(amount: Int64) -> [CashuSwift.Proof] {
        var selected: [CashuSwift.Proof] = []
        var total: Int64 = 0
        
        // Sort proofs by amount (ascending) to minimize change
        let sortedProofs = proofs.sorted { $0.amount < $1.amount }
        
        for proof in sortedProofs {
            if total >= amount {
                break
            }
            selected.append(proof)
            total += Int64(proof.amount)
        }
        
        return total >= amount ? selected : []
    }
    
    /// Remove proofs from wallet and handle NIP-60 event management
    private func removeProofs(_ proofsToRemove: [CashuSwift.Proof]) {
        proofs.removeAll { proof in
            proofsToRemove.contains { $0.C == proof.C }
        }
    }
    
    /// Delete spent token events and create new ones for remaining proofs (NIP-60 rollover)
    public func rolloverProofs(spentProofs: [CashuSwift.Proof], originalEventIds: [String]) async throws {
        guard let signer = ndk.signer else {
            throw NDKError.notConfigured("No signer configured for NDKCashuWallet")
        }
        
        // Add original event IDs to our superseded set immediately
        supersededTokenEventIds.formUnion(originalEventIds)
        
        // Create delete events for the original token events
        for eventId in originalEventIds {
            try await createDeleteEvent(eventId: eventId, signer: signer)
        }
        
        // Save remaining proofs to new token events with del field
        try await saveTokenEventsWithDeleted(signer: signer, deletedEventIds: originalEventIds)
        
        // Create spending history event
        let spentAmount = spentProofs.reduce(0) { $0 + Int64($1.amount) }
        try await createSpendingHistoryEvent(
            direction: .out,
            amount: spentAmount,
            destroyedEventIds: originalEventIds,
            createdEventIds: nil, // Will be filled when new events are created
            signer: signer
        )
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
    
    /// Mint information
    public struct MintInfo {
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

// MARK: - Error Extensions

extension NDKError {
    static func invalidProof(_ message: String) -> NDKError {
        return NDKError.walletError(message: "Invalid proof: \(message)")
    }
    
    static func depositNotReady(_ message: String) -> NDKError {
        return NDKError.walletError(message: "Deposit not ready: \(message)")
    }
}