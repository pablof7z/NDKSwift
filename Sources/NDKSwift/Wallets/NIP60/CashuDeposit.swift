import Foundation
import CashuSwift

/// Represents the result of a deposit monitoring operation
public enum DepositMonitoringResult {
    case minted(proofs: [CashuSwift.Proof])
    case expired
    case cancelled
}

/// Errors specific to deposit mint failures
public enum DepositMintError: LocalizedError {
    case requiresUserIntervention(
        pendingOperation: PendingMintOperation,
        invoice: String
    )
    
    public var errorDescription: String? {
        switch self {
        case .requiresUserIntervention(let op, _):
            return "Failed to mint tokens at \(op.mintURL) after Lightning deposit was confirmed. Quote ID: \(op.quoteId)"
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .requiresUserIntervention:
            return "The mint confirmed receiving your Lightning payment but failed to issue tokens. You can retry minting or contact the mint operator."
        }
    }
}

/// Split an amount into powers of 2 for optimal denomination distribution
private func splitIntoBase2(_ amount: Int) -> [Int] {
    var result = [Int]()
    var remaining = amount
    var power = 0
    
    while remaining > 0 {
        if remaining & 1 == 1 {
            result.append(1 << power) // 2^power
        }
        remaining >>= 1
        power += 1
    }
    
    return result
}

/// Functions for handling Lightning deposits to Cashu mints
public enum CashuDeposit {
    
    // MARK: - Deposit Operations
    
    /// Request a mint quote for depositing via Lightning
    public static func requestMintQuote(
        amount: Int64,
        mintURL: String,
        mints: MintManager,
        eventManager: WalletEventManager,
        persistQuote: Bool = false,
        signer: NDKSigner? = nil
    ) async throws -> (quote: CashuMintQuote, eventId: String?) {
        // Get mint quote from mint manager
        let quoteResponse = try await mints.requestMintQuote(amount: amount, mintURL: mintURL)
        
        // Create our quote structure
        let quote = CashuMintQuote(
            quoteId: quoteResponse.quote,
            mintURL: mintURL,
            amount: amount,
            invoice: quoteResponse.request,
            expiry: Date().addingTimeInterval(TimeInterval(quoteResponse.expiry ?? 600)),
            requestedAt: Date()
        )
        
        // If persistQuote is true and signer is provided, save it as a NIP-60 quote event
        var eventId: String? = nil
        if persistQuote, let signer = signer {
            eventId = try await eventManager.saveQuoteEvent(quote: quote, signer: signer)
        }
        
        return (quote: quote, eventId: eventId)
    }
    
