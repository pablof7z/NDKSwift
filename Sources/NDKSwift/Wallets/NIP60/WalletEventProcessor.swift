import Foundation
import CashuSwift

/// Consolidated processor for all wallet-related events
/// Replaces the multiple EventHandler structs with a single, cohesive component
actor WalletEventProcessor {
    
    /// Process a wallet event based on its kind
    func processEvent(_ event: NDKEvent, context: WalletEventContext) async {
        print("wallet event received", event.kind)
        do {
            switch event.kind {
            case EventKind.cashuWalletConfig:
                await context.wallet.processWalletConfiguration(event: event)
            case EventKind.cashuToken:
                try await processTokenEvent(event, context: context)
            case EventKind.cashuQuote:
                try await processQuoteEvent(event, context: context)
            case EventKind.deletion:
                try await processDeleteEvent(event, context: context)
            case EventKind.nutzap:
                try await processNutzapEvent(event, context: context)
            default:
                print("⚠️ No handler for event kind \(event.kind)")
            }
        } catch {
            print("❌ Failed to process wallet event \(event.id): \(error)")
        }
    }
    
    // MARK: - Private Event Processing Methods
    
    /// Process token events
    private func processTokenEvent(_ event: NDKEvent, context: WalletEventContext) async throws {
        // First check if we should process this event
        if await context.eventManager.shouldFilterEvent(event.id) {
            print("⏭️ Skipping deleted or superseded token event: \(event.id)")
            return
        }
        
        print("💰 Processing token event: \(event.id)")
        print("💰 Event Kind: \(event.kind)")
        print("💰 Event Author: \(event.pubkey)")
        
        // Decrypt and process token
        let sender = NDKUser(pubkey: event.pubkey)
        let decryptedContent = try await context.signer.decrypt(
            sender: sender,
            value: event.content,
            scheme: .nip44
        )
        
        print("🔓 DECRYPTED TOKEN CONTENT:")
        print("🔓 Decrypted length: \(decryptedContent.count) characters")
        print("🔓 Decrypted content: \(decryptedContent)")
        print("🔓 Decrypted content (raw): \(String(describing: decryptedContent.data(using: .utf8)))")
        
        // Parse token data
        guard let tokenData = decryptedContent.data(using: .utf8),
              let nip60Token = try? JSONDecoder().decode(NIP60TokenEvent.self, from: tokenData) else {
            print("❌ Failed to parse NIP-60 token event data from decrypted content")
            throw NDKError.invalidContent("Failed to parse NIP-60 token event data")
        }
        
        print("🪙 PARSED TOKEN EVENT:")
        print("🪙 Mint URL: \(nip60Token.mint)")
        print("🪙 Proofs count: \(nip60Token.proofs.count)")
        print("🪙 Del tags count: \(nip60Token.del?.count ?? 0)")
        if let delTags = nip60Token.del {
            print("🪙 Del tags: \(delTags)")
        }
        for (index, proof) in nip60Token.proofs.enumerated() {
            print("🪙 Proof \(index): amount=\(proof.amount), keysetID=\(proof.keysetID), C=\(proof.C.prefix(20))...")
        }
        
        // Handle del tags - these events are no longer valid
        if let delIds = nip60Token.del {
            for delId in delIds {
                print("💰 Processing del tag for event: \(delId)")
                await deleteEventAndProofs(delId, context: context)
            }
        }
        
        // Add proofs to state
        for proof in nip60Token.proofs {
            await context.proofStateManager.addProof(
                proof, 
                mint: nip60Token.mint, 
                eventId: event.id,
                timestamp: event.createdAt
            )
        }
        
        await context.eventManager.addCurrentTokenEventId(event.id)
        
        // Update wallet's internal proofs array
        await context.wallet.updateProofsFromStateManager()
    }
    
    /// Process quote events
    private func processQuoteEvent(_ event: NDKEvent, context: WalletEventContext) async throws {
        print("📜 Processing quote event")
        print("📜 Event ID: \(event.id)")
        print("📜 Event Kind: \(event.kind)")
        print("📜 Event Author: \(event.pubkey)")
        print("📜 Encrypted content length: \(event.content.count) characters")
        print("📜 Encrypted content (first 100 chars): \(event.content.prefix(100))")
        
        // Decrypt content
        let sender = NDKUser(pubkey: event.pubkey)
        let decryptedContent = try await context.signer.decrypt(
            sender: sender,
            value: event.content,
            scheme: .nip44
        )
        
        print("🔓 DECRYPTED QUOTE CONTENT:")
        print("🔓 Decrypted length: \(decryptedContent.count) characters")
        print("🔓 Decrypted content: \(decryptedContent)")
        
        // Parse quote data
        guard let quoteData = decryptedContent.data(using: .utf8),
              let quote = try? JSONDecoder().decode(CashuMintQuote.self, from: quoteData) else {
            throw NDKError.invalidContent("Failed to parse quote event data")
        }
        
        print("📜 Loaded quote: \(quote.quoteId) for \(quote.amount) sats")
        
        // Start tracking the quote for automatic minting
        await context.wallet.trackQuote(quote: quote, event: event)
    }
    
    /// Process spending history events
    
    /// Process delete events (kind 5)
    private func processDeleteEvent(_ event: NDKEvent, context: WalletEventContext) async throws {
        print("🗑️ Processing delete event")
        
        // Find 'e' tags that reference events to delete
        let eventIdsToDelete = event.tags.compactMap { tag -> String? in
            guard tag.count >= 2 && tag[0] == "e" else { return nil }
            return tag[1]
        }
        
        // Find 'k' tags that specify kinds to delete
        let kindsToDelete = event.tags.compactMap { tag -> Int32? in
            guard tag.count >= 2 && tag[0] == "k" else { return nil }
            return Int32(tag[1])
        }
        
        // We only care about token events and quote events
        let relevantKinds: Set<Int32> = [7375, 7374]
        let shouldDeleteKinds = kindsToDelete.isEmpty || !Set(kindsToDelete).isDisjoint(with: relevantKinds)
        
        guard shouldDeleteKinds else {
            print("🗑️ Delete event doesn't target wallet kinds, ignoring")
            return
        }
        
        // Process each event to delete
        for eventId in eventIdsToDelete {
            print("🗑️ Processing deletion for event: \(eventId)")
            await deleteEventAndProofs(eventId, context: context)
        }
    }
    
    /// Process incoming nutzap events
    private func processNutzapEvent(_ event: NDKEvent, context: WalletEventContext) async throws {
        print("⚡️ Processing incoming nutzap event")
        try await context.wallet.processIncomingNutzapEvent(event)
    }
    
    // MARK: - Helper Methods
    
    /// Common function to handle deletion of an event and its proofs
    /// Used by both delete events (kind 5) and token events with del tags
    private func deleteEventAndProofs(_ eventId: String, context: WalletEventContext) async {
        // Mark event as deleted/superseded
        await context.eventManager.markEventDeleted(eventId)
        let current = await context.eventManager.getCurrentTokenEventIds()
        await context.eventManager.setCurrentTokenEventIds(current.subtracting([eventId]))
        
        // Mark proofs that are still owned by this event as deleted
        let deletedProofs = await context.proofStateManager.markProofsOwnedByEventAsDeleted(eventId)
        if !deletedProofs.isEmpty {
            print("🗑️ Marked \(deletedProofs.count) proofs as deleted from event: \(eventId)")
            
            // Update wallet's internal proofs array
            await context.wallet.updateProofsFromStateManager()
        }
    }
}

// MARK: - Context Structure (moved from WalletEventHandler.swift)

/// Context passed to event processor
struct WalletEventContext {
    let wallet: NIP60Wallet
    let proofStateManager: ProofStateManager
    let eventManager: WalletEventManager
    let p2pkManager: P2PKManager
    let signer: NDKSigner
}