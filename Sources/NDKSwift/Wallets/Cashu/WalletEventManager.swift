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
    private var supersededTokenEventIds: Set<String> = []
    
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
        signer: NDKSigner
    ) async throws -> [String] {
        // Create new token events for each mint
        var newEventIds: Set<String> = []
        
        for (mint, proofs) in availableProofsByMint {
            let token = CashuSwift.Token(
                proofs: [mint: proofs],
                unit: "sat"
            )
            
            let eventId = try await saveTokenEvent(
                token: token,
                signer: signer,
                deletedEventIds: nil
            )
            newEventIds.insert(eventId)
            print("WalletEventManager - Saved token event: \(eventId) for mint: \(mint)")
        }
        
        // Delete old token events that are no longer needed
        let eventsToDelete = currentTokenEventIds.subtracting(newEventIds)
        for eventId in eventsToDelete {
            try await createDeleteEvent(eventId: eventId, signer: signer)
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
        // Extract mint URL from token
        guard let mintURL = token.proofsByMint.keys.first else {
            throw NDKError.invalidRequest("Token has no mint URL")
        }
        
        // Get proofs from token
        let proofs = token.proofsByMint[mintURL] ?? []
        
        // Create NIP-60 compliant token event structure
        let nip60Token = NIP60TokenEvent(
            mint: mintURL,
            proofs: proofs,
            del: deletedEventIds
        )
        
        // Encode token to JSON
        let tokenData = try JSONEncoder().encode(nip60Token)
        guard let plaintext = String(data: tokenData, encoding: .utf8) else {
            throw NDKError.encodingError("Failed to encode token data")
        }
        
        let signerPubkey = try await signer.pubkey
        let recipient = NDKUser(pubkey: signerPubkey)
        let encryptedContent = try await signer.encrypt(
            recipient: recipient,
            value: plaintext,
            scheme: .nip44
        )
        
        // Create token event (kind 7375) - no relay tags for token events
        let tokenEvent = try await NDKEventBuilder()
            .content(encryptedContent)
            .kind(7375)
            .build(signer: signer)
        
        let publishedRelays = try await ndk.publish(tokenEvent, logRawJSON: true)
        print("WalletEventManager - Published token event \(tokenEvent.id) to \(publishedRelays.count) relays")
        
        return tokenEvent.id
    }
    
    /// Create a delete event for a token event
    private func createDeleteEvent(eventId: String, signer: NDKSigner) async throws {
        let deleteEvent = try await NDKEventBuilder()
            .content("Deleted token event")
            .kind(5) // Delete event
            .tags([
                ["e", eventId],
                ["k", "7375"] // Token event kind
            ])
            .build(signer: signer)
        
        try await ndk.publish(deleteEvent)
        deletedTokenEventIds.insert(eventId)
        print("WalletEventManager - Created delete event for token: \(eventId)")
    }
    
    // MARK: - Quote Event Management
    
    /// Save a quote event
    public func saveQuoteEvent(quote: CashuMintQuote, signer: NDKSigner) async throws {
        let quoteData = try JSONEncoder().encode(quote)
        guard let plaintext = String(data: quoteData, encoding: .utf8) else {
            throw NDKError.encodingError("Failed to encode quote data")
        }
        
        let signerPubkey = try await signer.pubkey
        let recipient = NDKUser(pubkey: signerPubkey)
        let encryptedContent = try await signer.encrypt(
            recipient: recipient,
            value: plaintext,
            scheme: .nip44
        )
        
        let quoteEvent = try await NDKEventBuilder()
            .content(encryptedContent)
            .kind(7374) // Quote event
            .build(signer: signer)
        
        try await ndk.publish(quoteEvent)
        print("WalletEventManager - Published quote event: \(quoteEvent.id)")
    }
    
    /// Delete a quote event
    public func deleteQuoteEvent(quoteId: String, signer: NDKSigner) async throws {
        let deleteEvent = try await NDKEventBuilder()
            .content("Quote expired or used")
            .kind(5) // Delete event
            .tags([
                ["e", quoteId],
                ["k", "7374"] // Quote event kind
            ])
            .build(signer: signer)
        
        try await ndk.publish(deleteEvent)
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
        // Build encrypted tags
        var encryptedTags: [[String]] = []
        encryptedTags.append(["direction", direction.rawValue])
        encryptedTags.append(["amount", String(amount)])
        
        // Add encrypted event references
        if let createdIds = createdEventIds {
            for eventId in createdIds {
                encryptedTags.append(["e", eventId, "", "created"])
            }
        }
        
        if let destroyedIds = destroyedEventIds {
            for eventId in destroyedIds {
                encryptedTags.append(["e", eventId, "", "destroyed"])
            }
        }
        
        // Build clear tags (unencrypted)
        var clearTags: [[String]] = []
        
        // Redeemed tags should be unencrypted according to NIP-60
        if let redeemedId = redeemedEventId {
            clearTags.append(["e", redeemedId, "", "redeemed"])
        }
        
        // Encode tags to JSON for encryption
        let tagsData = try JSONEncoder().encode(encryptedTags)
        guard let plaintext = String(data: tagsData, encoding: .utf8) else {
            throw NDKError.encodingError("Failed to encode spending history")
        }
        
        let signerPubkey = try await signer.pubkey
        let recipient = NDKUser(pubkey: signerPubkey)
        let encryptedContent = try await signer.encrypt(
            recipient: recipient,
            value: plaintext,
            scheme: .nip44
        )
        
        let historyEvent = try await NDKEventBuilder()
            .content(encryptedContent)
            .kind(7376) // Spending history
            .tags(clearTags)
            .build(signer: signer)
        
        try await ndk.publish(historyEvent)
        print("WalletEventManager - Created spending history event")
    }
    
    // MARK: - Event State Management
    
    /// Track a deleted event
    public func markEventDeleted(_ eventId: String) {
        deletedTokenEventIds.insert(eventId)
    }
    
    /// Track superseded events from del tags
    public func markEventsSuperseded(_ eventIds: [String]) {
        supersededTokenEventIds.formUnion(eventIds)
    }
    
    /// Check if an event should be filtered
    public func shouldFilterEvent(_ eventId: String) -> Bool {
        return deletedTokenEventIds.contains(eventId) || supersededTokenEventIds.contains(eventId)
    }
    
    /// Clear all tracked event IDs
    public func clearTrackedEvents() {
        currentTokenEventIds.removeAll()
        deletedTokenEventIds.removeAll()
        supersededTokenEventIds.removeAll()
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
    
    // MARK: - Wallet Configuration
    
    /// Save wallet configuration event
    public func saveWalletEvent(
        signer: NDKSigner,
        relays: [String]? = nil,
        walletTags: [[String]]
    ) async throws {
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
        
        let relayTags = await getRelayTags(providedRelays: relays, signer: signer)
        
        let builder = NDKEventBuilder()
            .content(encryptedContent)
            .kind(17375) // Wallet configuration
        
        // Add relay tags if available
        for tag in relayTags {
            _ = builder.tag(tag)
        }
        
        let walletEvent = try await builder.build(signer: signer)
        
        let publishedRelays = try await ndk.publish(walletEvent)
        lastWalletConfigTimestamp = walletEvent.createdAt
        print("WalletEventManager - Published wallet event \(walletEvent.id) to \(publishedRelays.count) relays")
    }
    
    /// Get relay tags for wallet events according to NIP-60
    private func getRelayTags(providedRelays: [String]?, signer: NDKSigner) async -> [[String]] {
        var relayTags: [[String]] = []
        
        if let providedRelays = providedRelays, !providedRelays.isEmpty {
            // Use provided relays
            for relay in providedRelays {
                relayTags.append(["relay", relay])
            }
        } else {
            // Use outbox write relays if available
            let signerPubkey = try? await signer.pubkey
            if let pubkey = signerPubkey {
                // Get user to fetch relay list
                let user = ndk.getUser(pubkey)
                
                // Try to fetch relay list (returns [NDKRelayInfo])
                do {
                    let relayInfoList: [NDKRelayInfo] = try await user.fetchRelayList()
                    let writeRelays = relayInfoList.filter { $0.write }
                    
                    for relay in writeRelays {
                        relayTags.append(["relay", relay.url])
                    }
                } catch {
                    // Failed to fetch relay list, continue without relay tags
                }
            }
        }
        
        return relayTags
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