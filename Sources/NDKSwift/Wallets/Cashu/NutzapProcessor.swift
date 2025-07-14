import Foundation
import CashuSwift

/// Handles nutzap operations for Cashu wallets
/// This includes sending and receiving P2PK-locked tokens via Nostr events
public actor NutzapProcessor {
    // MARK: - Properties
    
    private let proofStateManager: ProofStateManager
    private let eventManager: WalletEventManager
    private let p2pkManager: P2PKManager
    private let ndk: NDK
    
    // MARK: - Initialization
    
    init(
        proofStateManager: ProofStateManager,
        eventManager: WalletEventManager,
        p2pkManager: P2PKManager,
        ndk: NDK
    ) {
        self.proofStateManager = proofStateManager
        self.eventManager = eventManager
        self.p2pkManager = p2pkManager
        self.ndk = ndk
    }
    
    
    // MARK: - Sending Nutzaps
    
    /// Send a nutzap to a recipient
    public func sendNutzap(
        wallet: NDKCashuWallet,
        amount: Int64,
        to recipient: PublicKey,
        comment: String? = nil,
        eventId: String? = nil,
        mints: [String: CashuSwift.Mint],
        signer: NDKSigner
    ) async throws -> NDKEvent {
        // Find a mint with sufficient balance
        var selectedMint: (url: String, mint: CashuSwift.Mint)?
        for (mintURL, mint) in mints {
            let balance = await proofStateManager.getBalance(mint: mintURL)
            if balance >= amount {
                selectedMint = (url: mintURL, mint: mint)
                break
            }
        }
        
        guard let (mintURL, mint) = selectedMint else {
            throw NDKError.insufficientBalance(amount: amount)
        }
        
        // Get recipient's P2PK pubkey (for nutzaps, it's their Nostr pubkey)
        let recipientP2PK = recipient
        
        // Select and lock proofs
        let selectedProofs = await proofStateManager.selectProofs(amount: amount, mint: mintURL)
        guard !selectedProofs.isEmpty else {
            throw NDKError.insufficientBalance(amount: amount)
        }
        
        // Reserve proofs
        try await proofStateManager.reserveProofs(selectedProofs)
        
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
            try await ndk.publish(nutzapEvent)
            
            // Update wallet state
            await proofStateManager.markProofsAsDeleted(selectedProofs)
            if let changeProofs = change {
                for proof in changeProofs {
                    await proofStateManager.addProof(proof, mint: mintURL)
                }
            }
            
            // Update token events
            _ = try await wallet.update(deletedProofs: selectedProofs, addedProofs: change ?? [])
            
            // Create spending history
            try await eventManager.createSpendingHistoryEvent(
                direction: .out,
                amount: amount,
                destroyedEventIds: nil,
                createdEventIds: nil,
                redeemedEventId: nil,
                signer: signer
            )
            
            return nutzapEvent
            
        } catch {
            // Release proofs on failure
            await proofStateManager.releaseProofs(selectedProofs)
            throw error
        }
    }
    
    // MARK: - Receiving Nutzaps
    
    /// Process an incoming nutzap event
    public func processIncomingNutzap(
        wallet: NDKCashuWallet,
        _ event: NDKEvent,
        mints: [String: CashuSwift.Mint],
        keysets: [String: CashuSwift.Keyset],
        signer: NDKSigner
    ) async throws {
        // Check if this nutzap is for us
        let privateKey = try await p2pkManager.getOrCreatePrivateKey()
        let ourPubkeyHex = try await p2pkManager.getCashuPublicKey()
        
        // Verify p tag points to our pubkey
        let pTags = event.tags.filter { $0.first == "p" }
        guard let recipientTag = pTags.first,
              recipientTag.count > 1,
              recipientTag[1] == ourPubkeyHex else {
            // Not for us
            return
        }
        
        // Decode the token from content
        guard let tokenData = event.content.data(using: .utf8),
              let token = try? JSONDecoder().decode(CashuSwift.Token.self, from: tokenData) else {
            print("Failed to decode token from nutzap")
            return
        }
        
        var totalReceived: Int64 = 0
        var redeemedProofs: [CashuSwift.Proof] = []
        
        // Process each mint's proofs
        for (mintURL, proofs) in token.proofsByMint {
            guard let mint = mints[mintURL] else {
                print("Unknown mint in nutzap: \(mintURL)")
                continue
            }
            
            // Filter proofs locked to us
            let ourProofs = proofs.filter { $0.isLockedTo(pubkey: ourPubkeyHex) }
            guard !ourProofs.isEmpty else { continue }
            
            // Redeem the P2PK-locked proofs
            let lockedToken = CashuSwift.Token(
                proofs: [mintURL: ourProofs],
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
        _ = try await wallet.update(deletedProofs: [], addedProofs: redeemedProofs)
        
        // Create spending history for received nutzap
        if let signer = ndk.signer {
            try await eventManager.createSpendingHistoryEvent(
                direction: .in,
                amount: totalReceived,
                destroyedEventIds: nil,
                createdEventIds: nil,
                redeemedEventId: event.id,
                signer: signer
            )
        }
        
        // Emit nutzap received notification
        await emitNutzapReceived(event: event, amount: totalReceived)
    }
    
    // MARK: - Private Methods
    
    private func lockProofsForRecipient(
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
    
    private func createNutzapEvent(
        wallet: NDKCashuWallet,
        proofs: [CashuSwift.Proof],
        recipient: PublicKey,
        amount: Int64,
        comment: String?,
        eventId: String?,
        signer: NDKSigner
    ) async throws -> NDKEvent {
        // Get mints reference
        let mints = await wallet.getMints()
        
        // Group proofs by mint URL
        var proofsByMint: [String: [CashuSwift.Proof]] = [:]
        for proof in proofs {
            // Find mint URL for this proof
            for (mintURL, mint) in mints {
                if mint.keysets.contains(where: { $0.keysetID == proof.keysetID }) {
                    proofsByMint[mintURL, default: []].append(proof)
                    break
                }
            }
        }
        
        // Create token for the proofs
        let token = CashuSwift.Token(
            proofs: proofsByMint,
            unit: "sat"
        )
        
        // Encode token
        let tokenString = try token.serialize()
        
        // Build nutzap event (kind 9321)
        let eventBuilder = NDKEventBuilder()
            .content(tokenString)
            .kind(9321) // Nutzap kind
            .tag(["p", recipient, "", String(amount)])
        
        if let eventId = eventId {
            _ = eventBuilder.tag(["e", eventId])
        }
        
        _ = eventBuilder.tag(["amount", String(amount)])
        
        if let comment = comment {
            _ = eventBuilder.tag(["comment", comment])
        }
        
        let nutzapEvent = try await eventBuilder.build(signer: signer)
        
        return nutzapEvent
    }
    
    private func emitNutzapReceived(event: NDKEvent, amount: Int64) async {
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
    static let nutzapReceived = Notification.Name("NDKCashuWallet.nutzapReceived")
}