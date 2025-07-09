import Foundation
import CashuSwift

/// NIP-60 Cashu wallet implementation
public actor NDKCashuWallet: NDKWallet {
    // MARK: - Properties
    
    private let ndk: NDK
    private let walletId: String
    private let proofManager: CashuProofManager
    private let eventHandler: CashuEventHandler
    private let p2pkManager: P2PKManager
    
    // Cached state
    private var mints: Set<String> = []
    private var balance: Int64 = 0
    private var isLoaded = false
    
    // CashuSwift connections with TTL
    private var mintConnections: [String: (mint: CashuSwift.Mint, connectedAt: Date)] = [:]
    private let mintConnectionTTL: TimeInterval = 300 // 5 minutes
    
    // MARK: - Initialization
    
    public init(ndk: NDK, walletId: String? = nil) {
        self.ndk = ndk
        self.walletId = walletId ?? UUID().uuidString
        self.proofManager = CashuProofManager()
        self.eventHandler = CashuEventHandler(ndk: ndk, walletId: self.walletId)
        self.p2pkManager = P2PKManager()
    }
    
    // MARK: - NDKWallet Protocol (Legacy - will be removed)
    
    public func pay(_ request: NDKPaymentRequest) async throws -> NDKPaymentConfirmation {
        // Legacy method - kept for backward compatibility
        // New code should use CashuPaymentProvider with NDKZapManager
        throw NDKError.notImplemented("Use CashuPaymentProvider with NDKZapManager instead")
    }
    
    public func getBalance() async throws -> Int64 {
        if !isLoaded {
            try await load()
        }
        
        // Calculate from available proofs
        let availableProofs = await proofManager.getAvailableProofs()
        return availableProofs.reduce(0) { $0 + Int64($1.amount) }
    }
    
    public func createInvoice(amount: Int64, description: String?) async throws -> String {
        // This would require mint to support Lightning, which is optional
        throw NDKError.notImplemented("Lightning invoice creation not supported yet")
    }
    
    nonisolated public func supports(method: NDKPaymentMethod) -> Bool {
        return method == .nutzap
    }
    
    // MARK: - Wallet Operations
    
    /// Load wallet state from NIP-60 events
    public func load() async throws {
        // Load wallet metadata event (kind 7375)
        var walletFilter = NDKFilter(
            authors: [try await ndk.signer!.pubkey],
            kinds: [7375] // cashuWallet
        )
        walletFilter.addTagFilter("d", values: [walletId])
        
        if let walletEvent = try await ndk.fetchEvent(walletFilter) {
            let walletData = try await eventHandler.parseWalletEvent(walletEvent)
            self.mints = Set(walletData.mints)
        }
        
        // Load proof events (kind 7376)
        var proofFilter = NDKFilter(
            authors: [try await ndk.signer!.pubkey],
            kinds: [7376] // cashuToken
        )
        proofFilter.addTagFilter("wallet", values: [walletId])
        
        let proofEvents = try await ndk.fetchEvents(proofFilter)
        for event in proofEvents {
            let token = try await eventHandler.parseTokenEvent(event)
            for entry in token.token {
                await proofManager.addProofs(entry.proofs, mint: entry.mint)
            }
        }
        
        // Reconcile proof states with mints
        await reconcileProofStates()
        
        isLoaded = true
    }
    
    /// Save wallet state to NIP-60 events
    public func save() async throws {
        // Save wallet metadata
        let walletData = WalletData(
            name: "NDKSwift Wallet",
            mints: Array(mints),
            unit: "sat"
        )
        
        let walletEvent = try await eventHandler.createWalletEvent(walletData: walletData)
        try await ndk.publish(walletEvent)
        
        // Save proofs by mint
        let proofsByMint = await proofManager.getProofsByMint()
        for (mint, proofs) in proofsByMint {
            if !proofs.isEmpty {
                let token = CashuToken(
                    token: [TokenEntry(mint: mint, proofs: proofs)],
                    unit: "sat",
                    memo: "Wallet backup"
                )
                
                let tokenEvent = try await eventHandler.createTokenEvent(token: token, mint: mint)
                try await ndk.publish(tokenEvent)
            }
        }
    }
    
    /// Mint new tokens from a Lightning invoice payment
    public func mintTokens(amount: Int64, mintURL: String) async throws {
        // Ensure mint is connected
        let mint = try await ensureMintConnected(mintURL)
        
        // Add mint to our list
        mints.insert(mintURL)
        
        // Step 1: Request a mint quote from the mint
        let quoteRequest = CashuSwift.Bolt11.RequestMintQuote(
            amount: Int(amount),
            unit: "sat"
        )
        
        let quote = try await CashuSwift.getQuote(mint: mint, quoteRequest: quoteRequest)
        
        guard let mintQuote = quote as? CashuSwift.Bolt11.MintQuote else {
            throw NDKError.paymentFailed(reason: "Invalid quote type")
        }
        
        // Step 2: Pay the Lightning invoice (this would be done externally)
        // The wallet user needs to pay mintQuote.request (the bolt11 invoice)
        print("⚡ Pay this Lightning invoice: \(mintQuote.request)")
        print("⏳ Waiting for payment...")
        
        // Step 3: Poll for quote state until paid
        var isPaid = false
        var attempts = 0
        while !isPaid && attempts < 60 { // Wait up to 60 seconds
            let quoteState = try await CashuSwift.mintQuoteState(
                for: mintQuote.quote,
                mint: mint
            )
            
            if quoteState.state == .paid {
                isPaid = true
            } else {
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                attempts += 1
            }
        }
        
        guard isPaid else {
            throw NDKError.paymentFailed(reason: "Lightning invoice was not paid")
        }
        
        // Step 4: Issue the tokens
        let seed = try await generateSeed()
        let (proofs, validDLEQ) = try await CashuSwift.issue(
            for: mintQuote,
            with: mint,
            seed: seed
        )
        
        if !validDLEQ {
            print("⚠️ Warning: DLEQ verification failed for minted proofs")
        }
        
        // Step 5: Add proofs to our wallet
        let cashuProofs = proofs.map { $0.toNDKProof() }
        await proofManager.addProofs(cashuProofs, mint: mintURL)
        
        // Step 6: Save wallet state
        try await save()
    }
    
    // MARK: - Core Send Operations
    
    /// Send P2PK-locked proofs to a recipient
    /// This is the core method used by payment providers
    public func send(
        amount: Int64,
        to recipientP2PK: String,
        mint mintURL: URL
    ) async throws -> (proofs: [CashuProof], change: [CashuProof]?) {
        // Ensure wallet is loaded
        if !isLoaded {
            try await load()
        }
        
        // Check if we have this mint
        guard mints.contains(mintURL.absoluteString) else {
            throw NDKError.paymentFailed(reason: "Mint not available in wallet: \(mintURL)")
        }
        
        // Reserve proofs for this amount
        let reservationId = "send-\(UUID().uuidString)"
        let reservedProofs = try await proofManager.reserveProofs(
            amount: amount,
            mint: mintURL.absoluteString,
            for: reservationId
        )
        
        do {
            // Get mint connection
            let mint = try await ensureMintConnected(mintURL.absoluteString)
            
            // Convert our proofs to CashuSwift format
            let inputProofs = reservedProofs.map { $0.toCashuSwiftProof() }
            
            // Create P2PK-locked outputs
            let seed = try await generateSeed()
            let (lockedProofs, changeProofs, validDLEQ) = try await CashuSwift.send(
                proofs: inputProofs,
                amount: Int(amount),
                to: recipientP2PK,
                privKey: try await p2pkManager.getOrCreatePrivateKey(),
                mint: mint,
                seed: seed
            )
            
            if !validDLEQ {
                print("⚠️ Warning: DLEQ verification failed for locked proofs")
            }
            
            // Mark original proofs as spent
            await proofManager.markProofsAsSpent(
                proofs: reservedProofs,
                mint: mintURL.absoluteString
            )
            
            // Add change proofs back to wallet if any
            if !changeProofs.isEmpty {
                let ndkChangeProofs = changeProofs.map { $0.toNDKProof() }
                await proofManager.addProofs(ndkChangeProofs, mint: mintURL.absoluteString)
            }
            
            // Convert locked proofs to our format
            let ndkLockedProofs = lockedProofs.map { $0.toNDKProof() }
            let ndkChangeProofs = changeProofs.isEmpty ? nil : changeProofs.map { $0.toNDKProof() }
            
            // Save wallet state
            try? await save()
            
            return (proofs: ndkLockedProofs, change: ndkChangeProofs)
            
        } catch {
            // Release reserved proofs on failure
            await proofManager.releaseReservation(reservationId)
            throw error
        }
    }
    
    /// Get available mints in this wallet
    public func getMints() async -> [MintInfo] {
        return mints.compactMap { urlString in
            guard let url = URL(string: urlString) else { return nil }
            return MintInfo(url: url, features: nil)
        }
    }
    
    /// Get balance for a specific mint
    public func getBalance(mint mintURL: URL) async -> Int64 {
        let availableProofs = await proofManager.getAvailableProofs(mint: mintURL.absoluteString)
        return availableProofs.reduce(0) { $0 + Int64($1.amount) }
    }
    
    /// Pay a Lightning invoice through a mint
    public func payLightning(invoice: String, amount: Int64) async throws -> (preimage: String, feePaid: Int64?) {
        // Find a mint that supports Lightning
        // For now, just use the first mint
        guard let mintURL = mints.first else {
            throw NDKError.paymentFailed(reason: "No mints available")
        }
        
        let mint = try await ensureMintConnected(mintURL)
        
        // Reserve proofs
        let reservationId = "lightning-\(UUID().uuidString)"
        let reservedProofs = try await proofManager.reserveProofs(
            amount: amount,
            mint: mintURL,
            for: reservationId
        )
        
        do {
            // Convert proofs
            let inputProofs = reservedProofs.map { $0.toCashuSwiftProof() }
            
            // Melt tokens to pay Lightning invoice
            let meltResponse = try await CashuSwift.melt(
                invoice: invoice,
                with: inputProofs,
                mint: mint
            )
            
            // Mark proofs as spent
            await proofManager.markProofsAsSpent(
                proofs: reservedProofs,
                mint: mintURL
            )
            
            // Add change if any
            if !meltResponse.change.isEmpty {
                let changeProofs = meltResponse.change.map { $0.toNDKProof() }
                await proofManager.addProofs(changeProofs, mint: mintURL)
            }
            
            // Save wallet state
            try? await save()
            
            return (preimage: meltResponse.preimage ?? "", feePaid: Int64(meltResponse.fee_reserve ?? 0))
            
        } catch {
            // Release reserved proofs on failure
            await proofManager.releaseReservation(reservationId)
            throw error
        }
    }
    
    // MARK: - Nutzap Operations (Legacy)
    
    private func sendNutzap(
        to recipient: NDKUser,
        amount: Int64,
        mint mintURL: String,
        comment: String? = nil
    ) async throws -> NDKEvent {
        // Get recipient's P2PK pubkey
        let recipientP2PK = try await getRecipientP2PKPubkey(recipient)
        
        // Reserve proofs
        let reservedProofs = try await proofManager.reserveProofs(
            amount: amount,
            mint: mintURL,
            for: "nutzap-\(UUID().uuidString)"
        )
        
        do {
            // Lock proofs to recipient's P2PK pubkey using CashuSwift
            let mint = try await ensureMintConnected(mintURL)
            
            // Convert our proofs to CashuSwift format
            let inputProofs = reservedProofs.map { $0.toCashuSwiftProof() }
            
            // Get the P2PK memo (if it's a seed for deterministic output)
            let seed = try await generateSeed()
            
            // Send with P2PK lock
            let (token, change, outputDLEQ) = try await CashuSwift.send(
                inputs: inputProofs,
                mint: mint,
                amount: Int(amount),
                seed: seed,
                memo: comment,
                lockToPublicKey: recipientP2PK
            )
            
            if outputDLEQ != .valid {
                print("⚠️ Warning: DLEQ verification failed for locked proofs")
            }
            
            // Update our proof state - spent proofs are confirmed spent
            await proofManager.confirmSpent(reservedProofs.map { $0.secret })
            
            // Add change proofs back to our wallet
            if !change.isEmpty {
                let changeProofs = change.map { $0.toNDKProof() }
                await proofManager.addProofs(changeProofs, mint: mintURL)
            }
            
            // Extract the locked proofs from the token
            guard let lockedProofs = token.proofsByMint.first?.value else {
                throw NDKError.paymentFailed(reason: "No locked proofs in token")
            }
            
            // Create nutzap event with the locked proofs
            let nutzapEvent = try await createNutzapEvent(
                proofs: lockedProofs,
                mint: mintURL,
                recipient: recipient,
                comment: comment
            )
            
            // Publish nutzap
            try await ndk.publish(nutzapEvent)
            
            // Confirm proofs as spent
            await proofManager.confirmSpent(reservedProofs.map { $0.secret })
            
            // Save updated state
            try await save()
            
            return nutzapEvent
            
        } catch {
            // Release reservation on failure
            await proofManager.releaseReservation(reservedProofs.map { $0.secret })
            throw error
        }
    }
    
    // MARK: - Private Helpers
    
    private func ensureMintConnected(_ mintURL: String) async throws -> CashuSwift.Mint {
        // Check cache
        if let cached = mintConnections[mintURL],
           Date().timeIntervalSince(cached.connectedAt) < mintConnectionTTL {
            return cached.mint
        }
        
        // Connect to mint
        guard let url = URL(string: mintURL) else {
            throw NDKError.invalidURL(mintURL)
        }
        
        // Create mint and load its info
        let mint = CashuSwift.Mint(url: url)
        
        // Load mint info to populate keysets
        _ = try await mint.info()
        
        // Cache connection
        mintConnections[mintURL] = (mint, Date())
        
        return mint
    }
    
    private func reconcileProofStates() async {
        // Check proof states with mints
        let proofsByMint = await proofManager.getProofsByMint()
        
        for (mintURL, proofs) in proofsByMint {
            do {
                let mint = try await ensureMintConnected(mintURL)
                
                // Check which proofs are spent by attempting to swap them
                // If a proof is spent, the swap will fail
                for proof in proofs {
                    do {
                        // Try a minimal swap to check if proof is still valid
                        let inputProof = proof.toCashuSwiftProof()
                        let _ = try await CashuSwift.swap(
                            inputs: [inputProof],
                            with: mint,
                            amount: proof.amount,
                            seed: nil
                        )
                        // If swap succeeds, proof is still valid
                    } catch {
                        // If swap fails, assume proof is spent
                        await proofManager.markAsSpent(proof.secret)
                    }
                }
            } catch {
                // Log error but continue with other mints
                print("Failed to reconcile proofs for mint \(mintURL): \(error)")
            }
        }
        
        // Release expired reservations
        await proofManager.releaseExpiredReservations()
    }
    
    private func getRecipientMints(_ recipient: NDKUser) async throws -> Set<String> {
        let filter = NDKFilter(
            authors: [recipient.pubkey],
            kinds: [10019] // cashuMintList
        )
        
        if let mintListEvent = try await ndk.fetchEvent(filter),
           let mintList = try? JSONDecoder().decode(CashuMintList.self, from: mintListEvent.content.data(using: .utf8)!) {
            return Set(mintList.mints.map { $0.url })
        }
        
        return []
    }
    
    private func getRecipientP2PKPubkey(_ recipient: NDKUser) async throws -> String {
        let filter = NDKFilter(
            authors: [recipient.pubkey],
            kinds: [10019] // cashuMintList
        )
        
        if let mintListEvent = try await ndk.fetchEvent(filter) {
            // Look for P2PK pubkey in tags
            if let p2pkTag = mintListEvent.tags.first(where: { $0.count >= 2 && $0[0] == "pubkey" }) {
                return "02" + p2pkTag[1] // Convert to Cashu format
            }
        }
        
        // Fallback to using Nostr pubkey
        return "02" + recipient.pubkey
    }
    
    private func createNutzapEvent(
        proofs: [CashuSwift.Proof],
        mint: String,
        recipient: NDKUser,
        comment: String?
    ) async throws -> NDKEvent {
        let event = NDKEvent()
        event.ndk = ndk
        event.kind = 9321 // nutzap
        
        // Add required tags
        event.tags.append(["p", recipient.pubkey])
        event.tags.append(["mint", mint])
        event.tags.append(["u", "sat"])
        
        // Create token
        let token = CashuToken(
            token: [TokenEntry(
                mint: mint,
                proofs: proofs.map { $0.toNDKProof() }
            )],
            unit: "sat",
            memo: comment
        )
        
        // Serialize token as content
        let encoder = JSONEncoder()
        event.content = try encoder.encode(token).base64EncodedString()
        
        // Sign event
        try await event.sign()
        
        return event
    }
}

