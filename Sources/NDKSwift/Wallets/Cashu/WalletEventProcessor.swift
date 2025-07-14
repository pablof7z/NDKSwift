import Foundation
import CashuSwift

/// Consolidated processor for all wallet-related events
/// Replaces the multiple EventHandler structs with a single, cohesive component
actor WalletEventProcessor {
    
    /// Process a wallet event based on its kind
    func processEvent(_ event: NDKEvent, context: WalletEventContext) async {
        do {
            switch event.kind {
            case 17375:  // Wallet configuration
                try await processWalletConfigEvent(event, context: context)
            case 7375:   // Token event
                try await processTokenEvent(event, context: context)
            case 7374:   // Quote event
                try await processQuoteEvent(event, context: context)
            case 7376:   // Spending history
                try await processSpendingHistoryEvent(event, context: context)
            case 5:      // Delete event
                try await processDeleteEvent(event, context: context)
            case EventKind.nutzap:  // Incoming nutzap
                try await processNutzapEvent(event, context: context)
            default:
                print("⚠️ No handler for event kind \(event.kind)")
            }
        } catch {
            print("❌ Failed to process wallet event \(event.id): \(error)")
        }
    }
    
    // MARK: - Private Event Processing Methods
    
    /// Process wallet configuration events (kind 17375)
    private func processWalletConfigEvent(_ event: NDKEvent, context: WalletEventContext) async throws {
        print("🔧 Processing wallet configuration event")
        
        // Decrypt content
        let sender = NDKUser(pubkey: event.pubkey)
        let decryptedContent = try await context.signer.decrypt(
            sender: sender,
            value: event.content,
            scheme: .nip44
        )
        
        // Parse wallet tags
        guard let tagsData = decryptedContent.data(using: .utf8),
              let walletTags = try? JSONDecoder().decode([[String]].self, from: tagsData) else {
            throw NDKError.invalidContent("Failed to parse wallet configuration")
        }
        
        // Process wallet tags
        await context.wallet.processWalletTags(walletTags)
    }
    
    /// Process token events (kind 7375)
    private func processTokenEvent(_ event: NDKEvent, context: WalletEventContext) async throws {
        // First check if we should process this event
        if await context.eventManager.shouldFilterEvent(event.id) {
            print("⏭️ Skipping deleted or superseded token event: \(event.id)")
            return
        }
        
        print("💰 Processing token event: \(event.id)")
        
        // Decrypt and process token
        let sender = NDKUser(pubkey: event.pubkey)
        let decryptedContent = try await context.signer.decrypt(
            sender: sender,
            value: event.content,
            scheme: .nip44
        )
        
        // Parse token data
        guard let tokenData = decryptedContent.data(using: .utf8),
              let nip60Token = try? JSONDecoder().decode(NIP60TokenEvent.self, from: tokenData) else {
            throw NDKError.invalidContent("Failed to parse NIP-60 token event data")
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
            // Store proof if we have the corresponding keyset
            if await context.wallet.hasKeyset(proof.keysetID) {
                // Find mint for this proof
                if let mint = await context.wallet.findMintForKeyset(proof.keysetID) {
                    await context.proofStateManager.addProof(
                        proof, 
                        mint: mint, 
                        eventId: event.id,
                        timestamp: event.createdAt
                    )
                }
            }
        }
        
        await context.eventManager.addCurrentTokenEventId(event.id)
        
        // Update wallet's internal proofs array
        await context.wallet.updateProofsFromStateManager()
    }
    
    /// Process quote events (kind 7374)
    private func processQuoteEvent(_ event: NDKEvent, context: WalletEventContext) async throws {
        print("📜 Processing quote event")
        
        // Decrypt content
        let sender = NDKUser(pubkey: event.pubkey)
        let decryptedContent = try await context.signer.decrypt(
            sender: sender,
            value: event.content,
            scheme: .nip44
        )
        
        // Parse quote data
        guard let quoteData = decryptedContent.data(using: .utf8),
              let quote = try? JSONDecoder().decode(CashuMintQuote.self, from: quoteData) else {
            throw NDKError.invalidContent("Failed to parse quote event data")
        }
        
        print("📜 Loaded quote: \(quote.quoteId) for \(quote.amount) sats")
        
        // Store quote for future reference if needed
        // This could be used for resuming interrupted deposits
    }
    
    /// Process spending history events (kind 7376)
    private func processSpendingHistoryEvent(_ event: NDKEvent, context: WalletEventContext) async throws {
        print("📊 Processing spending history event")
        
        // Decrypt content
        let sender = NDKUser(pubkey: event.pubkey)
        let decryptedContent = try await context.signer.decrypt(
            sender: sender,
            value: event.content,
            scheme: .nip44
        )
        
        // Parse history data
        guard let historyData = decryptedContent.data(using: .utf8) else {
            throw NDKError.invalidContent("Failed to parse spending history")
        }
        
        // Process history entry
        // This could be used for transaction history display
        print("📊 Loaded spending history entry")
    }
    
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
        
        // We only care about token events (kind 7375) and quote events (kind 7374)
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
    let wallet: NDKCashuWallet
    let proofStateManager: ProofStateManager
    let eventManager: WalletEventManager
    let p2pkManager: P2PKManager
    let signer: NDKSigner
}