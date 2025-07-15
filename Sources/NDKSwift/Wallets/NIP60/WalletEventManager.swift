import Foundation
import CashuSwift

/// Spending direction for history events
public enum SpendingDirection: String {
    case `in` = "in"   // Received funds
    case out = "out"   // Sent funds
}

/// Manages wallet event operations for NIP-60 Cashu wallets
/// This includes creating, deleting, and managing token events, quote events, and spending history
public actor WalletEventManager {
    // MARK: - Properties
    
    private let ndk: NDK
    private var currentTokenEventIds: Set<String> = []
    private var deletedTokenEventIds: Set<String> = []
    
    // Wallet event tracking
    private var lastWalletConfigTimestamp: Timestamp = 0
    
    // MARK: - Initialization
    
    public init(ndk: NDK) {
        self.ndk = ndk
    }
    
    // MARK: - Token Event Management
    
    /// Create or update token events based on proof state changes
    public func updateTokenEvents(
        availableProofsByMint: [String: [CashuSwift.Proof]],
        proofStateManager: ProofStateManager,
        signer: NDKSigner
    ) async throws -> [String] {
        // Create new token events for each mint
        var newEventIds: Set<String> = []
        
        for (mint, proofs) in availableProofsByMint {
            // Get the previous owner event IDs for these proofs
            // These are the token events that will be superseded by the new token
            let previousOwnerEventIds = await proofStateManager.getOwnerEventIds(for: proofs)
            
            let token = CashuSwift.Token(
                proofs: [mint: proofs],
                unit: "sat"
            )
            
            // Convert Set to Array and filter out any that might be in currentTokenEventIds
            // to avoid including events that are still valid
            let deletedEventIds = Array(previousOwnerEventIds.intersection(currentTokenEventIds))
            
            let eventId = try await saveTokenEvent(
                token: token,
                signer: signer,
                deletedEventIds: deletedEventIds.isEmpty ? nil : deletedEventIds
            )
            newEventIds.insert(eventId)
            print("WalletEventManager - Saved token event: \(eventId) for mint: \(mint)")
            if !deletedEventIds.isEmpty {
                print("  With del tags for events: \(deletedEventIds)")
            }
            
            // Update proof ownership to this event
            // We don't have the timestamp here, but these are new events we're creating
            // so they will have the current timestamp which should be newer than any existing
            await proofStateManager.updateProofOwnership(proofs, eventId: eventId, timestamp: Timestamp(Date().timeIntervalSince1970))
        }
        
        // Delete old token events that are no longer needed
        // Note: We now use explicit del tags in new tokens, so we might not need
        // to create separate deletion events for all cases. However, we keep this
        // for tokens that have no proofs left (completely spent)
        let eventsToDelete = currentTokenEventIds.subtracting(newEventIds)
        for eventId in eventsToDelete {
            // Check if this event was already included in del tags
            var alreadyDeleted = false
            for (_, proofs) in availableProofsByMint {
                let previousOwners = await proofStateManager.getOwnerEventIds(for: proofs)
                if previousOwners.contains(eventId) {
                    alreadyDeleted = true
                    break
                }
            }
            
            // Only create explicit delete event if not already handled via del tags
            if !alreadyDeleted {
                try await createDeleteEvent(eventId: eventId, signer: signer)
            }
        }
        
        // Update tracking
        currentTokenEventIds = newEventIds
        
        return Array(newEventIds)
    }
    
    /// Save individual token event
    private func saveTokenEvent(
        token: CashuSwift.Token,
        signer: NDKSigner,
        deletedEventIds: [String]?
    ) async throws -> String {
        let tokenEvent = try await NDKCashuTokenEvent.createAndPublish(
            ndk: ndk,
            token: token,
            signer: signer,
            deletedEventIds: deletedEventIds
        )
        return tokenEvent.event.id
    }
    
    /// Create a delete event for a token event
    private func createDeleteEvent(eventId: String, signer: NDKSigner) async throws {
        // First get the event to delete
        let filter = NDKFilter(ids: [eventId])
        
        if let eventToDelete = try await ndk.fetchEvent(filter) {
            try await eventToDelete.delete(ndk: ndk, reason: "Deleted token event", signer: signer)
        }
        
        deletedTokenEventIds.insert(eventId)
        print("WalletEventManager - Created delete event for token: \(eventId)")
    }
    
    // MARK: - Quote Event Management
    
    /// Save a quote event
    public func saveQuoteEvent(quote: CashuMintQuote, signer: NDKSigner) async throws {
        try await NDKCashuQuoteEvent.createAndPublish(
            ndk: ndk,
            quote: quote,
            signer: signer
        )
    }
    
    /// Delete a quote event
    public func deleteQuoteEvent(quoteId: String, signer: NDKSigner) async throws {
        // First get the event to delete
        let filter = NDKFilter(ids: [quoteId])
        
        if let quoteEvent = try await ndk.fetchEvent(filter) {
            try await quoteEvent.delete(ndk: ndk, reason: "Quote expired or used", signer: signer)
        }
        
        print("WalletEventManager - Deleted quote event: \(quoteId)")
    }
    
    // MARK: - Spending History
    
    /// Create spending history event
    public func createSpendingHistoryEvent(
        direction: SpendingDirection,
        amount: Int64,
        destroyedEventIds: [String]? = nil,
        createdEventIds: [String]? = nil,
        redeemedEventId: String? = nil,
        signer: NDKSigner
    ) async throws {
        try await NDKCashuSpendingHistory.createAndPublish(
            ndk: ndk,
            direction: direction,
            amount: amount,
            destroyedEventIds: destroyedEventIds,
            createdEventIds: createdEventIds,
            redeemedEventId: redeemedEventId,
            signer: signer
        )
    }
    
    // MARK: - Event State Management
    
    /// Track a deleted event
    public func markEventDeleted(_ eventId: String) {
        deletedTokenEventIds.insert(eventId)
    }
    
    /// Check if an event should be filtered
    public func shouldFilterEvent(_ eventId: String) -> Bool {
        return deletedTokenEventIds.contains(eventId)
    }
    
    /// Clear all tracked event IDs
    public func clearTrackedEvents() {
        currentTokenEventIds.removeAll()
        deletedTokenEventIds.removeAll()
    }
    
    /// Get current token event IDs
    public func getCurrentTokenEventIds() -> Set<String> {
        return currentTokenEventIds
    }
    
    /// Update current token event IDs
    public func setCurrentTokenEventIds(_ eventIds: Set<String>) {
        currentTokenEventIds = eventIds
    }
    
    /// Add a current token event ID
    public func addCurrentTokenEventId(_ eventId: String) {
        currentTokenEventIds.insert(eventId)
    }
    
    /// Get the last wallet configuration timestamp
    public func getLastWalletConfigTimestamp() -> Timestamp {
        return lastWalletConfigTimestamp
    }
    
    /// Update the last wallet configuration timestamp
    public func updateLastWalletConfigTimestamp(_ timestamp: Timestamp) {
        lastWalletConfigTimestamp = timestamp
    }
}