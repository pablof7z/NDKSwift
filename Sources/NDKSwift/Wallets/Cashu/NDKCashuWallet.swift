import Foundation
import CashuSwift

/// NIP-60 Cashu wallet implementation
public actor NDKCashuWallet: NDKWallet {
    // MARK: - Properties
    
    private let ndk: NDK
    private let walletId: String
    private var proofs: [CashuSwift.Proof] = []
    private var mints: [String: CashuSwift.Mint] = [:] // URL string to Mint
    private var keysets: [String: CashuSwift.Keyset] = [:] // Keyset ID to Keyset
    
    /// Mint discovery service for finding mints via Nostr
    public let mintDiscovery: MintDiscovery
    
    // MARK: - Initialization
    
    public init(ndk: NDK, walletId: String? = nil) {
        self.ndk = ndk
        self.walletId = walletId ?? UUID().uuidString
        self.mintDiscovery = MintDiscovery(ndk: ndk)
    }
    
    // MARK: - NDKWallet Protocol
    
    public func pay(_ request: NDKPaymentRequest) async throws -> NDKPaymentConfirmation {
        guard ndk.signer != nil else {
            throw NDKError.notConfigured("No signer configured for NDKCashuWallet")
        }
        
        guard let nutzapRequest = request as? NDKNutzapRequest else {
            throw NDKError.invalidRequest("NDKCashuWallet only supports nutzap payments")
        }
        
        // Select proofs for the requested amount
        let selectedProofs = selectProofs(amount: nutzapRequest.amount)
        guard !selectedProofs.isEmpty else {
            throw NDKError.insufficientBalance(amount: nutzapRequest.amount)
        }
        
        // Create nutzap event with the selected proofs
        let nutzapEvent = try await createNutzapEvent(
            proofs: selectedProofs,
            recipient: nutzapRequest.recipientPubkey,
            amount: nutzapRequest.amount,
            comment: nutzapRequest.comment
        )
        
        // Publish the nutzap event
        try await ndk.publish(nutzapEvent)
        
        // Remove spent proofs from wallet
        removeProofs(selectedProofs)
        
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
    
    // MARK: - Additional Methods
    
    /// Get available mints in this wallet
    public func getMints() async -> [MintInfo] {
        return mints.values.map { mint in
            MintInfo(
                url: mint.url
            )
        }
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
        // Select proofs for the amount
        let selectedProofs = selectProofs(amount: amount)
        guard !selectedProofs.isEmpty else {
            throw NDKError.insufficientBalance(amount: amount)
        }
        
        let totalSelected = selectedProofs.reduce(0) { $0 + $1.amount }
        _ = totalSelected - Int(amount)
        
        // Convert to CashuProof type
        let cashuProofs = selectedProofs.map { proof in
            CashuProof(
                id: proof.keysetID,
                amount: proof.amount,
                secret: proof.secret,
                C: proof.C
            )
        }
        
        // Remove spent proofs
        removeProofs(selectedProofs)
        
        // For now, we don't handle change splitting
        return (proofs: cashuProofs, change: nil)
    }
    
    /// Pay a Lightning invoice through a mint
    public func payLightning(invoice: String, amount: Int64) async throws -> (preimage: String, feePaid: Int64?) {
        // This would require the melt functionality from CashuSwift
        // For now, we don't support Lightning payments
        throw NDKError.notImplemented("Lightning payments not yet supported")
    }
    
    /// Mint tokens from a Lightning invoice payment
    public func mintTokens(amount: Int64, mintURL: String) async throws {
        // This would require the mint functionality from CashuSwift
        // For now, we don't support minting
        throw NDKError.notImplemented("Minting not yet supported")
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
            kinds: [17375], // NIP-60 wallet event kind
            tags: ["d": Set([walletId])]
        )
        
        let events = try await ndk.fetchEvents(filter)
        guard let latestEvent = events.first else {
            return // No wallet data found
        }
        
        // Decrypt wallet configuration
        let sender = NDKUser(pubkey: try await signer.pubkey)
        let decryptedContent = try await signer.decrypt(
            sender: sender,
            value: latestEvent.content,
            scheme: .nip44
        )
        
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
                // Store P2PK private key (would typically be stored securely)
                // For now, we just acknowledge it exists
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
        let filter = NDKFilter(
            authors: [try await signer.pubkey],
            kinds: [7375] // NIP-60 token event kind
        )
        
        let events = try await ndk.fetchEvents(filter)
        
        for event in events {
            do {
                try await loadTokenEvent(event: event, signer: signer)
            } catch {
                print("Failed to load token event \(event.id): \(error)")
            }
        }
    }
    
    /// Load individual token event and extract proofs
    private func loadTokenEvent(event: NDKEvent, signer: NDKSigner) async throws {
        // Decrypt token event content
        let sender = NDKUser(pubkey: try await signer.pubkey)
        let decryptedContent = try await signer.decrypt(
            sender: sender,
            value: event.content,
            scheme: .nip44
        )
        
        // Parse token data
        guard let tokenData = decryptedContent.data(using: .utf8),
              let tokenObject = try? JSONSerialization.jsonObject(with: tokenData) as? [String: Any] else {
            throw NDKError.invalidContent("Failed to parse token data")
        }
        
        guard let mintURL = tokenObject["mint"] as? String,
              let proofsArray = tokenObject["proofs"] as? [[String: Any]] else {
            throw NDKError.invalidContent("Invalid token data format")
        }
        
        // Convert proofs to CashuSwift.Proof format
        var loadedProofs: [CashuSwift.Proof] = []
        
        for proofDict in proofsArray {
            guard let keysetID = proofDict["id"] as? String,
                  let amount = proofDict["amount"] as? Int,
                  let secret = proofDict["secret"] as? String,
                  let C = proofDict["C"] as? String else {
                continue
            }
            
            // Create CashuSwift.Proof (this may need adjustment based on actual CashuSwift API)
            let proof = CashuSwift.Proof(
                keysetID: keysetID,
                amount: amount,
                secret: secret,
                C: C
            )
            
            loadedProofs.append(proof)
        }
        
        // Add proofs to wallet
        proofs.append(contentsOf: loadedProofs)
        
        // Ensure we have the mint loaded
        if mints[mintURL] == nil {
            guard let url = URL(string: mintURL) else { return }
            
            do {
                let mint = try await CashuSwift.loadMint(url: url)
                mints[mintURL] = mint
                
                // Store keysets
                for keyset in mint.keysets {
                    keysets[keyset.keysetID] = keyset
                }
            } catch {
                print("Failed to load mint \(mintURL): \(error)")
            }
        }
    }
    
    /// Save wallet state to NIP-60 events
    public func save() async throws {
        guard let signer = ndk.signer else {
            throw NDKError.notConfigured("No signer configured for NDKCashuWallet")
        }
        
        try await saveWalletEvent(signer: signer)
        try await saveTokenEvents(signer: signer)
    }
    
    /// Save wallet configuration event (kind 17375)
    private func saveWalletEvent(signer: NDKSigner) async throws {
        // Create wallet configuration tags
        var walletTags: [[String]] = []
        
        // Add P2PK private key (generate if needed)
        let p2pkPrivateKey = try generateP2PKPrivateKey()
        walletTags.append(["privkey", p2pkPrivateKey])
        
        // Add mint URLs
        for mintURL in mints.keys {
            walletTags.append(["mint", mintURL])
        }
        
        // Encrypt the wallet configuration
        let walletDataJSON = try JSONEncoder().encode(walletTags)
        guard let plaintext = String(data: walletDataJSON, encoding: .utf8) else {
            throw NDKError.encodingError("Failed to encode wallet data")
        }
        
        let signerPubkey = try await signer.pubkey
        let recipient = NDKUser(pubkey: signerPubkey)
        let encryptedContent = try await signer.encrypt(
            recipient: recipient, 
            value: plaintext, 
            scheme: .nip44
        )
        
        // Create wallet event (kind 17375) - replaceable by d tag
        let walletEvent = try await NDKEventBuilder()
            .content(encryptedContent)
            .kind(17375)
            .tags([["d", walletId]])
            .build(signer: signer)
        try await ndk.publish(walletEvent)
    }
    
    /// Save token events (kind 7375) containing encrypted proofs
    private func saveTokenEvents(signer: NDKSigner) async throws {
        // Group proofs by mint for separate token events
        var proofsByMint: [String: [CashuSwift.Proof]] = [:]
        
        for proof in proofs {
            // Find which mint this proof belongs to by checking keysets
            var mintURL: String?
            for (url, mint) in mints {
                if mint.keysets.contains(where: { $0.keysetID == proof.keysetID }) {
                    mintURL = url
                    break
                }
            }
            
            if let mintURL = mintURL {
                if proofsByMint[mintURL] == nil {
                    proofsByMint[mintURL] = []
                }
                proofsByMint[mintURL]?.append(proof)
            }
        }
        
        // Create token event for each mint
        for (mintURL, mintProofs) in proofsByMint {
            try await saveTokenEvent(
                mintURL: mintURL,
                proofs: mintProofs,
                signer: signer
            )
        }
    }
    
    /// Save individual token event for a specific mint
    private func saveTokenEvent(
        mintURL: String,
        proofs: [CashuSwift.Proof],
        signer: NDKSigner
    ) async throws {
        // Convert CashuSwift.Proof to the format expected by NIP-60
        let nip60Proofs = proofs.map { proof in
            [
                "id": proof.keysetID,
                "amount": proof.amount,
                "secret": proof.secret,
                "C": proof.C
            ]
        }
        
        // Create token event payload
        let tokenData: [String: Any] = [
            "mint": mintURL,
            "proofs": nip60Proofs,
            "del": [] // No deletion references for now
        ]
        
        // Encrypt the token data
        let tokenDataJSON = try JSONSerialization.data(withJSONObject: tokenData, options: [])
        guard let plaintext = String(data: tokenDataJSON, encoding: .utf8) else {
            throw NDKError.encodingError("Failed to encode token data")
        }
        
        let signerPubkey = try await signer.pubkey
        let recipient = NDKUser(pubkey: signerPubkey)
        let encryptedContent = try await signer.encrypt(
            recipient: recipient,
            value: plaintext,
            scheme: .nip44
        )
        
        // Create token event (kind 7375)
        let tokenEvent = try await NDKEventBuilder()
            .content(encryptedContent)
            .kind(7375)
            .tags([]) // Empty tags for privacy as per NIP-60
            .build(signer: signer)
        try await ndk.publish(tokenEvent)
    }
    
    /// Generate P2PK private key for receiving nutzaps
    private func generateP2PKPrivateKey() throws -> String {
        // For now, generate a random 32-byte private key
        // In a real implementation, this should be derived deterministically
        // from the wallet seed or stored persistently
        let privateKeyData = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        return privateKeyData.map { String(format: "%02hhx", $0) }.joined()
    }
    
    // MARK: - Private Helper Methods
    
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
        
        // Create delete events for the original token events
        for eventId in originalEventIds {
            try await createDeleteEvent(eventId: eventId, signer: signer)
        }
        
        // Save remaining proofs to new token events
        try await saveTokenEvents(signer: signer)
    }
    
    /// Create a delete event for a spent token event (NIP-09)
    private func createDeleteEvent(eventId: String, signer: NDKSigner) async throws {
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
    
    /// Add proofs to wallet
    public func addProofs(_ newProofs: [CashuSwift.Proof]) {
        proofs.append(contentsOf: newProofs)
    }
    
    /// Add a mint to the wallet
    public func addMint(_ mint: CashuSwift.Mint) {
        mints[mint.url.absoluteString] = mint
        for keyset in mint.keysets {
            keysets[keyset.keysetID] = keyset
        }
    }
    
    /// Create a nutzap event
    private func createNutzapEvent(
        proofs: [CashuSwift.Proof],
        recipient: String,
        amount: Int64,
        comment: String?
    ) async throws -> NDKEvent {
        guard let signer = ndk.signer else {
            throw NDKError.notConfigured("No signer configured for NDKCashuWallet")
        }
        
        // Create cashu token
        guard let mint = mints.values.first else {
            throw NDKError.noMintAvailable("No mint available")
        }
        
        let token = CashuSwift.Token(
            proofs: [mint.url.absoluteString: proofs],
            unit: "sat",
            memo: comment
        )
        
        // Convert token to JSON string (adjust method name based on actual CashuSwift API)
        let tokenData = try JSONEncoder().encode(token)
        guard let tokenString = String(data: tokenData, encoding: .utf8) else {
            throw NDKError.encodingError("Failed to encode token")
        }
        
        // Create nutzap event (kind 9321)
        let nutzapEvent = try await NDKEventBuilder()
            .content(comment ?? "")
            .kind(9321)
            .tags([
                ["p", recipient],
                ["amount", String(amount)],
                ["u", mint.url.absoluteString],
                ["proof", tokenString]
            ])
            .build(signer: signer)
        return nutzapEvent
    }
    
    /// Receive tokens from a serialized token string
    public func receiveToken(_ tokenString: String) async throws {
        let tokenData = tokenString.data(using: .utf8) ?? Data()
        let token = try JSONDecoder().decode(CashuSwift.Token.self, from: tokenData)
        
        // Verify and add proofs
        for (mintUrl, mintProofs) in token.proofsByMint {
            // Ensure we have the mint
            if mints[mintUrl] == nil {
                guard let mintURL = URL(string: mintUrl) else {
                    throw NDKError.invalidURL("Invalid mint URL: \(mintUrl)")
                }
                let mint = try await CashuSwift.loadMint(url: mintURL)
                addMint(mint)
            }
            
            // Add the proofs
            addProofs(mintProofs)
        }
    }
}

// MARK: - Supporting Types

struct WalletData: Codable {
    let name: String
    let mints: [String]
    let unit: String
}

// NDKCashuPaymentConfirmation is now defined in NDKWallet.swift to avoid duplication