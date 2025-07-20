import Foundation
import CashuSwift

/// Consolidated processor for all wallet-related events
/// Replaces the multiple EventHandler structs with a single, cohesive component
actor WalletEventProcessor {
    
    /// Process a wallet event based on its kind
    func processEvent(_ event: NDKEvent, context: WalletEventContext) async {
        NDKLogger.shared.log(.debug, category: .wallet, "Wallet event received: kind=\(event.kind)")
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
                NDKLogger.shared.log(.warning, category: .wallet, "No handler for event kind \(event.kind)")
            }
        } catch {
            NDKLogger.shared.log(.error, category: .wallet, "Failed to process wallet event \(event.id): \(error)")
        }
    }
    
    // MARK: - Private Event Processing Methods
    
    /// Process token events
    private func processTokenEvent(_ event: NDKEvent, context: WalletEventContext) async throws {
        // First check if we should process this event
        if await context.eventManager.shouldFilterEvent(event.id) {
            NDKLogger.shared.log(.debug, category: .wallet, "Skipping deleted or superseded token event: \(event.id)")
            return
        }
        
        NDKLogger.shared.log(.debug, category: .wallet, "Processing token event: \(event.id)")
        NDKLogger.shared.log(.debug, category: .wallet, "Event Kind: \(event.kind)")
        NDKLogger.shared.log(.debug, category: .wallet, "Event Author: \(event.pubkey)")
        
        // Decrypt and process token
        let sender = NDKUser(pubkey: event.pubkey)
        let decryptedContent = try await context.signer.decrypt(
            sender: sender,
            value: event.content,
            scheme: .nip44
        )
        
        NDKLogger.shared.log(.debug, category: .wallet, "DECRYPTED TOKEN CONTENT:")
        NDKLogger.shared.log(.debug, category: .wallet, "Decrypted length: \(decryptedContent.count) characters")
        NDKLogger.shared.log(.debug, category: .wallet, "Decrypted content: \(decryptedContent)")
        NDKLogger.shared.log(.debug, category: .wallet, "Decrypted content (raw): \(String(describing: decryptedContent.data(using: .utf8)))")
        
        // Parse token data
        guard let tokenData = decryptedContent.data(using: .utf8),
              let nip60Token = JSONCoding.safeDecode(NIP60TokenEvent.self, from: tokenData) else {
            NDKLogger.shared.log(.error, category: .wallet, "Failed to parse NIP-60 token event data from decrypted content")
            throw NDKError.invalidContent("Failed to parse NIP-60 token event data")
        }
        
        NDKLogger.shared.log(.debug, category: .wallet, "PARSED TOKEN EVENT:")
        NDKLogger.shared.log(.debug, category: .wallet, "Mint URL: \(nip60Token.mint)")
        NDKLogger.shared.log(.debug, category: .wallet, "Proofs count: \(nip60Token.proofs.count)")
        NDKLogger.shared.log(.debug, category: .wallet, "Del tags count: \(nip60Token.del?.count ?? 0)")
        if let delTags = nip60Token.del {
            NDKLogger.shared.log(.debug, category: .wallet, "Del tags: \(delTags)")
        }
        for (index, proof) in nip60Token.proofs.enumerated() {
            NDKLogger.shared.log(.debug, category: .wallet, "Proof \(index): amount=\(proof.amount), keysetID=\(proof.keysetID), C=\(proof.C.prefix(20))...")
        }
        
        // Handle del tags - these events are no longer valid
        if let delIds = nip60Token.del {
            for delId in delIds {
                NDKLogger.shared.log(.debug, category: .wallet, "Processing del tag for event: \(delId)")
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
    }
    
    /// Process quote events
    private func processQuoteEvent(_ event: NDKEvent, context: WalletEventContext) async throws {
        NDKLogger.shared.log(.debug, category: .wallet, "Processing quote event")
        NDKLogger.shared.log(.debug, category: .wallet, "Event ID: \(event.id)")
        NDKLogger.shared.log(.debug, category: .wallet, "Event Kind: \(event.kind)")
        NDKLogger.shared.log(.debug, category: .wallet, "Event Author: \(event.pubkey)")
        NDKLogger.shared.log(.debug, category: .wallet, "Encrypted content length: \(event.content.count) characters")
        NDKLogger.shared.log(.debug, category: .wallet, "Encrypted content (first 100 chars): \(event.content.prefix(100))")
        
        // Decrypt content
        let sender = NDKUser(pubkey: event.pubkey)
        let decryptedContent = try await context.signer.decrypt(
            sender: sender,
            value: event.content,
            scheme: .nip44
        )
        
        NDKLogger.shared.log(.debug, category: .wallet, "DECRYPTED QUOTE CONTENT:")
        NDKLogger.shared.log(.debug, category: .wallet, "Decrypted length: \(decryptedContent.count) characters")
        NDKLogger.shared.log(.debug, category: .wallet, "Decrypted content: \(decryptedContent)")
        
        // Parse quote data
        guard let quoteData = decryptedContent.data(using: .utf8),
              let quote = JSONCoding.safeDecode(CashuMintQuote.self, from: quoteData) else {
            throw NDKError.invalidContent("Failed to parse quote event data")
        }
        
        NDKLogger.shared.log(.debug, category: .wallet, "Loaded quote: \(quote.quoteId) for \(quote.amount) sats")
        
        // Start tracking the quote for automatic minting
        await context.wallet.trackQuote(quote: quote, event: event)
    }
    
    /// Process spending history events
    
    /// Process delete events (kind 5)
    private func processDeleteEvent(_ event: NDKEvent, context: WalletEventContext) async throws {
        NDKLogger.shared.log(.debug, category: .wallet, "Processing delete event")
        
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
            NDKLogger.shared.log(.debug, category: .wallet, "Delete event doesn't target wallet kinds, ignoring")
            return
        }
        
        // Process each event to delete
        for eventId in eventIdsToDelete {
            NDKLogger.shared.log(.debug, category: .wallet, "Processing deletion for event: \(eventId)")
            await deleteEventAndProofs(eventId, context: context)
        }
    }
    
    /// Process incoming nutzap events
    private func processNutzapEvent(_ event: NDKEvent, context: WalletEventContext) async throws {
        NDKLogger.shared.log(.debug, category: .wallet, "Processing incoming nutzap event")
        try await context.wallet.processIncomingNutzap(event)
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
            NDKLogger.shared.log(.debug, category: .wallet, "Marked \(deletedProofs.count) proofs as deleted from event: \(eventId)")
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