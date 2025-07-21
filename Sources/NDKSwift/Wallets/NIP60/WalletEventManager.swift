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
    
    // Nutzap tracking
    private var nutzapEvents: [String: NutzapInfo] = [:] // eventId -> NutzapInfo
    private var redeemedNutzaps: Set<String> = [] // Set of redeemed nutzap event IDs
    
    // MARK: - Initialization
    
    public init(ndk: NDK) {
        self.ndk = ndk
    }
    
    // MARK: - Token Event Management
    
    /// Create or update token events based on calculated token changes
    public func updateTokenEvents(
        tokenChange: WalletTokenChange,
        proofStateManager: ProofStateManager,
        signer: NDKSigner
    ) async throws -> [String] {
        print("\n=== WalletEventManager.updateTokenEvents START ===")
        print("Tokens to delete: \(tokenChange.deletedTokenIds)")
        print("Proofs to save: \(tokenChange.saveProofs.count)")
        
        var newEventIds = Set<String>()
        
        // Keep existing token events that aren't being deleted
        for existingId in currentTokenEventIds {
            if !tokenChange.deletedTokenIds.contains(existingId) {
                newEventIds.insert(existingId)
            }
        }
        
        // Create deletion events for tokens being deleted
        if !tokenChange.deletedTokenIds.isEmpty {
            let deleteEvent = try await ndk.event()
                .kind(5) // Event deletion
                .content("")
                .tags([
                    ["k", String(7375)] // Cashu token kind
                ] + tokenChange.deletedTokenIds.map { ["e", $0] })
                .build(signer: signer)
            
            _ = try await ndk.publish(deleteEvent)
            
            // Create individual Kind 5 events for each deleted token
            for tokenId in tokenChange.deletedTokenIds {
                Task {
                    do {
                        try await self.createDeleteEvent(eventId: tokenId, signer: signer)
                    } catch {
                        print("⚠️ Failed to create Kind 5 deletion event for \(tokenId)")
                    }
                }
            }
        }
        
        // Create new token event if we have proofs to save
        if !tokenChange.saveProofs.isEmpty {
            // Group proofs by mint
            var proofsByMint: [String: [CashuSwift.Proof]] = [:]
            for proof in tokenChange.saveProofs {
                let mint = await proofStateManager.getMintForProof(proof) ?? "unknown"
                proofsByMint[mint, default: []].append(proof)
            }
            
            // Create a token event for each mint
            for (mint, proofs) in proofsByMint {
                let token = CashuSwift.Token(
                    proofs: [mint: proofs],
                    unit: "sat"
                )
                
                let eventId = try await saveTokenEvent(
                    token: token,
                    signer: signer,
                    deletedEventIds: Array(tokenChange.deletedTokenIds)
                )
                
                newEventIds.insert(eventId)
                
                // Update proof ownership
                await proofStateManager.updateProofOwnership(
                    proofs,
                    eventId: eventId,
                    timestamp: Timestamp.now
                )
            }
        }
        
        // Update tracking
        currentTokenEventIds = newEventIds
        
        print("=== WalletEventManager.updateTokenEvents END ===\n")
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
        
        let dataSource = NDKDataSource(
            ndk: ndk,
            filter: filter,
            maxAge: 0, // Always fresh for deletion
            cachePolicy: .networkOnly, // Need to confirm it exists
            subscriptionId: "nip60-delete-event"
        )
        
        let events = await dataSource.currentValue()
        if let eventToDelete = events.first {
            try await eventToDelete.delete(reason: "Deleted token event", signer: signer, ndk: ndk)
        }
        
        deletedTokenEventIds.insert(eventId)
        print("WalletEventManager - Created delete event for token: \(eventId)")
    }
    
    // MARK: - Quote Event Management
    
    /// Save a quote event and return its event ID
    @discardableResult
    public func saveQuoteEvent(quote: CashuMintQuote, signer: NDKSigner) async throws -> String {
        let quoteEvent = try await NDKCashuQuoteEvent.createAndPublish(
            ndk: ndk,
            quote: quote,
            signer: signer
        )
        return quoteEvent.event.id
    }
    
    /// Delete a quote event by its Nostr event ID
    public func deleteQuoteEvent(eventId: String, signer: NDKSigner) async throws {
        // First get the event to delete
        let filter = NDKFilter(ids: [eventId])
        
        let dataSource = NDKDataSource(
            ndk: ndk,
            filter: filter,
            maxAge: 0, // Always fresh for deletion
            cachePolicy: .networkOnly, // Need to confirm it exists
            subscriptionId: "nip60-delete-event"
        )
        
        let events = await dataSource.currentValue()
        if let quoteEvent = events.first {
            try await quoteEvent.delete(reason: "Quote expired or used", signer: signer, ndk: ndk)
        }
        
        print("WalletEventManager - Deleted quote event: \(eventId)")
    }
    
    // MARK: - Spending History
    
    /// Create spending history event
    public func createSpendingHistoryEvent(
        direction: SpendingDirection,
        amount: Int64,
        memo: String? = nil,
        destroyedEventIds: [String]? = nil,
        createdEventIds: [String]? = nil,
        redeemedEventId: String? = nil,
        signer: NDKSigner
    ) async throws {
        try await NDKCashuSpendingHistory.createAndPublish(
            ndk: ndk,
            direction: direction,
            amount: amount,
            memo: memo,
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
    
    // MARK: - Nutzap Tracking
    
    /// Track a nutzap event
    public func trackNutzap(_ event: NDKEvent) {
        // Extract amount from proof tags
        var totalAmount: Int64 = 0
        for tag in event.tags {
            if tag.count >= 2 && tag[0] == "proof" {
                if let proofData = tag[1].data(using: .utf8),
                   let proof = try? JSONCoding.decode(CashuSwift.Proof.self, from: proofData) {
                    totalAmount += Int64(proof.amount)
                }
            }
        }
        
        nutzapEvents[event.id] = NutzapInfo(
            eventId: event.id,
            sender: event.pubkey,
            amount: totalAmount,
            comment: event.content.isEmpty ? nil : event.content,
            createdAt: event.createdAt,
            isRedeemed: redeemedNutzaps.contains(event.id)
        )
    }
    
    /// Mark a nutzap as redeemed
    public func markNutzapRedeemed(_ eventId: String) {
        redeemedNutzaps.insert(eventId)
        if var info = nutzapEvents[eventId] {
            info.isRedeemed = true
            info.redeemedAt = Timestamp.now
            nutzapEvents[eventId] = info
        }
    }
    
    /// Get all nutzap events
    public func getNutzaps() -> [NutzapInfo] {
        return Array(nutzapEvents.values).sorted { $0.createdAt > $1.createdAt }
    }
    
    /// Get pending (unredeemed) nutzaps
    public func getPendingNutzaps() -> [NutzapInfo] {
        return nutzapEvents.values
            .filter { !$0.isRedeemed }
            .sorted { $0.createdAt > $1.createdAt }
    }
    
    /// Get redeemed nutzaps
    public func getRedeemedNutzaps() -> [NutzapInfo] {
        return nutzapEvents.values
            .filter { $0.isRedeemed }
            .sorted { $0.createdAt > $1.createdAt }
    }
    
    /// Check if a nutzap is redeemed
    public func isNutzapRedeemed(_ eventId: String) -> Bool {
        return redeemedNutzaps.contains(eventId)
    }
    
    /// Clear nutzap tracking (for wallet reload)
    public func clearNutzapTracking() {
        nutzapEvents.removeAll()
        redeemedNutzaps.removeAll()
    }
}

// MARK: - NutzapInfo

/// Information about a nutzap event
public struct NutzapInfo: Sendable {
    public let eventId: String
    public let sender: String
    public let amount: Int64
    public let comment: String?
    public let createdAt: Timestamp
    public var isRedeemed: Bool
    public var redeemedAt: Timestamp?
    
    public init(eventId: String, sender: String, amount: Int64, comment: String?, createdAt: Timestamp, isRedeemed: Bool, redeemedAt: Timestamp? = nil) {
        self.eventId = eventId
        self.sender = sender
        self.amount = amount
        self.comment = comment
        self.createdAt = createdAt
        self.isRedeemed = isRedeemed
        self.redeemedAt = redeemedAt
    }
}