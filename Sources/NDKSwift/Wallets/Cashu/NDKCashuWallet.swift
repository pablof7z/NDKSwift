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
        guard let signer = ndk.signer else {
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
            throw NDKError.insufficientBalance("Not enough balance")
        }
        
        // Create a token
        let token = CashuSwift.Token(
            proofs: [mint.url.absoluteString: selectedProofs],
            unit: "sat",
            memo: description
        )
        
        // Remove the proofs from wallet as they're now in the token
        removeProofs(selectedProofs)
        
        return try token.serialized()
    }
    
    nonisolated public func supports(method: NDKPaymentMethod) -> Bool {
        switch method {
        case .nutzap:
            return true
        case .lightning:
            return false // We only support nutzaps for now
        }
    }
    
    // MARK: - Additional Methods
    
    /// Get available mints in this wallet
    public func getMints() async -> [MintInfo] {
        return mints.values.map { mint in
            MintInfo(
                url: mint.url.absoluteString,
                name: mint.url.host ?? "Unknown Mint",
                pubkey: "", // Would need to fetch from mint info
                version: "1.0",
                description: "Cashu mint",
                longDescription: nil,
                contact: [],
                motd: nil,
                nuts: [:]
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
            throw NDKError.insufficientBalance("Not enough balance")
        }
        
        let totalSelected = selectedProofs.reduce(0) { $0 + $1.amount }
        let change = totalSelected - Int(amount)
        
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
        
        // Fetch NIP-60 wallet events
        let filter = NDKFilter(
            kinds: [37375], // NIP-60 wallet event kind
            authors: [try await signer.pubkey],
            tags: [["d", walletId]]
        )
        
        let events = try await ndk.fetchEvents(filter)
        guard let latestEvent = events.first else {
            return // No wallet data found
        }
        
        // Parse wallet data from event content
        guard let walletData = try? JSONDecoder().decode(WalletData.self, from: latestEvent.content.data(using: .utf8) ?? Data()) else {
            throw NDKError.invalidContent("Failed to parse wallet data")
        }
        
        // Load mints
        for mintURLString in walletData.mints {
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
        }
        
        // Load proofs from encrypted NIP-60 proof events
        let proofFilter = NDKFilter(
            kinds: [7376], // NIP-60 proof event kind
            authors: [try await signer.pubkey],
            tags: [["a", "37375:\(try await signer.pubkey):\(walletId)"]]
        )
        
        let proofEvents = try await ndk.fetchEvents(proofFilter)
        for event in proofEvents {
            // Decrypt and parse proofs
            // This would require NIP-04 or NIP-44 decryption
            // For now, we'll skip the actual loading
        }
    }
    
    /// Save wallet state to NIP-60 events
    public func save() async throws {
        guard let signer = ndk.signer else {
            throw NDKError.notConfigured("No signer configured for NDKCashuWallet")
        }
        
        // Create wallet data
        let walletData = WalletData(
            name: "NDKSwift Cashu Wallet",
            mints: Array(mints.keys),
            unit: "sat"
        )
        
        let walletDataJSON = try JSONEncoder().encode(walletData)
        guard let content = String(data: walletDataJSON, encoding: .utf8) else {
            throw NDKError.encodingError("Failed to encode wallet data")
        }
        
        // Create NIP-60 wallet event
        var walletEvent = NDKEvent(
            pubkey: try await signer.pubkey,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: 37375,
            tags: [
                ["d", walletId],
                ["mint", Array(mints.keys).joined(separator: ",")],
                ["name", "NDKSwift Cashu Wallet"]
            ],
            content: content
        )
        
        try await walletEvent.sign(signer: ndk.signer)
        try await ndk.publish(walletEvent)
        
        // Save proofs as encrypted events
        // This would require implementing NIP-04 or NIP-44 encryption
        // For now, we'll skip the actual saving
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
    
    /// Remove proofs from wallet
    private func removeProofs(_ proofsToRemove: [CashuSwift.Proof]) {
        proofs.removeAll { proof in
            proofsToRemove.contains { $0.C == proof.C }
        }
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
        // Create cashu token
        guard let mint = mints.values.first else {
            throw NDKError.noMintAvailable("No mint available")
        }
        
        let token = CashuSwift.Token(
            proofs: [mint.url.absoluteString: proofs],
            unit: "sat",
            memo: comment
        )
        
        let tokenString = try token.serialized()
        
        // Create nutzap event (kind 9321)
        var nutzapEvent = NDKEvent(
            pubkey: try await signer.pubkey,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: 9321,
            tags: [
                ["p", recipient],
                ["amount", String(amount)],
                ["u", mint.url.absoluteString],
                ["proof", tokenString]
            ],
            content: comment ?? ""
        )
        
        try await nutzapEvent.sign(signer: ndk.signer)
        return nutzapEvent
    }
    
    /// Receive tokens from a serialized token string
    public func receiveToken(_ tokenString: String) async throws {
        let tokenData = tokenString.data(using: .utf8) ?? Data()
        let token = try JSONDecoder().decode(CashuSwift.Token.self, from: tokenData)
        
        // Verify and add proofs
        for entry in token.token {
            // Ensure we have the mint
            if mints[entry.mint] == nil {
                guard let mintURL = URL(string: entry.mint) else {
                    throw NDKError.invalidURL("Invalid mint URL: \(entry.mint)")
                }
                let mint = try await CashuSwift.loadMint(url: mintURL)
                addMint(mint)
            }
            
            // Add the proofs
            addProofs(entry.proofs)
        }
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