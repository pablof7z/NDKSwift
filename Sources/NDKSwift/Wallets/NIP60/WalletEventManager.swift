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
        signer: NDKSigner,
        relays: [String]
    ) async throws -> [String] {
        NDKLogger.log(.debug, category: .wallet, "=== WalletEventManager.updateTokenEvents START ===")
        NDKLogger.log(.debug, category: .wallet, "Tokens to delete: \(tokenChange.deletedTokenIds)")
        NDKLogger.log(.debug, category: .wallet, "Proofs to save: \(tokenChange.saveProofs.count)")

        var newEventIds = Set<String>()

        // Keep existing token events that aren't being deleted
        for existingId in currentTokenEventIds {
            if !tokenChange.deletedTokenIds.contains(existingId) {
                newEventIds.insert(existingId)
            }
        }

        // Create deletion events for tokens being deleted
        if !tokenChange.deletedTokenIds.isEmpty {
            let deleteEvent = try await NDKEventBuilder(ndk: ndk)
                .kind(EventKind.deletion) // Event deletion
                .content("")
                .tags([
                    ["k", String(7375)] // Cashu token kind
                ] + tokenChange.deletedTokenIds.map { ["e", $0] })
                .build(signer: signer)

            let publishedRelays = try await ndk.publish(deleteEvent, to: Set(relays))
            NDKLogger.log(.debug, category: .wallet, "🗑️ Token deletion event published to \(publishedRelays.count) relays")

            // Create individual Kind 5 events for each deleted token
            for tokenId in tokenChange.deletedTokenIds {
                Task {
                    do {
                        try await self.createDeleteEvent(eventId: tokenId, signer: signer)
                    } catch {
                        NDKLogger.log(.warning, category: .wallet, "⚠️ Failed to create Kind 5 deletion event for \(tokenId): \(error)")
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
                    deletedEventIds: Array(tokenChange.deletedTokenIds),
                    relays: relays
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

        NDKLogger.log(.debug, category: .wallet, "=== WalletEventManager.updateTokenEvents END ===")
        return Array(newEventIds)
    }

    /// Save individual token event
    private func saveTokenEvent(
        token: CashuSwift.Token,
        signer: NDKSigner,
        deletedEventIds: [String]?,
        relays: [String]
    ) async throws -> String {
        let tokenEvent = try await NDKCashuTokenEvent.create(
            ndk: ndk,
            token: token,
            signer: signer,
            deletedEventIds: deletedEventIds
        )
        
        // Publish to specific relays
        _ = try await ndk.publish(tokenEvent.event, to: Set(relays))
        
        return tokenEvent.event.id
    }

    /// Create a delete event for a token event
    private func createDeleteEvent(eventId: String, signer: NDKSigner) async throws {
        // First get the event to delete
        let filter = NDKFilter(ids: [eventId])

        let dataSource = NDKSubscription(
            ndk: ndk,
            filter: filter,
            maxAge: 0, // Always fresh for deletion
            cachePolicy: .networkOnly, // Need to confirm it exists
            subscriptionId: "nip60-delete-event"
        )

        // Collect all matching events to ensure we find it
        let events = await dataSource.collect(timeout: NetworkConstants.timeoutDataCollectionShort)
        if let eventToDelete = events.first {
            try await eventToDelete.delete(reason: "Deleted token event", signer: signer, ndk: ndk)
        }

        deletedTokenEventIds.insert(eventId)
        NDKLogger.log(.debug, category: .wallet, "WalletEventManager - Created delete event for token: \(eventId)")
    }

    // MARK: - Quote Event Management

    /// Save a quote event and return its event ID
    @discardableResult
    public func saveQuoteEvent(quote: CashuMintQuote, signer: NDKSigner, relays: [String]) async throws -> String {
        let quoteEvent = try await NDKCashuQuoteEvent.create(
            ndk: ndk,
            quote: quote,
            signer: signer
        )
        
        // Publish to specific relays
        _ = try await ndk.publish(quoteEvent.event, to: Set(relays))
        
        return quoteEvent.event.id
    }

    /// Delete a quote event by its Nostr event ID
    public func deleteQuoteEvent(eventId: String, signer: NDKSigner) async throws {
        // First get the event to delete
        let filter = NDKFilter(ids: [eventId])

        let dataSource = NDKSubscription(
            ndk: ndk,
            filter: filter,
            maxAge: 0, // Always fresh for deletion
            cachePolicy: .networkOnly, // Need to confirm it exists
            subscriptionId: "nip60-delete-event"
        )

        // Collect all matching events to ensure we find it
        let events = await dataSource.collect(timeout: NetworkConstants.timeoutDataCollectionShort)
        if let quoteEvent = events.first {
            try await quoteEvent.delete(reason: "Quote expired or used", signer: signer, ndk: ndk)
        }

        NDKLogger.log(.debug, category: .wallet, "WalletEventManager - Deleted quote event: \(eventId)")
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
        token: String? = nil,
        signer: NDKSigner,
        relays: [String]
    ) async throws {
        NDKLogger.log(.info, category: .wallet, "📝 Creating spending history event: \(direction) \(amount) sats - \(memo ?? "no memo")")
        let historyEvent = try await NDKCashuSpendingHistory.create(
            ndk: ndk,
            direction: direction,
            amount: amount,
            memo: memo,
            destroyedEventIds: destroyedEventIds,
            createdEventIds: createdEventIds,
            redeemedEventId: redeemedEventId,
            token: token,
            signer: signer
        )
        
        // Publish to specific relays
        _ = try await ndk.publish(historyEvent.event, to: Set(relays))
        
        NDKLogger.log(.info, category: .wallet, "✅ Spending history event created and published")
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
        clearNutzapTracking()
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

    // MARK: - Nutzap Tracking

    /// Track a nutzap event
    public func trackNutzap(_ event: NDKEvent) {
        // Extract amount and mint from proof tags
        var totalAmount: Int64 = 0
        var mint = ""

        for tag in event.tags {
            if tag.count >= 2 && tag[0] == NostrConstants.TagName.proof {
                if let proofData = tag[1].data(using: .utf8),
                   let proof = try? JSONCoding.decode(CashuSwift.Proof.self, from: proofData) {
                    totalAmount += Int64(proof.amount)
                }
            }
            // Extract mint from tags
            if tag.count >= 2 && tag[0] == NostrConstants.TagName.url {
                mint = tag[1]
            }
        }

        // Determine initial status based on whether it was already redeemed
        let status: NutzapRedemptionStatus = redeemedNutzaps.contains(event.id)
            ? .redeemed(at: event.createdAt, proofsCount: 0)
            : .pending

        nutzapEvents[event.id] = NutzapInfo(
            eventId: event.id,
            event: event,
            sender: event.pubkey,
            amount: totalAmount,
            comment: event.content.nilIfEmpty,
            createdAt: event.createdAt,
            mint: mint,
            status: status
        )
    }

    /// Mark a nutzap as redeemed
    public func markNutzapRedeemed(_ eventId: String, proofsCount: Int = 0) {
        redeemedNutzaps.insert(eventId)
        if var info = nutzapEvents[eventId] {
            info.status = .redeemed(at: Timestamp.now, proofsCount: proofsCount)
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

    /// Update nutzap status
    public func updateNutzapStatus(_ eventId: String, status: NutzapRedemptionStatus) {
        if var info = nutzapEvents[eventId] {
            info.status = status
            // Update redeemed set if needed
            if case .redeemed = status {
                redeemedNutzaps.insert(eventId)
            }
            nutzapEvents[eventId] = info
        }
    }

    /// Update nutzap redemption attempt timestamp
    public func updateNutzapAttemptTimestamp(_ eventId: String) {
        if var info = nutzapEvents[eventId] {
            info.latestRedemptionAttemptTimestamp = Timestamp.now
            nutzapEvents[eventId] = info
        }
    }

    /// Get specific nutzap info
    public func getNutzapInfo(_ eventId: String) -> NutzapInfo? {
        return nutzapEvents[eventId]
    }

    /// Get nutzaps by status filter
    public func getNutzapsByStatus(_ filter: NutzapStatusFilter) -> [NutzapInfo] {
        let filtered: [NutzapInfo]

        switch filter {
        case .all:
            filtered = Array(nutzapEvents.values)
        case .pending:
            filtered = nutzapEvents.values.filter { nutzap in
                if case .pending = nutzap.status { return true }
                return false
            }
        case .redeemed:
            filtered = nutzapEvents.values.filter { nutzap in
                if case .redeemed = nutzap.status { return true }
                return false
            }
        case .failed:
            filtered = nutzapEvents.values.filter { nutzap in
                if case .failed = nutzap.status { return true }
                return false
            }
        case .retryableFailed:
            filtered = nutzapEvents.values.filter { nutzap in
                if case .failed(let error, _, _) = nutzap.status {
                    return error.isRetryable
                }
                return false
            }
        }

        return filtered.sorted { $0.createdAt > $1.createdAt }
    }

    /// Get failed nutzaps
    public func getFailedNutzaps() -> [NutzapInfo] {
        return getNutzapsByStatus(.failed)
    }
}

// MARK: - NutzapInfo

/// Information about a nutzap event with enhanced status tracking
public struct NutzapInfo: Sendable, Codable {
    public let eventId: String
    public let event: NDKEvent // Store full event for retries
    public let sender: String
    public let amount: Int64
    public let comment: String?
    public let createdAt: Timestamp
    public let mint: String
    public var status: NutzapRedemptionStatus
    public var latestRedemptionAttemptTimestamp: Timestamp?

    public init(
        eventId: String,
        event: NDKEvent,
        sender: String,
        amount: Int64,
        comment: String?,
        createdAt: Timestamp,
        mint: String,
        status: NutzapRedemptionStatus = .pending,
        latestRedemptionAttemptTimestamp: Timestamp? = nil
    ) {
        self.eventId = eventId
        self.event = event
        self.sender = sender
        self.amount = amount
        self.comment = comment
        self.createdAt = createdAt
        self.mint = mint
        self.status = status
        self.latestRedemptionAttemptTimestamp = latestRedemptionAttemptTimestamp
    }

    // For backward compatibility
    public var isRedeemed: Bool {
        if case .redeemed = status {
            return true
        }
        return false
    }

    // For backward compatibility
    public var redeemedAt: Timestamp? {
        if case .redeemed(let at, _) = status {
            return at
        }
        return nil
    }
}