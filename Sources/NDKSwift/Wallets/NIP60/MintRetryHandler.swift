import Foundation
import CashuSwift

/// Configuration for mint retry behavior
public struct MintRetryConfig {
    /// Base delay between retries in seconds
    let baseDelay: TimeInterval = NetworkConstants.retryBaseDelay
    
    /// Linear increment for each retry (5s, 10s, 15s, etc.)
    let delayIncrement: TimeInterval = NetworkConstants.retryDelayIncrement
    
    /// Maximum number of retry attempts
    let maxRetries: Int = NetworkConstants.maxMintRetries  // Total wait time: 5+10+15+20+25+30 = 105 seconds
    
    /// Maximum delay between retries
    let maxDelay: TimeInterval = NetworkConstants.maxRetryDelay
    
    public init() {}
}

/// Handles retry logic for failed mint operations
public actor MintRetryHandler {
    private let config = MintRetryConfig()
    
    /// Persistent storage for pending mint operations
    private var pendingMints: [String: PendingMintOperation] = [:]
    
    /// Retry minting tokens with linear backoff
    /// - Returns: Tuple of (proofs, wasUserNotified) - wasUserNotified indicates if user was shown the failure dialog
    public func retryMintWithBackoff(
        mintQuote: CashuSwift.Bolt11.MintQuote,
        mint: CashuSwift.Mint,
        amount: Int64,
        paymentProof: String? = nil,
        onRetryAttempt: ((Int, TimeInterval) -> Void)? = nil
    ) async throws -> (proofs: [CashuSwift.Proof], wasUserNotified: Bool) {
        
        let operationId = mintQuote.quote
        var attemptCount = 0
        
        // Store the pending operation
        let pendingOp = PendingMintOperation(
            quoteId: mintQuote.quote,
            mintURL: mint.url.absoluteString,
            amount: amount,
            invoice: mintQuote.request,
            paymentProof: paymentProof,
            createdAt: Date(),
            lastAttemptAt: Date()
        )
        pendingMints[operationId] = pendingOp
        
        defer {
            // Clean up on completion
            pendingMints[operationId] = nil
        }
        
        while attemptCount < config.maxRetries {
            attemptCount += 1
            
            // Calculate delay with linear backoff
            let delay: TimeInterval
            if attemptCount == 1 {
                delay = 0 // First attempt is immediate
            } else {
                let calculatedDelay = config.baseDelay + (config.delayIncrement * Double(attemptCount - 2))
                delay = min(calculatedDelay, config.maxDelay)
            }
            
            if delay > 0 {
                NDKLogger.log(.info, category: .wallet, "⏳ Mint retry attempt \(attemptCount)/\(config.maxRetries) - waiting \(Int(delay))s...")
                onRetryAttempt?(attemptCount, delay)
                
                try await Task.sleep(nanoseconds: UInt64(delay * Double(TimeConstants.nanosecondsPerSecond)))
            }
            
            do {
                NDKLogger.log(.info, category: .wallet, "🔄 Attempting to mint tokens (attempt \(attemptCount)/\(config.maxRetries))...")
                
                // Try to mint the tokens
                let (proofs, validDLEQ) = try await CashuSwift.issue(
                    for: mintQuote,
                    with: mint,
                    seed: nil
                )
                
                // Verify DLEQ if available
                if !validDLEQ {
                    throw NDKError.walletError(message: "DLEQ verification failed")
                }
                
                NDKLogger.log(.info, category: .wallet, "✅ Successfully minted \(proofs.count) proofs after \(attemptCount) attempts")
                return (proofs, false)
                
            } catch {
                NDKLogger.log(.warning, category: .wallet, "❌ Mint attempt \(attemptCount) failed: \(error)")
                
                // Check if error is recoverable
                if !isRecoverableError(error) {
                    throw error
                }
            }
        }
        
        // All retries exhausted
        NDKLogger.log(.error, category: .wallet, "🚨 All mint retry attempts failed for quote \(mintQuote.quote)")
        
        // Return empty proofs and indicate user should be notified
        return ([], true)
    }
    
    /// Check if an error is recoverable (worth retrying)
    private func isRecoverableError(_ error: Error) -> Bool {
        // Network errors, timeouts, and temporary mint issues are recoverable
        if let ndkError = error as? NDKError {
            switch ndkError {
            case .timeout, .connectionFailed:
                return true
            case .insufficientBalance:
                return false
            case .walletError, .paymentFailed:
                return false
            default:
                return true // Be optimistic for unknown errors
            }
        }
        
        // Check for common networking errors
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .cannotConnectToHost, .networkConnectionLost,
                 .notConnectedToInternet, .dataNotAllowed:
                return true
            default:
                return false
            }
        }
        
        // Default to recoverable for unknown errors
        return true
    }
    
    /// Get all pending mint operations (for recovery after app restart)
    public func getPendingMints() -> [PendingMintOperation] {
        Array(pendingMints.values)
    }
    
    /// Retry a specific pending mint operation
    public func retryPendingMint(
        _ operation: PendingMintOperation,
        mint: CashuSwift.Mint
    ) async throws -> [CashuSwift.Proof] {
        // Fetch the mint quote state to ensure it's marked as paid
        let mintQuote = try await CashuSwift.mintQuoteState(for: operation.quoteId, mint: mint)
        
        let (proofs, wasUserNotified) = try await retryMintWithBackoff(
            mintQuote: mintQuote,
            mint: mint,
            amount: operation.amount,
            paymentProof: operation.paymentProof
        )
        
        if wasUserNotified {
            throw MintRetryError.userNotificationRequired(operation)
        }
        
        return proofs
    }
}

/// Represents a pending mint operation that needs to be completed
public struct PendingMintOperation: Codable, Identifiable {
    public let id: String
    public let quoteId: String
    public let mintURL: String
    public let amount: Int64
    public let invoice: String
    public let paymentProof: String?
    public let createdAt: Date
    public let lastAttemptAt: Date
    
    public init(
        quoteId: String,
        mintURL: String,
        amount: Int64,
        invoice: String,
        paymentProof: String? = nil,
        createdAt: Date,
        lastAttemptAt: Date
    ) {
        self.id = quoteId
        self.quoteId = quoteId
        self.mintURL = mintURL
        self.amount = amount
        self.invoice = invoice
        self.paymentProof = paymentProof
        self.createdAt = createdAt
        self.lastAttemptAt = lastAttemptAt
    }
}

/// Errors specific to mint retry operations
public enum MintRetryError: LocalizedError {
    case userNotificationRequired(PendingMintOperation)
    
    public var errorDescription: String? {
        switch self {
        case .userNotificationRequired(let operation):
            return "Mint at \(operation.mintURL) failed to issue tokens after multiple attempts. User intervention required."
        }
    }
}