    /// Monitor deposit status for a mint quote
    /// 
    /// This method monitors a mint quote to check if the associated Lightning invoice has been paid.
    /// It uses progressive intervals that increase based on the quote's age (older quotes are checked less frequently).
    /// 
    /// - Parameters:
    ///   - quote: The mint quote to monitor
    ///   - quoteEventId: Optional ID of the Nostr event storing this quote (for cleanup after success)
    ///   - mints: MintManager instance for mint operations
    ///   - eventManager: WalletEventManager for event management
    ///   - signer: NDKSigner for signing events
    ///   - timeout: Maximum time to monitor before giving up (default: 600 seconds)
    ///   - quoteAge: How old the quote already is (affects check intervals)
    ///   - onProofsReceived: Callback to handle newly minted proofs
    ///   - manualCheckTrigger: Optional AsyncStream that allows manual triggering of status checks.
    ///                         Yield a value to this stream to immediately check the payment status
    ///                         instead of waiting for the automatic interval.
    /// 
    /// - Returns: An AsyncThrowingStream that yields DepositStatus updates
    /// 
    /// The monitoring uses dynamic intervals:
    /// - Base interval: 2 minutes
    /// - Increases by 1.5x for each hour the quote has existed
    /// - Maximum interval: 2 hours
    /// 
    /// When `manualCheckTrigger` is provided, the method will race between the automatic
    /// interval timer and the manual trigger, checking immediately when a value is yielded
    /// to the trigger stream.
    public static func monitorDeposit(
        quote: CashuMintQuote,
        quoteEventId: String? = nil,
        mints: MintManager,
        eventManager: WalletEventManager,
        signer: NDKSigner,
        timeout: TimeInterval = 600.0,
        quoteAge: TimeInterval = 0,
        onProofsReceived: @escaping ([CashuSwift.Proof]) async throws -> [String],
        manualCheckTrigger: AsyncStream<Void>? = nil
    ) -> AsyncThrowingStream<DepositStatus, Error> {
        return AsyncThrowingStream { continuation in
            let task = Task {
                let startTime = Date()
                
                do {
                    while Date().timeIntervalSince(startTime) < timeout {
                        // Check if Lightning invoice has been paid to the mint
                        do {
                            let proofs = try await checkAndMintTokens(
                                quote: quote,
                                mints: mints
                            )
                            
                            if !proofs.isEmpty {
                                // Quote successfully used - delete the quote event if we have its ID
                                if let quoteEventId = quoteEventId {
                                    Task {
                                        do {
                                            try await eventManager.deleteQuoteEvent(eventId: quoteEventId, signer: signer)
                                            NDKLogger.log(.info, category: .wallet, "✅ Cleaned up quote event \(quoteEventId) after successful mint")
                                        } catch {
                                            NDKLogger.log(.warning, category: .wallet, "⚠️ Failed to delete quote event \(quoteEventId): \(error)")
                                        }
                                    }
                                }
                                
                                // Let the wallet handle proof state updates
                                let createdEventIds = try await onProofsReceived(proofs)
                                
                                // Create history event for the lightning deposit
                                Task {
                                    do {
                                        try await eventManager.createSpendingHistoryEvent(
                                            direction: .in,
                                            amount: Int64(quote.amount),
                                            memo: StringConstants.Transactions.lightningDeposit,
                                            createdEventIds: createdEventIds,
                                            signer: signer
                                        )
                                        NDKLogger.log(.info, category: .wallet, "✅ Created NIP-60 history event for lightning deposit of \(quote.amount) sats")
                                    } catch {
                                        NDKLogger.log(.warning, category: .wallet, "⚠️ Failed to create history event for deposit: \(error)")
                                    }
                                }
                                
                                continuation.yield(.minted(proofs: proofs))
                                continuation.finish()
                                return
                            }
                        } catch {
                            // If it's a specific error indicating deposit not ready, continue polling
                            if case NDKError.walletError(let message) = error, message.contains("Deposit not ready") {
                                // Expected - deposit not ready yet, continue polling
                            } else if case CashuError.quoteNotPaid = error {
                                // Also handle CashuError.quoteNotPaid for compatibility
                                // Expected - deposit not ready yet, continue polling
                            } else {
                                throw error
                            }
                        }
                        
                        // Still pending
                        continuation.yield(.pending)
                        
                        // Calculate dynamic polling interval based on quote age using exponential backoff
                        let currentAge = quoteAge + Date().timeIntervalSince(startTime)
                        let hoursOld = currentAge / TimeConstants.hour
                        let baseInterval: TimeInterval = 120.0 // 2 minutes
                        let maxInterval: TimeInterval = 7200.0 // 2 hours
                        let interval = min(baseInterval * pow(1.5, hoursOld), maxInterval)
                        
                        NDKLogger.log(.debug, category: .wallet, "📜 Quote \(quote.quoteId) still pending - next check in \(Int(interval)) seconds")
                        
                        // Wait before next check, but allow manual trigger
                        if let manualCheckTrigger = manualCheckTrigger {
                            // Create a task that races between sleep and manual trigger
                            await withTaskGroup(of: Void.self) { group in
                                // Sleep task
                                group.addTask {
                                    try? await Task.sleep(nanoseconds: UInt64(interval * Double(TimeConstants.nanosecondsPerSecond)))
                                }
                                
                                // Manual trigger task
                                group.addTask {
                                    for await _ in manualCheckTrigger {
                                        NDKLogger.log(.debug, category: .wallet, "🔄 Manual check triggered...")
                                        break
                                    }
                                }
                                
                                // Wait for first to complete and cancel the other
                                await group.next()
                                group.cancelAll()
                            }
                        } else {
                            // No manual trigger - use regular sleep
                            try await Task.sleep(nanoseconds: UInt64(interval * Double(TimeConstants.nanosecondsPerSecond)))
                        }
                    }
                    
                    // Timeout reached - persist quote and mark as expired
                    // Only save if we don't already have an event ID (to avoid duplicates)
                    if quoteEventId == nil {
                        _ = try await eventManager.saveQuoteEvent(quote: quote, signer: signer)
                    }
                    continuation.yield(.expired)
                    continuation.finish()
                    
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
    
    /// Check if Lightning deposit has been made and mint tokens
    private static func checkAndMintTokens(
        quote: CashuMintQuote,
        mints: MintManager
    ) async throws -> [CashuSwift.Proof] {
        guard let mint = await mints.getMint(url: quote.mintURL) else {
            throw NDKError.noMintAvailable("Mint not found")
        }
        
        // Check mint quote status
        let statusResponse = try await CashuSwift.mintQuoteState(
            for: quote.quoteId,
            mint: mint
        )
        
        // Check if Lightning invoice has been paid
        guard statusResponse.paid == true else {
            throw NDKError.depositNotReady("Deposit not yet received by mint")
        }
        
        // Generate outputs for minting
        _ = splitIntoBase2(Int(quote.amount))
        
        // Create mint quote with request details for issue function
        var mintQuote = statusResponse
        mintQuote.requestDetail = CashuSwift.Bolt11.RequestMintQuote(
            unit: "sat",
            amount: Int(quote.amount)
        )
        
        // Use retry handler for minting with linear backoff
        let retryHandler = MintRetryHandler()
        let (proofs, wasUserNotified) = try await retryHandler.retryMintWithBackoff(
            mintQuote: mintQuote,
            mint: mint,
            amount: quote.amount,
            paymentProof: nil, // No payment proof for deposits
            onRetryAttempt: { attemptNumber, delay in
                NDKLogger.log(.info, category: .wallet, "⏳ Deposit mint retry attempt \(attemptNumber) in \(Int(delay))s...")
            }
        )
        
        // Check if user notification is required
        if wasUserNotified && proofs.isEmpty {
            _ = PendingMintOperation(
                quoteId: quote.quoteId,
                mintURL: quote.mintURL,
                amount: quote.amount,
                invoice: quote.invoice,
                paymentProof: nil,
                createdAt: Date(),
                lastAttemptAt: Date()
            )
            
            throw NDKError.paymentFailed(reason: "Mint operation requires user intervention after reaching retry limit")
        }
        
        guard !proofs.isEmpty else {
            throw NDKError.paymentFailed(reason: "Failed to mint tokens after deposit was confirmed")
        }
        
        return proofs
    }
    
    /// Check and mint tokens for an existing quote (one-shot operation)
    public static func checkAndMintTokens(
        quoteId: String,
        mintURL: String,
        amount: Int64,
        mints: MintManager
    ) async throws -> [CashuSwift.Proof] {
        let quote = CashuMintQuote(
            quoteId: quoteId,
            mintURL: mintURL,
            amount: amount,
            invoice: "", // Not needed for checking
            expiry: Date(), // Not needed for checking
            requestedAt: Date()
        )
        
        return try await checkAndMintTokens(quote: quote, mints: mints)
    }
}