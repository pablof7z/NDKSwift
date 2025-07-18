import Foundation
import CashuSwift

/// Functions for handling nutzap operations (P2PK-locked tokens via Nostr events)
public enum Nutzap {
    
    // MARK: - Sending Nutzaps
    
    /// Send a nutzap to a recipient
    /// - Parameters:
    ///   - wallet: The NIP60 wallet to send from
    ///   - amount: Amount to send in satoshis
    ///   - recipient: Recipient's Nostr public key
    ///   - recipientP2PKKey: Recipient's P2PK key (from their kind:10019 event or payment request)
    ///   - comment: Optional comment for the nutzap
    ///   - eventId: Optional event ID if nutzapping an event
    ///   - mints: Available mints
    ///   - proofStateManager: Proof state manager
    ///   - eventManager: Event manager for history
    ///   - ndk: NDK instance
    ///   - signer: Signer for the nutzap event
    public static func send(
        wallet: NIP60Wallet,
        amount: Int64,
        to recipient: PublicKey,
        recipientP2PKKey: String,
        comment: String? = nil,
        eventId: String? = nil,
        mints: [String: CashuSwift.Mint],
        proofStateManager: ProofStateManager,
        eventManager: WalletEventManager,
        ndk: NDK,
        signer: NDKSigner
    ) async throws -> NDKEvent {
        // Find mints with sufficient balance, ordered by balance (highest first)
        var mintsWithBalance: [(url: String, mint: CashuSwift.Mint, balance: Int64)] = []
        for (mintURL, mint) in mints {
            let balance = await proofStateManager.getBalance(mint: mintURL)
            if balance >= amount {
                mintsWithBalance.append((url: mintURL, mint: mint, balance: balance))
            }
        }
        
        // Sort by balance (highest first) to try the mint with most balance first
        let viableMints = mintsWithBalance
            .sorted { $0.balance > $1.balance }
            .map { (url: $0.url, mint: $0.mint) }
        
        guard !viableMints.isEmpty else {
            throw NDKError.insufficientBalance(amount: amount)
        }
        
        // Use the provided P2PK key (should come from payment request)
        let recipientP2PK = recipientP2PKKey
        
        // Try each viable mint until one succeeds
        var lastError: Error?
        for (mintURL, mint) in viableMints {
            // Select and lock proofs
            let selectedProofs = await proofStateManager.selectProofs(amount: amount, mint: mintURL)
            guard !selectedProofs.isEmpty else {
                lastError = NDKError.insufficientBalance(amount: amount)
                continue
            }
            
            // Reserve proofs
            do {
                try await proofStateManager.reserveProofs(selectedProofs)
            } catch {
                lastError = error
                continue
            }
            
            do {
                // Create P2PK-locked proofs
                let (lockedProofs, change) = try await lockProofsForRecipient(
                    proofs: selectedProofs,
                    amount: amount,
                    recipientPubkey: recipientP2PK,
                    mint: mint,
                    mintURL: mintURL
                )
                
                // Create nutzap event
                let nutzapEvent = try await createNutzapEvent(
                    wallet: wallet,
                    proofs: lockedProofs,
                    recipient: recipient,
                    amount: amount,
                    comment: comment,
                    eventId: eventId,
                    signer: signer
                )
                
                // Publish the nutzap
                _ = try await ndk.publish(nutzapEvent)
                
                // Update wallet state
                await proofStateManager.markProofsAsDeleted(selectedProofs)
                if let changeProofs = change {
                    for proof in changeProofs {
                        await proofStateManager.addProof(proof, mint: mintURL)
                    }
                }
                
                // Update token events
                let stateChange = WalletStateChange(
                    store: change ?? [],
                    destroy: selectedProofs,
                    mint: mintURL,
                    memo: "Send nutzap"
                )
                _ = try await wallet.update(stateChange: stateChange)
                
                // Create spending history
                try await eventManager.createSpendingHistoryEvent(
                    direction: .out,
                    amount: amount,
                    memo: comment ?? "Nutzap sent",
                    destroyedEventIds: nil,
                    createdEventIds: nil,
                    redeemedEventId: nil,
                    signer: signer
                )
                
                return nutzapEvent
                
            } catch {
                // Release proofs on failure and try next mint
                await proofStateManager.releaseProofs(selectedProofs)
                lastError = error
                print("Nutzap failed with mint \(mintURL): \(error). Trying next mint...")
                continue
            }
        }
        
        // If we reach here, all mints failed
        throw lastError ?? NDKError.insufficientBalance(amount: amount)
    }
    