// MARK: - Supporting Types

struct WalletData: Codable {
    let name: String
    let mints: [String]
    let unit: String
}


public struct NDKCashuPaymentConfirmation: NDKPaymentConfirmation {
    public let amount: Int64
    public let recipient: String
    public let timestamp: Date
    public let preimage: String?
    public let paymentRequest: String?
    public let nutzap: NDKEvent
    
    public init(amount: Int64, recipient: String, timestamp: Date, nutzap: NDKEvent) {
        self.amount = amount
        self.recipient = recipient
        self.timestamp = timestamp
        self.preimage = nil
        self.paymentRequest = nil
        self.nutzap = nutzap
    }
}


// MARK: - Helper Methods

extension NDKCashuWallet {
    /// Generate a deterministic seed for this wallet
    private func generateSeed() async throws -> String {
        guard let signer = ndk.signer else {
            throw NDKError.signerNotConfigured
        }
        // Use wallet ID as seed source (in real app, might use private key derivation)
        let seedData = "\(walletId)".data(using: .utf8)!
        return seedData.sha256().hexString
    }
    
    /// Process incoming nutzaps
    public func processIncomingNutzap(_ event: NDKEvent) async throws {
        // Get the token from the event content
        let eventContent = await event.content
        guard let tokenData = eventContent.data(using: .utf8),
              let token = try? JSONDecoder().decode(CashuToken.self, from: tokenData) else {
            throw NDKError.invalidEvent("Invalid nutzap token format")
        }
        
        // Get our P2PK private key
        let (privateKey, _) = try await p2pkManager.getOrCreateKeypair()
        
        // Find the mint from the event
        let eventTags = await event.tags
        guard let mintTag = eventTags.first(where: { $0.count >= 2 && $0[0] == "mint" }),
              let mint = try? await ensureMintConnected(mintTag[1]) else {
            throw NDKError.invalidEvent("Missing or invalid mint in nutzap")
        }
        
        // Convert to CashuSwift token format
        let cashuToken = CashuSwift.Token(
            proofs: [mint.url.absoluteString: token.token.flatMap { $0.proofs.map { $0.toCashuSwiftProof() } }],
            unit: token.unit ?? "sat",
            memo: token.memo
        )
        
        // Receive the token (unlock P2PK proofs)
        let seed = try await generateSeed()
        let (receivedProofs, inputDLEQ, outputDLEQ) = try await CashuSwift.receive(
            token: cashuToken,
            of: mint,
            seed: seed,
            privateKey: privateKey
        )
        
        if inputDLEQ != .valid || outputDLEQ != .valid {
            print("⚠️ Warning: DLEQ verification failed for received nutzap")
        }
        
        // Add received proofs to our wallet
        let ndkProofs = receivedProofs.map { $0.toNDKProof() }
        await proofManager.addProofs(ndkProofs, mint: mint.url.absoluteString)
        
        // Save updated wallet state
        try await save()
    }
}


// MARK: - Factory Method

extension NDK {
    /// Create a Cashu wallet
    public func createCashuWallet(walletId: String? = nil) -> NDKCashuWallet {
        return NDKCashuWallet(ndk: self, walletId: walletId)
    }
}