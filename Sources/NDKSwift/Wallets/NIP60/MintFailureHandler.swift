import Foundation

/// UI-level handler for mint failures that require user intervention
/// This is a reference implementation showing how apps should handle mint failures
public protocol MintFailureHandlerDelegate: AnyObject {
    /// Called when a mint fails after receiving payment
    /// - Parameters:
    ///   - operation: The pending mint operation that failed
    ///   - error: The specific error that occurred
    /// - Returns: User's decision on how to proceed
    func handleMintFailure(
        operation: PendingMintOperation,
        error: Error
    ) async -> MintFailureUserDecision
}

/// User's decision on how to handle a mint failure
public enum MintFailureUserDecision {
    /// Retry the mint operation
    case retry
    /// Blacklist the mint and don't retry
    case blacklistMint
    /// Cancel without blacklisting
    case cancel
}

/// Example implementation of mint failure handling
public actor MintFailureHandler {
    private weak var delegate: MintFailureHandlerDelegate?
    private let wallet: NIP60Wallet
    private let mints: MintManager
    
    public init(wallet: NIP60Wallet, mints: MintManager, delegate: MintFailureHandlerDelegate? = nil) {
        self.wallet = wallet
        self.mints = mints
        self.delegate = delegate
    }
    
    /// Handle a mint failure error from payment operations
    public func handlePaymentError(_ error: Error) async throws {
        // Check if this is a mint failure that requires user intervention
        if case MintFailureError.requiresUserIntervention(let operation, _, _, _, let paymentProof) = error {
            try await handleMintFailure(operation, paymentProof: paymentProof)
        } else if case DepositMintError.requiresUserIntervention(let operation, _) = error {
            try await handleDepositFailure(operation)
        } else {
            // Re-throw other errors
            throw error
        }
    }
    
    /// Handle cross-mint transfer failure
    private func handleMintFailure(_ operation: PendingMintOperation, paymentProof: String) async throws {
        guard let delegate = delegate else {
            NDKLogger.log(.error, category: .wallet, "No delegate set to handle mint failure")
            throw NDKError.notConfigured("No mint failure handler delegate")
        }
        
        // Get user's decision
        let decision = await delegate.handleMintFailure(
            operation: operation,
            error: MintFailureError.requiresUserIntervention(
                pendingOperation: operation,
                sourceMint: "", // Would be filled from context
                destinationMint: operation.mintURL,
                amount: operation.amount,
                paymentProof: paymentProof
            )
        )
        
        switch decision {
        case .retry:
            // Retry the mint operation
            guard let mint = await mints.getMint(url: operation.mintURL) else {
                throw NDKError.noMintAvailable("Mint not found: \(operation.mintURL)")
            }
            
            let retryHandler = MintRetryHandler()
            let proofs = try await retryHandler.retryPendingMint(operation, mint: mint)
            
            if !proofs.isEmpty {
                NDKLogger.log(.info, category: .wallet, "✅ Successfully recovered \(proofs.count) proofs after user retry")
                // Update wallet state with recovered proofs
                // This would be handled by the calling code
            }
            
        case .blacklistMint:
            // Add mint to blacklist
            do {
                try await wallet.blacklistMint(operation.mintURL)
            } catch {
                NDKLogger.log(.error, category: .wallet, "Failed to blacklist mint: \(error)")
            }
            
            // Log the failed operation for potential manual recovery
            logFailedOperation(operation, paymentProof: paymentProof)
            
        case .cancel:
            // User chose not to retry or blacklist
            NDKLogger.log(.info, category: .wallet, "User cancelled mint recovery for: \(operation.mintURL)")
            
            // Still log the operation for potential manual recovery
            logFailedOperation(operation, paymentProof: paymentProof)
        }
    }
    
    /// Handle deposit mint failure
    private func handleDepositFailure(_ operation: PendingMintOperation) async throws {
        guard let delegate = delegate else {
            NDKLogger.log(.error, category: .wallet, "No delegate set to handle deposit failure")
            throw NDKError.notConfigured("No mint failure handler delegate")
        }
        
        // Get user's decision
        let decision = await delegate.handleMintFailure(
            operation: operation,
            error: DepositMintError.requiresUserIntervention(
                pendingOperation: operation,
                invoice: operation.invoice
            )
        )
        
        switch decision {
        case .retry:
            // Retry checking and minting
            let proofs = try await CashuDeposit.checkAndMintTokens(
                quoteId: operation.quoteId,
                mintURL: operation.mintURL,
                amount: operation.amount,
                mints: mints
            )
            
            if !proofs.isEmpty {
                NDKLogger.log(.info, category: .wallet, "✅ Successfully recovered \(proofs.count) proofs from deposit")
            }
            
        case .blacklistMint:
            do {
                try await wallet.blacklistMint(operation.mintURL)
            } catch {
                NDKLogger.log(.error, category: .wallet, "Failed to blacklist mint after deposit failure: \(error)")
            }
            
        case .cancel:
            NDKLogger.log(.info, category: .wallet, "User cancelled deposit recovery for: \(operation.mintURL)")
        }
    }
    
    /// Log failed operation for potential manual recovery
    private func logFailedOperation(_ operation: PendingMintOperation, paymentProof: String?) {
        let logEntry = """
        FAILED MINT OPERATION
        =====================
        Quote ID: \(operation.quoteId)
        Mint URL: \(operation.mintURL)
        Amount: \(operation.amount) sats
        Invoice: \(operation.invoice)
        Payment Proof: \(paymentProof ?? "N/A")
        Created: \(operation.createdAt)
        Last Attempt: \(operation.lastAttemptAt)
        =====================
        """
        
        NDKLogger.log(.error, category: .wallet, logEntry)
        
        // In a real implementation, this would:
        // 1. Save to persistent storage
        // 2. Allow export for manual recovery
        // 3. Potentially notify a monitoring service
    }
}

/// Example UI implementation for SwiftUI apps
public struct MintFailureAlert {
    public static func present(
        operation: PendingMintOperation,
        error: Error
    ) async -> MintFailureUserDecision {
        // In a real SwiftUI app, this would present an alert
        // For now, we'll return a default decision
        // 
        // Example alert content:
        // Title: "Mint Failed to Issue Tokens"
        // Message: "The mint at \(operation.mintURL) received your payment but failed to issue tokens.
        //          Amount: \(operation.amount) sats
        //          Quote ID: \(operation.quoteId)
        //          
        //          What would you like to do?"
        // Buttons:
        // - "Retry" -> .retry
        // - "Blacklist Mint" -> .blacklistMint  
        // - "Cancel" -> .cancel
        
        return .retry // Default action
    }
}