    // MARK: - Receiving Nutzaps
    
    /// Process an incoming nutzap event
    public static func processIncoming(
        wallet: NIP60Wallet,
        event: NDKEvent,
        mints: [String: CashuSwift.Mint],
        keysets: [String: CashuSwift.Keyset],
        proofStateManager: ProofStateManager,
        eventManager: WalletEventManager,
        p2pkManager: P2PKManager,
        ndk: NDK,
        signer: NDKSigner
    ) async throws {
        // Check if this nutzap is for us
        let privateKey = try await p2pkManager.getOrCreatePrivateKey()
        let ourPubkeyHex = try await p2pkManager.getCashuPublicKey()
        
        // Verify p tag points to our Nostr pubkey
        let pTags = event.tags.filter { $0.first == "p" }
        guard let recipientTag = pTags.first,
              recipientTag.count > 1 else {
            // No recipient tag
            return
        }
        
        // Get mint URLs from u tags
        let mintURLs = event.tags
            .filter { $0.count >= 2 && $0[0] == "u" }
            .map { $0[1] }
        
        guard !mintURLs.isEmpty else {
            print("No mint URLs in nutzap")
            return
        }
        
        // Extract proofs from proof tags
        let proofTags = event.tags.filter { $0.count >= 2 && $0[0] == "proof" }
        guard !proofTags.isEmpty else {
            print("No proofs in nutzap")
            return
        }
        
        var allProofs: [CashuSwift.Proof] = []
        for proofTag in proofTags {
            guard let proofData = proofTag[1].data(using: .utf8),
                  let proof = try? JSONDecoder().decode(CashuSwift.Proof.self, from: proofData) else {
                print("Failed to decode proof from tag")
                continue
            }
            allProofs.append(proof)
        }
        
        var totalReceived: Int64 = 0
        var redeemedProofs: [CashuSwift.Proof] = []
        
        // Filter proofs locked to us
        let ourProofs = CashuHelpers.filterProofsLockedTo(proofs: allProofs, pubkey: ourPubkeyHex)
        guard !ourProofs.isEmpty else {
            print("No proofs locked to us in nutzap")
            return
        }
        
        // Process proofs by mint
        for mintURL in mintURLs {
            guard let mint = mints[mintURL] else {
                print("Unknown mint in nutzap: \(mintURL)")
                continue
            }
            
            // Find proofs for this mint
            let mintProofs = ourProofs.filter { proof in
                mint.keysets.contains { $0.keysetID == proof.keysetID }
            }
            
            guard !mintProofs.isEmpty else { continue }
            
            // Redeem the P2PK-locked proofs
            let lockedToken = CashuSwift.Token(
                proofs: [mintURL: mintProofs],
                unit: "sat"
            )
            let (unlockedProofs, _, _) = try await CashuSwift.receive(
                token: lockedToken,
                of: mint,
                seed: nil,
                privateKey: privateKey
            )
            
            // Add unlocked proofs to our wallet
            for proof in unlockedProofs {
                await proofStateManager.addProof(proof, mint: mintURL)
                totalReceived += Int64(proof.amount)
            }
            
            redeemedProofs.append(contentsOf: unlockedProofs)
        }
        
        guard totalReceived > 0 else { return }
        
        // Update wallet state
        // Group by mint since we may have redeemed from multiple mints
        var proofsByMint: [String: [CashuSwift.Proof]] = [:]
        for proof in redeemedProofs {
            if let proofMint = mints.first(where: { _, mint in 
                mint.keysets.contains { $0.keysetID == proof.keysetID }
            }) {
                proofsByMint[proofMint.key, default: []].append(proof)
            }
        }
        
        // Update state for each mint
        for (mintURL, proofs) in proofsByMint {
            let stateChange = WalletStateChange(
                store: proofs,
                destroy: [],
                mint: mintURL,
                memo: "Receive nutzap"
            )
            _ = try await wallet.update(stateChange: stateChange)
        }
        
        // Create spending history for received nutzap
        // The comment is in the content field per NIP-61
        let nutzapComment = event.content.isEmpty ? nil : event.content
        
        try await eventManager.createSpendingHistoryEvent(
            direction: .in,
            amount: totalReceived,
            memo: nutzapComment ?? "Nutzap received",
            destroyedEventIds: nil,
            createdEventIds: nil,
            redeemedEventId: event.id,
            signer: signer
        )
        
        // Emit nutzap received notification
        await emitNutzapReceived(event: event, amount: totalReceived)
    }
    
