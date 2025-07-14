import Foundation
import CashuSwift

/// Manages Lightning deposit operations for the Cashu wallet
public actor CashuDepositManager {
    // MARK: - Properties
    
    private let eventManager: WalletEventManager
    private let proofStateManager: ProofStateManager
    
    // MARK: - Initialization
    
    public init(eventManager: WalletEventManager, proofStateManager: ProofStateManager) {
        self.eventManager = eventManager
        self.proofStateManager = proofStateManager
    }
    
    // MARK: - Deposit Operations
    
    /// Request a mint quote for depositing via Lightning
    public func requestMintQuote(
        amount: Int64,
        mintURL: String,
        mintManager: MintManager,
        persistQuote: Bool = false,
        signer: NDKSigner? = nil
    ) async throws -> CashuMintQuote {
        // Get mint quote from mint manager
        let quoteResponse = try await mintManager.requestMintQuote(amount: amount, mintURL: mintURL)
        
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
        if persistQuote, let signer = signer {
            try await eventManager.saveQuoteEvent(quote: quote, signer: signer)
        }
        
        return quote
    }
    
    /// Monitor deposit status for a mint quote
    public func monitorDeposit(
        quote: CashuMintQuote,
        mintManager: MintManager,
        signer: NDKSigner,
        pollingInterval: TimeInterval = 5.0,
        timeout: TimeInterval = 600.0,
        onProofsReceived: @escaping ([CashuSwift.Proof]) async throws -> [String]
    ) -> AsyncThrowingStream<DepositStatus, Error> {
        return AsyncThrowingStream { continuation in
            let task = Task {
                let startTime = Date()
                
                do {
                    while Date().timeIntervalSince(startTime) < timeout {
                        // Check if Lightning invoice has been paid to the mint
                        do {
                            let proofs = try await self.checkAndMintTokens(
                                quote: quote,
                                mintManager: mintManager
                            )
                            
                            if !proofs.isEmpty {
                                // Delete the quote event
                                try await self.eventManager.deleteQuoteEvent(
                                    quoteId: quote.quoteId,
                                    signer: signer
                                )
                                
                                // Let the wallet handle proof state updates
                                let createdEventIds = try await onProofsReceived(proofs)
                                
                                // Create history event for the lightning deposit
                                Task {
                                    do {
                                        try await self.eventManager.createSpendingHistoryEvent(
                                            direction: .in,
                                            amount: Int64(quote.amount),
                                            createdEventIds: createdEventIds,
                                            signer: signer
                                        )
                                        print("✅ Created NIP-60 history event for lightning deposit of \(quote.amount) sats")
                                    } catch {
                                        print("⚠️ Failed to create history event for deposit: \(error)")
                                    }
                                }
                                
                                continuation.yield(.minted(proofs: proofs))
                                continuation.finish()
                                return
                            }
                        } catch {
                            // If it's a specific error indicating deposit not ready, continue polling
                            if case CashuError.quoteNotPaid = error {
                                // Expected - deposit not ready yet, continue polling
                            } else {
                                throw error
                            }
                        }
                        
                        // Still pending
                        continuation.yield(.pending)
                        
                        // Wait before next check
                        try await Task.sleep(nanoseconds: UInt64(pollingInterval * 1_000_000_000))
                    }
                    
                    // Timeout reached - persist quote and mark as expired
                    try await self.eventManager.saveQuoteEvent(quote: quote, signer: signer)
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
    private func checkAndMintTokens(
        quote: CashuMintQuote,
        mintManager: MintManager
    ) async throws -> [CashuSwift.Proof] {
        guard let mint = await mintManager.getMint(url: quote.mintURL) else {
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
        let distribution = splitIntoBase2(Int(quote.amount))
        
        // Create mint quote with request details for issue function
        var mintQuote = statusResponse
        mintQuote.requestDetail = CashuSwift.Bolt11.RequestMintQuote(
            unit: "sat",
            amount: Int(quote.amount)
        )
        
        // Issue tokens using the quote
        let (proofs, validDLEQ) = try await CashuSwift.issue(
            for: mintQuote,
            with: mint,
            seed: nil,
            preferredDistribution: distribution
        )
        
        // Check DLEQ verification
        guard validDLEQ else {
            throw NDKError.invalidProof("DLEQ verification failed")
        }
        
        return proofs
    }
    
    /// Check and mint tokens for an existing quote (one-shot operation)
    public func checkAndMintTokens(
        quoteId: String,
        mintURL: String,
        amount: Int64,
        mintManager: MintManager
    ) async throws -> [CashuSwift.Proof] {
        let quote = CashuMintQuote(
            quoteId: quoteId,
            mintURL: mintURL,
            amount: amount,
            invoice: "", // Not needed for checking
            expiry: Date(), // Not needed for checking
            requestedAt: Date()
        )
        
        return try await checkAndMintTokens(quote: quote, mintManager: mintManager)
    }
}

