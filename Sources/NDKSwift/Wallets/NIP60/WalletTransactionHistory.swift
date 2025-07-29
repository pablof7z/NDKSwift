import Foundation
import CashuSwift

/// Manages wallet transaction history by merging multiple event types
/// Uses NDKDataSource for fully reactive event processing
public actor WalletTransactionHistory {
    // MARK: - Properties

    private let ndk: NDK
    private let signer: NDKSigner
    private let eventManager: WalletEventManager
    private weak var eventStream: NIP60WalletEventStream?

    // Transaction storage
    private var transactions: [String: WalletTransaction] = [:]  // transactionId -> transaction

    // Lookup indices for efficient transaction finding
    private var nutzapEventIndex: [String: String] = [:]         // nutzapId -> txId
    private var historyEventIndex: [String: String] = [:]        // historyId -> txId
    private var quoteIndex: [String: String] = [:]               // quoteId -> txId
    private var paymentHashIndex: [String: String] = [:]         // paymentHash -> txId
    private var recipientIndex: [String: [String]] = [:]         // recipientPubkey -> [txIds]

    // Data sources for reactive event processing
    private var historyDataSource: NDKDataSource<NDKEvent>?
    private var nutzapDataSource: NDKDataSource<NDKEvent>?
    private var observationTask: Task<Void, Never>?

    // Track user pubkey for filtering
    private var userPubkey: String?

    // MARK: - Initialization

    public init(ndk: NDK, signer: NDKSigner, eventManager: WalletEventManager, eventStream: NIP60WalletEventStream? = nil) {
        self.ndk = ndk
        self.signer = signer
        self.eventManager = eventManager
        self.eventStream = eventStream
    }

    deinit {
        observationTask?.cancel()
    }

    /// Set the event stream for real-time updates
    public func setEventStream(_ stream: NIP60WalletEventStream) {
        self.eventStream = stream
    }

    // MARK: - Lifecycle

    /// Start observing wallet events reactively
    public func startObserving() async throws {
        // Cancel any existing observation
        observationTask?.cancel()

        // Get user pubkey
        userPubkey = try await signer.pubkey
        guard let userPubkey = userPubkey else { return }

        // Create filters for wallet events
        let historyFilter = NDKFilter(
            authors: [userPubkey],
            kinds: [EventKind.cashuSpendingHistory]
        )

        let nutzapFilter = NDKFilter(
            kinds: [EventKind.nutzap],
            tags: [NostrConstants.TagName.pubkey: Set([userPubkey])]
        )

        // Create data sources
        historyDataSource = NDKDataSource(
            ndk: ndk,
            filter: historyFilter,
            maxAge: 0,  // Always fresh
            cachePolicy: .cacheWithNetwork,
            subscriptionId: "wallet-history"
        )

        nutzapDataSource = NDKDataSource(
            ndk: ndk,
            filter: nutzapFilter,
            maxAge: 0,
            cachePolicy: .cacheWithNetwork,
            subscriptionId: "wallet-nutzaps"
        )

        // Start observation task
        observationTask = Task { [weak self] in
            guard let self = self else { return }

            await withTaskGroup(of: Void.self) { group in
                // Observe spending history events
                group.addTask {
                    guard let dataSource = await self.historyDataSource else { return }
                    for await event in dataSource.events {
                        do {
                            try await self.processSpendingHistoryEvent(event)
                        } catch {
                            NDKLogger.log(.error, category: .wallet, "Error processing history event: \(error)")
                        }
                    }
                }

                // Observe nutzap events
                group.addTask {
                    guard let dataSource = await self.nutzapDataSource else { return }
                    for await event in dataSource.events {
                        await self.processNutzapEvent(event)
                    }
                }
            }
        }
    }

    /// Stop observing events
    public func stopObserving() {
        observationTask?.cancel()
        observationTask = nil
        historyDataSource = nil
        nutzapDataSource = nil
    }

    // MARK: - Public API

    /// Get all transactions sorted by date (newest first)
    public func getAllTransactions() -> [WalletTransaction] {
        return Array(transactions.values).sortedByDate()
    }

    /// Get transactions filtered by type
    public func getTransactions(types: Set<WalletTransactionType>) -> [WalletTransaction] {
        return Array(transactions.values)
            .filtered(by: types)
            .sortedByDate()
    }

    /// Get transactions filtered by direction
    public func getTransactions(direction: TransactionDirection) -> [WalletTransaction] {
        return Array(transactions.values)
            .filtered(by: direction)
            .sortedByDate()
    }

    /// Get a specific transaction by ID
    public func getTransaction(id: String) -> WalletTransaction? {
        return transactions[id]
    }

    /// Get transaction associated with a specific event
    public func getTransactionForEvent(eventId: String) -> WalletTransaction? {
        // Check all indices
        if let txId = nutzapEventIndex[eventId] {
            return transactions[txId]
        }
        if let txId = historyEventIndex[eventId] {
            return transactions[txId]
        }

        // Check if it's a token or quote event in any transaction
        for transaction in transactions.values {
            if transaction.events.allEventIds.contains(eventId) {
                return transaction
            }
        }

        return nil
    }

    /// Find transaction by nutzap event ID
    public func findTransactionForNutzap(eventId: String) -> WalletTransaction? {
        guard let txId = nutzapEventIndex[eventId] else { return nil }
        return transactions[txId]
    }

    /// Find transaction by spending history event ID
    public func findTransactionForHistory(eventId: String) -> WalletTransaction? {
        guard let txId = historyEventIndex[eventId] else { return nil }
        return transactions[txId]
    }

    /// Find transaction by quote ID
    public func findTransactionForQuote(quoteId: String) -> WalletTransaction? {
        guard let txId = quoteIndex[quoteId] else { return nil }
        return transactions[txId]
    }

    /// Find transactions by recipient
    public func findTransactionsForRecipient(pubkey: String) -> [WalletTransaction] {
        guard let txIds = recipientIndex[pubkey] else { return [] }
        return txIds.compactMap { transactions[$0] }
    }

    /// Clear all transaction history
    public func clear() {
        transactions.removeAll()
        clearIndices()
    }

    // MARK: - Transaction Creation

    /// Create a pending transaction (before any events exist)
    @discardableResult
    public func createPendingTransaction(
        type: WalletTransactionType,
        amount: Int64,
        direction: TransactionDirection? = nil,
        memo: String? = nil,
        mint: String? = nil,
        lookupKeys: TransactionLookupKeys = TransactionLookupKeys(),
        nutzapData: NutzapData? = nil,
        lightningData: LightningData? = nil
    ) -> WalletTransaction {
        let transaction = WalletTransaction(
            type: type,
            amount: amount,
            direction: direction ?? determineDirection(for: type),
            status: .pending,
            memo: memo,
            mint: mint,
            timestamp: Date(),
            events: TransactionEvents(),
            lookupKeys: lookupKeys,
            nutzapData: nutzapData,
            lightningData: lightningData
        )

        // Store and index
        storeTransaction(transaction)

        // Emit event
        eventStream?.yield(NIP60WalletEvent(type: .transactionAdded(transaction)))

        return transaction
    }

    // MARK: - Event Processing

    /// Process a spending history event (kind 7376)
    public func processSpendingHistoryEvent(_ event: NDKEvent) async throws {
        NDKLogger.log(.info, category: .wallet, "📥 Processing spending history event: \(event.id)")
        // Parse the spending history data
        let historyEvent = NDKCashuSpendingHistory(event: event)
        let historyData = try await historyEvent.decryptedHistoryData(signer: signer)

        NDKLogger.log(.info, category: .wallet, "📥 History data: \(historyData.direction?.rawValue ?? "unknown") \(historyData.amount) sats - \(historyData.memo ?? "no memo")")

        // Check if we already have a transaction for this event
        if findTransactionForHistory(eventId: event.id) != nil {
            NDKLogger.log(.debug, category: .wallet, "Spending history event already processed: \(event.id)")
            return
        }

        // For nutzaps, check if we have an existing transaction
        if let redeemedNutzapId = historyData.redeemedEventId {
            if let existingTx = findTransactionForNutzap(eventId: redeemedNutzapId) {
                // Update existing nutzap transaction
                updateTransactionWithSpendingHistory(
                    transactionId: existingTx.id,
                    historyEvent: event,
                    historyData: historyData
                )
                return
            }
        }

        // Check if we have a pending transaction that matches this history
        let matchingTx = findPendingTransactionForHistory(historyData)
        if let existingTx = matchingTx {
            // Update existing transaction
            updateTransactionWithSpendingHistory(
                transactionId: existingTx.id,
                historyEvent: event,
                historyData: historyData
            )
        } else {
            // Create new transaction from history
            let transaction = await createTransactionFromHistory(
                event: event,
                historyData: historyData
            )
            storeTransaction(transaction)
            NDKLogger.log(.info, category: .wallet, "📤 Emitting transactionAdded event for transaction: \(transaction.id)")
            eventStream?.yield(NIP60WalletEvent(type: .transactionAdded(transaction)))
        }
    }

    /// Process a nutzap event (kind 9321)
    public func processNutzapEvent(_ event: NDKEvent) async {
        // Check if we already have a transaction for this nutzap
        if findTransactionForNutzap(eventId: event.id) != nil {
            NDKLogger.log(.debug, category: .wallet, "Nutzap event already processed: \(event.id)")
            return
        }

        // Extract nutzap data
        var amount: Int64 = 0
        for tag in event.tags {
            if tag.count >= 2 && tag[0] == NostrConstants.TagName.proof {
                if let proofData = tag[1].data(using: .utf8) {
                    do {
                        let proof = try JSONCoding.decode(CashuSwift.Proof.self, from: proofData)
                        amount += Int64(proof.amount)
                    } catch {
                        NDKLogger.log(.warning, category: .wallet, "Failed to decode proof in transaction history: \(error.localizedDescription)")
                    }
                }
            }
        }

        // Create nutzap data
        let nutzapData = NutzapData(
            senderPubkey: event.pubkey,
            nutzapEventId: event.id,
            comment: event.content.nilIfEmpty
        )

        // Check nutzap status
        let nutzapInfo = await eventManager.getNutzapInfo(event.id)
        let status: TransactionStatus

        if let info = nutzapInfo {
            switch info.status {
            case .redeemed:
                status = .completed
            case .failed:
                status = .failed
            case .pending:
                status = .processing
            }
        } else {
            // If no info yet, check if it's been redeemed
            let isRedeemed = await eventManager.isNutzapRedeemed(event.id)
            status = isRedeemed ? .completed : .processing
        }

        // Create transaction
        let transaction = WalletTransaction(
            type: .nutzapReceived,
            amount: amount,
            direction: .incoming,
            status: status,
            memo: nutzapData.comment ?? "Nutzap received",
            mint: nil,  // Could extract from u tags if needed
            timestamp: Date(nostrTimestamp: event.createdAt),
            events: TransactionEvents(nutzapEventId: event.id),
            lookupKeys: TransactionLookupKeys(nutzapEventId: event.id),
            nutzapData: nutzapData
        )

        storeTransaction(transaction)
        eventStream?.yield(NIP60WalletEvent(type: .transactionAdded(transaction)))
    }

    /// Process sent nutzap events (from our own wallet)
    public func processSentNutzapEvent(_ event: NDKEvent) async {
        // Check if we already have a transaction
        if findTransactionForNutzap(eventId: event.id) != nil {
            return
        }

        // Extract recipient and amount
        var recipient: String?
        var amount: Int64 = 0

        for tag in event.tags {
            if tag.count >= 2 {
                switch tag[0] {
                case NostrConstants.TagName.pubkey:
                    recipient = tag[1]
                case NostrConstants.TagName.proof:
                    if let proofData = tag[1].data(using: .utf8) {
                        do {
                            let proof = try JSONCoding.decode(CashuSwift.Proof.self, from: proofData)
                            amount += Int64(proof.amount)
                        } catch {
                            NDKLogger.log(.warning, category: .wallet, "Failed to decode proof in nutzap transaction: \(error.localizedDescription)")
                        }
                    }
                default:
                    break
                }
            }
        }

        let nutzapData = NutzapData(
            recipientPubkey: recipient,
            nutzapEventId: event.id,
            comment: event.content.nilIfEmpty
        )

        let transaction = WalletTransaction(
            type: .nutzapSent,
            amount: amount,
            direction: .outgoing,
            status: .completed,
            memo: nutzapData.comment ?? "Nutzap sent",
            mint: nil,
            timestamp: Date(nostrTimestamp: event.createdAt),
            events: TransactionEvents(nutzapEventId: event.id),
            lookupKeys: TransactionLookupKeys(
                nutzapEventId: event.id,
                recipientPubkey: recipient
            ),
            nutzapData: nutzapData
        )

        storeTransaction(transaction)
        eventStream?.yield(NIP60WalletEvent(type: .transactionAdded(transaction)))
    }

    // MARK: - Transaction Updates

    /// Update transaction when a nutzap event is associated
    public func updateTransactionWithNutzap(transactionId: String, nutzapEvent: NDKEvent) {
        guard let transaction = transactions[transactionId] else { return }

        // Update events
        let updatedEvents = TransactionEvents(
            spendingHistoryId: transaction.events.spendingHistoryId,
            nutzapEventId: nutzapEvent.id,
            tokenEventIds: transaction.events.tokenEventIds,
            quoteEventId: transaction.events.quoteEventId
        )

        // Update status
        let newStatus: TransactionStatus = transaction.events.spendingHistoryId != nil ? .completed : .processing

        // Update transaction
        let updated = transaction.with(
            status: newStatus,
            events: updatedEvents
        )

        // Re-index with new event
        removeFromIndices(transaction)
        storeTransaction(updated)

        eventStream?.yield(NIP60WalletEvent(type: .transactionUpdated(updated)))
    }

    /// Update transaction when spending history is associated
    private func updateTransactionWithSpendingHistory(
        transactionId: String,
        historyEvent: NDKEvent,
        historyData: NDKCashuSpendingHistory.HistoryData
    ) {
        guard let transaction = transactions[transactionId] else { return }

        // Update events
        let updatedEvents = TransactionEvents(
            spendingHistoryId: historyEvent.id,
            nutzapEventId: transaction.events.nutzapEventId,
            tokenEventIds: historyData.createdEventIds + historyData.destroyedEventIds,
            quoteEventId: transaction.events.quoteEventId
        )

        // Update status
        let newStatus: TransactionStatus = .completed

        // Update memo if not set
        let updatedMemo = transaction.memo ?? historyData.memo ?? historyData.defaultMemo

        // Update transaction
        let updated = transaction.with(
            status: newStatus,
            events: updatedEvents,
            memo: updatedMemo
        )

        // Re-index with new event
        removeFromIndices(transaction)
        storeTransaction(updated)

        eventStream?.yield(NIP60WalletEvent(type: .transactionUpdated(updated)))
    }

    /// Update transaction status
    public func updateTransactionStatus(id: String, status: TransactionStatus) {
        guard let transaction = transactions[id] else { return }

        let updated = transaction.with(status: status)
        transactions[id] = updated

        eventStream?.yield(NIP60WalletEvent(type: .transactionUpdated(updated)))
    }

    /// Update transaction status for a nutzap event
    public func updateNutzapTransactionStatus(nutzapEventId: String, status: TransactionStatus, errorDetails: String? = nil) {
        guard let transactionId = nutzapEventIndex[nutzapEventId],
              let transaction = transactions[transactionId] else { return }

        let updated = transaction.with(status: status, errorDetails: errorDetails)
        transactions[transactionId] = updated

        eventStream?.yield(NIP60WalletEvent(type: .transactionUpdated(updated)))
    }

    /// Update an existing transaction
    public func updateTransaction(_ transaction: WalletTransaction) {
        // Remove old indices
        if let existing = transactions[transaction.id] {
            removeFromIndices(existing)
        }

        // Store updated transaction
        storeTransaction(transaction)

        eventStream?.yield(NIP60WalletEvent(type: .transactionUpdated(transaction)))
    }

    /// Add a manual transaction (for operations that don't have history events yet)
    public func addManualTransaction(_ transaction: WalletTransaction) {
        storeTransaction(transaction)
        eventStream?.yield(NIP60WalletEvent(type: .transactionAdded(transaction)))
    }

    // MARK: - Private Helpers

    /// Store transaction and update indices
    private func storeTransaction(_ transaction: WalletTransaction) {
        transactions[transaction.id] = transaction

        // Update indices
        if let nutzapId = transaction.lookupKeys.nutzapEventId {
            nutzapEventIndex[nutzapId] = transaction.id
        }
        if let historyId = transaction.lookupKeys.spendingHistoryId {
            historyEventIndex[historyId] = transaction.id
        }
        if let quoteId = transaction.lookupKeys.quoteId {
            quoteIndex[quoteId] = transaction.id
        }
        if let paymentHash = transaction.lookupKeys.paymentHash {
            paymentHashIndex[paymentHash] = transaction.id
        }
        if let recipient = transaction.lookupKeys.recipientPubkey {
            recipientIndex[recipient, default: []].append(transaction.id)
        }

        // Also index by event IDs in TransactionEvents
        if let nutzapId = transaction.events.nutzapEventId {
            nutzapEventIndex[nutzapId] = transaction.id
        }
        if let historyId = transaction.events.spendingHistoryId {
            historyEventIndex[historyId] = transaction.id
        }
    }

    /// Remove transaction from indices
    private func removeFromIndices(_ transaction: WalletTransaction) {
        // Remove from lookup key indices
        if let nutzapId = transaction.lookupKeys.nutzapEventId {
            nutzapEventIndex.removeValue(forKey: nutzapId)
        }
        if let historyId = transaction.lookupKeys.spendingHistoryId {
            historyEventIndex.removeValue(forKey: historyId)
        }
        if let quoteId = transaction.lookupKeys.quoteId {
            quoteIndex.removeValue(forKey: quoteId)
        }
        if let paymentHash = transaction.lookupKeys.paymentHash {
            paymentHashIndex.removeValue(forKey: paymentHash)
        }
        if let recipient = transaction.lookupKeys.recipientPubkey {
            recipientIndex[recipient]?.removeAll { $0 == transaction.id }
        }

        // Remove from event indices
        if let nutzapId = transaction.events.nutzapEventId {
            nutzapEventIndex.removeValue(forKey: nutzapId)
        }
        if let historyId = transaction.events.spendingHistoryId {
            historyEventIndex.removeValue(forKey: historyId)
        }
    }

    /// Clear all indices
    private func clearIndices() {
        nutzapEventIndex.removeAll()
        historyEventIndex.removeAll()
        quoteIndex.removeAll()
        paymentHashIndex.removeAll()
        recipientIndex.removeAll()
    }

    /// Find a pending transaction that matches the spending history
    private func findPendingTransactionForHistory(_ historyData: NDKCashuSpendingHistory.HistoryData) -> WalletTransaction? {
        // Try to match by amount and type
        let candidates = transactions.values.filter { tx in
            tx.status == .pending &&
            tx.amount == historyData.amount &&
            matchesTransactionType(tx.type, historyData: historyData)
        }

        // If we have exactly one match, return it
        if candidates.count == 1 {
            return candidates.first
        }

        // No unique match found with current matching criteria
        return nil
    }

    /// Check if transaction type matches history data
    private func matchesTransactionType(_ type: WalletTransactionType, historyData: NDKCashuSpendingHistory.HistoryData) -> Bool {
        switch historyData.transactionType {
        case .nutzap:
            return type == .nutzapReceived || type == .nutzapSent
        case .mint:
            return type == .mint
        case .melt:
            return type == .melt
        case .send:
            return type == .send
        case .receive:
            return type == .receive
        case .unknown:
            return true
        }
    }

    /// Create a transaction from spending history data
    private func createTransactionFromHistory(
        event: NDKEvent,
        historyData: NDKCashuSpendingHistory.HistoryData
    ) async -> WalletTransaction {
        let transactionType: WalletTransactionType
        let direction: TransactionDirection
        var nutzapData: NutzapData?

        // Determine transaction type
        switch historyData.transactionType {
        case .nutzap:
            transactionType = .nutzapReceived
            direction = .incoming
            if let redeemedId = historyData.redeemedEventId {
                // Try to get nutzap details
                let filter = NDKFilter(ids: [redeemedId])
                let dataSource = NDKDataSource(
                    ndk: ndk,
                    filter: filter,
                    maxAge: 0,
                    cachePolicy: .cacheWithNetwork,
                    subscriptionId: "nutzap-lookup-\(redeemedId)"
                )

                // Collect all nutzap events and use the first one (there should only be one per ID)
                let events = await dataSource.collect(timeout: NetworkConstants.timeoutDataCollectionShort)
                if let nutzapEvent = events.first {
                    nutzapData = NutzapData(
                        senderPubkey: nutzapEvent.pubkey,
                        nutzapEventId: redeemedId,
                        comment: nutzapEvent.content.nilIfEmpty
                    )
                }
            }

        case .mint:
            transactionType = .mint
            direction = .incoming

        case .melt:
            transactionType = .melt
            direction = .outgoing

        case .send:
            transactionType = .send
            direction = .outgoing

        case .receive:
            transactionType = .receive
            direction = .incoming

        case .unknown:
            // Try to infer from direction
            if let dir = historyData.direction {
                switch dir {
                case .in:
                    transactionType = .receive
                    direction = .incoming
                case .out:
                    transactionType = .send
                    direction = .outgoing
                }
            } else {
                transactionType = .receive
                direction = .incoming
            }
        }

        // Build lookup keys
        let lookupKeys = TransactionLookupKeys(
            nutzapEventId: historyData.redeemedEventId,
            spendingHistoryId: event.id
        )

        // Build events
        let events = TransactionEvents(
            spendingHistoryId: event.id,
            nutzapEventId: historyData.redeemedEventId,
            tokenEventIds: historyData.createdEventIds + historyData.destroyedEventIds
        )

        // Build ecash token data if token is present
        var ecashTokenData: EcashTokenData?
        if let token = historyData.token {
            // Parse token to get actual proof count
            var proofCount = 0
            if let cashuToken = try? token.deserializeToken() {
                for (_, proofs) in cashuToken.proofsByMint {
                    proofCount += proofs.count
                }
            }

            ecashTokenData = EcashTokenData(
                tokenString: token,
                proofCount: proofCount
            )
        }

        return WalletTransaction(
            type: transactionType,
            amount: historyData.amount,
            direction: direction,
            status: .completed,
            memo: historyData.memo ?? historyData.defaultMemo,
            mint: historyData.mint,
            timestamp: Date(nostrTimestamp: event.createdAt),
            events: events,
            lookupKeys: lookupKeys,
            nutzapData: nutzapData,
            ecashTokenData: ecashTokenData
        )
    }

    /// Determine direction based on transaction type
    private func determineDirection(for type: WalletTransactionType) -> TransactionDirection {
        switch type {
        case .mint, .receive, .nutzapReceived:
            return .incoming
        case .melt, .send, .nutzapSent:
            return .outgoing
        case .swap:
            return .neutral
        }
    }
}