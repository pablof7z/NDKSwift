import Foundation
import CashuSwift

/// Consolidated processor for all wallet-related events
/// Replaces the multiple EventHandler structs with a single, cohesive component
actor WalletEventProcessor {

    /// Process a wallet event based on its kind
    func processEvent(_ event: NDKEvent, context: WalletEventContext) async {
        NDKLogger.log(.debug, category: .wallet, "Wallet event received: kind=\(event.kind)")

        // Special logging for nutzaps
        if event.kind == EventKind.nutzap {
            NDKLogger.log(.debug, category: .wallet, "Nutzap event detected in processor")
        }

        do {
            switch event.kind {
            case EventKind.cashuWalletConfig:
                await context.wallet.processWalletConfiguration(event: event)
            case EventKind.cashuWalletBackup:
                // Backup events are handled separately during restore operations
                NDKLogger.log(.info, category: .wallet, "Backup event detected: \(event.id) - skipping regular processing")
            case EventKind.cashuToken:
                try await processTokenEvent(event, context: context)
            case EventKind.cashuQuote:
                try await processQuoteEvent(event, context: context)
            case EventKind.deletion:
                try await processDeleteEvent(event, context: context)
            case EventKind.nutzap:
                try await processNutzapEvent(event, context: context)
            case EventKind.cashuSpendingHistory:
                try await processSpendingHistoryEvent(event, context: context)
            default:
                NDKLogger.log(.warning, category: .wallet, "No handler for event kind \(event.kind)")
            }
        } catch {
            NDKLogger.log(.error, category: .wallet, "\(ErrorMessageConstants.failedTo("process wallet event \(event.id)")): \(error)")
        }
    }

    // MARK: - Private Event Processing Methods

    /// Process token events
    private func processTokenEvent(_ event: NDKEvent, context: WalletEventContext) async throws {
        // First check if we should process this event
        if await context.eventManager.shouldFilterEvent(event.id) {
            NDKLogger.log(.debug, category: .wallet, "Skipping deleted or superseded token event: \(event.id)")
            return
        }

        NDKLogger.log(.debug, category: .wallet, "Processing token event: \(event.id)")
        NDKLogger.log(.debug, category: .wallet, "Event Kind: \(event.kind)")

        // Decrypt and process token
        let sender = NDKUser(pubkey: event.pubkey)
        let decryptedContent = try await context.signer.decrypt(
            sender: sender,
            value: event.content,
            scheme: .nip44
        )

        // Parse token data
        guard let tokenData = decryptedContent.data(using: .utf8),
              let nip60Token = JSONCoding.safeDecode(NIP60TokenEvent.self, from: tokenData) else {
            NDKLogger.log(.error, category: .wallet, ErrorMessageConstants.failedTo("parse NIP-60 token event data from decrypted content"))
            throw NDKError.invalidContent(ErrorMessageConstants.failedTo("parse NIP-60 token event data"))
        }

        // Add proofs to state FIRST before processing deletions
        // This ensures that if the same proof appears in both the deleted event and this event,
        // it will be properly transferred to the new event
        NDKLogger.log(.info, category: .wallet, "📊 Adding \(nip60Token.proofs.count) proofs from token event \(event.id) for mint: \(nip60Token.mint)")
        var totalAmount: Int64 = 0
        for proof in nip60Token.proofs {
            await context.proofStateManager.addProof(
                proof,
                mint: nip60Token.mint,
                eventId: event.id,
                timestamp: event.createdAt
            )
            totalAmount += Int64(proof.amount)
            NDKLogger.log(.debug, category: .wallet, "  - Added proof C: \(proof.C), amount: \(proof.amount)")
        }
        NDKLogger.log(.info, category: .wallet, "📊 Total amount added from token event: \(totalAmount) sats")

        // Handle del tags AFTER adding new proofs - these events are no longer valid
        // But only delete proofs that weren't transferred to this new event
        if let delIds = nip60Token.del {
            NDKLogger.log(.info, category: .wallet, "📊 Processing \(delIds.count) del tags from token event")
            for delId in delIds {
                await deleteEventAndProofs(delId, context: context)
            }
        }

        // Log current balance after processing
        let currentBalance = await context.proofStateManager.getTotalBalance()
        NDKLogger.log(.info, category: .wallet, "💰 Current total balance after processing token event: \(currentBalance) sats")

        await context.eventManager.addCurrentTokenEventId(event.id)
    }

    /// Process quote events
    private func processQuoteEvent(_ event: NDKEvent, context: WalletEventContext) async throws {
        NDKLogger.log(.debug, category: .wallet, "Processing quote event")
        NDKLogger.log(.debug, category: .wallet, "Event ID: \(event.id)")
        NDKLogger.log(.debug, category: .wallet, "Event Kind: \(event.kind)")
        NDKLogger.log(.debug, category: .wallet, "Event Author: \(event.pubkey)")
        NDKLogger.log(.debug, category: .wallet, "Encrypted content length: \(event.content.count) characters")
        NDKLogger.log(.debug, category: .wallet, "Encrypted content (first \(StringConstants.DisplayFormatting.debugLogPreviewLength) chars): \(event.content.prefix(StringConstants.DisplayFormatting.debugLogPreviewLength))")

        // Decrypt content
        let sender = NDKUser(pubkey: event.pubkey)
        let decryptedContent = try await context.signer.decrypt(
            sender: sender,
            value: event.content,
            scheme: .nip44
        )

        NDKLogger.log(.debug, category: .wallet, "DECRYPTED QUOTE CONTENT:")
        NDKLogger.log(.debug, category: .wallet, "Decrypted length: \(decryptedContent.count) characters")
        NDKLogger.log(.debug, category: .wallet, "Decrypted content: \(decryptedContent)")

        // Parse quote data
        guard let quoteData = decryptedContent.data(using: .utf8),
              let quote = JSONCoding.safeDecode(CashuMintQuote.self, from: quoteData) else {
            throw NDKError.invalidContent(ErrorMessageConstants.failedTo("parse quote event data"))
        }

        NDKLogger.log(.debug, category: .wallet, "Loaded quote: \(quote.quoteId) for \(quote.amount) sats")

        // Start tracking the quote for automatic minting
        await context.wallet.trackQuote(quote: quote, event: event)
    }

    /// Process spending history events

    /// Process delete events (kind 5)
    private func processDeleteEvent(_ event: NDKEvent, context: WalletEventContext) async throws {

        // Find 'e' tags that reference events to delete
        let eventIdsToDelete = event.tags.eventIds

        // Find 'k' tags that specify kinds to delete
        let kindsToDelete = event.tags.tagValues(named: NostrConstants.TagName.kind).compactMap { Int32($0) }

        // We only care about token events and quote events
        let relevantKinds: Set<Int32> = [Int32(EventKind.cashuToken), Int32(EventKind.cashuQuote)]
        let shouldDeleteKinds = kindsToDelete.isEmpty || !Set(kindsToDelete).isDisjoint(with: relevantKinds)

        guard shouldDeleteKinds else {
            NDKLogger.log(.debug, category: .wallet, "Delete event doesn't target wallet kinds, ignoring")
            return
        }

        // Process each event to delete
        for eventId in eventIdsToDelete {
            NDKLogger.log(.debug, category: .wallet, "Processing deletion for event: \(eventId)")
            await deleteEventAndProofs(eventId, context: context)
        }
    }

    /// Process incoming nutzap events
    private func processNutzapEvent(_ event: NDKEvent, context: WalletEventContext) async throws {
        NDKLogger.log(.debug, category: .wallet, "Nutzap event received - ID: \(event.id), Author: \(event.pubkey)")

        // Track the nutzap in the event manager
        await context.eventManager.trackNutzap(event)

        // Transaction history will automatically pick up this event through NDKDataSource
        // No need to manually process it here

        try await context.wallet.processIncomingNutzap(event)
    }

    /// Process spending history events
    private func processSpendingHistoryEvent(_ event: NDKEvent, context: WalletEventContext) async throws {
        NDKLogger.log(.debug, category: .wallet, "Processing spending history event: \(event.id)")

        // Check for redeemed nutzap events in the clear tags
        for tag in event.tags {
            if tag.count >= 4 && tag[0] == NostrConstants.TagName.event && tag[3] == NostrConstants.Marker.redeemed {
                let redeemedNutzapId = tag[1]
                NDKLogger.log(.info, category: .wallet, "Found redeemed nutzap in history: \(redeemedNutzapId)")

                // Mark the nutzap as redeemed
                await context.eventManager.markNutzapRedeemed(redeemedNutzapId)
            }
        }

        // Transaction history will automatically pick up this event through NDKDataSource
        // No need to manually process it here
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
            NDKLogger.log(.debug, category: .wallet, "Marked \(deletedProofs.count) proofs as deleted from event: \(eventId)")
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