    // MARK: - Private Helper Functions
    
    private static func lockProofsForRecipient(
        proofs: [CashuSwift.Proof],
        amount: Int64,
        recipientPubkey: String,
        mint: CashuSwift.Mint,
        mintURL: String
    ) async throws -> (proofs: [CashuSwift.Proof], change: [CashuSwift.Proof]?) {
        // Use CashuSwift's send function with P2PK locking
        let (token, changeProofs, _) = try await CashuSwift.send(
            inputs: proofs,
            mint: mint,
            amount: Int(amount),
            seed: nil,
            memo: nil,
            lockToPublicKey: recipientPubkey
        )
        
        // Get the locked proofs from the token
        guard let lockedProofs = token.proofsByMint[mintURL] else {
            throw NDKError.invalidProof("No proofs in created token")
        }
        
        return (proofs: lockedProofs, change: changeProofs)
    }
    
    private static func createNutzapEvent(
        wallet: NIP60Wallet,
        proofs: [CashuSwift.Proof],
        recipient: PublicKey,
        amount: Int64,
        comment: String?,
        eventId: String?,
        signer: NDKSigner
    ) async throws -> NDKEvent {
        // Get mints reference
        let mints = await wallet.mints.getAllMints()
        
        // Build nutzap event (kind 9321)
        let eventBuilder = wallet.ndk.event()
            .content(comment ?? "") // Content is the comment, not the token
            .kind(9321) // Nutzap kind
        
        // Add p tag for recipient
        _ = eventBuilder.tag(["p", recipient])
        
        // Add e tag if nutzapping an event
        if let eventId = eventId {
            _ = eventBuilder.tag(["e", eventId])
        }
        
        // Group proofs by mint and add proof/u tags for each mint
        var mintURLs = Set<String>()
        
        for proof in proofs {
            // Find mint URL for this proof
            for (mintURL, mint) in mints {
                if mint.keysets.contains(where: { $0.keysetID == proof.keysetID }) {
                    mintURLs.insert(mintURL)
                    
                    // Encode the proof as JSON
                    let proofData = try JSONEncoder().encode(proof)
                    let proofJSON = String(data: proofData, encoding: .utf8) ?? ""
                    
                    // Add proof tag
                    _ = eventBuilder.tag(["proof", proofJSON])
                    
                    break
                }
            }
        }
        
        // Add u tag for each mint URL
        for mintURL in mintURLs {
            _ = eventBuilder.tag(["u", mintURL])
        }
        
        let nutzapEvent = try await eventBuilder.build(signer: signer)
        
        return nutzapEvent
    }
    
    private static func emitNutzapReceived(event: NDKEvent, amount: Int64) async {
        // Emit notification for UI updates
        await MainActor.run {
            NotificationCenter.default.post(
                name: .nutzapReceived,
                object: nil,
                userInfo: [
                    "event": event,
                    "amount": amount
                ]
            )
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let nutzapReceived = Notification.Name("NIP60Wallet.nutzapReceived")
}