import Foundation
import CashuSwift

/// Handles payment routing and execution for the Cashu wallet
/// Consolidates all payment-related logic including cross-mint transfers
actor WalletPaymentRouter {
    
    /// Execute a payment request
    static func executePayment(
        _ request: PaymentRequest,
        wallet: NIP60Wallet,
        mints: MintManager,
        proofStateManager: ProofStateManager,
        eventManager: WalletEventManager,
        ndk: NDK,
        signer: NDKSigner
    ) async throws -> PaymentConfirmation {
        switch request {
        case let nutzapRequest as NutzapPaymentRequest:
            return try await executeNutzapPayment(
                nutzapRequest,
                wallet: wallet,
                mints: mints,
                proofStateManager: proofStateManager,
                eventManager: eventManager,
                ndk: ndk,
                signer: signer
            )
        case let lightningRequest as LightningInvoiceRequest:
            return try await executeLightningPayment(
                lightningRequest,
                wallet: wallet,
                mints: mints,
                proofStateManager: proofStateManager
            )
        default:
            throw NDKError.invalidRequest("Unsupported payment request type")
        }
    }
    
    /// Execute a nutzap payment
    static func executeNutzapPayment(
        _ nutzapRequest: NutzapPaymentRequest,
        wallet: NIP60Wallet,
        mints: MintManager,
        proofStateManager: ProofStateManager,
        eventManager: WalletEventManager,
        ndk: NDK,
        signer: NDKSigner
    ) async throws -> PaymentConfirmation {
        NDKLogger.log(.debug, category: .wallet, "WalletPaymentRouter.executeNutzapPayment - amount: \(nutzapRequest.amountSats)")
        NDKLogger.log(.debug, category: .wallet, "WalletPaymentRouter.executeNutzapPayment - proofStateManager: \(ObjectIdentifier(proofStateManager))")
        
        // Find the best payment route
        let acceptedMintURLs = Set(nutzapRequest.acceptedMints.map { $0.absoluteString })
        NDKLogger.log(.debug, category: .wallet, "WalletPaymentRouter.executeNutzapPayment - acceptedMints: \(acceptedMintURLs)")
        
        // Get blacklisted mints from wallet
        let blacklistedMints = await wallet.getBlacklistedMints()
        
        let paymentRoute = await CrossMintTransfer.findBestPaymentRoute(
            amount: nutzapRequest.amountSats,
            acceptedMints: acceptedMintURLs,
            mints: mints,
            proofStateManager: proofStateManager,
            blacklistedMints: blacklistedMints
        )
        
        // Determine which mint to use and perform any necessary transfers
        switch paymentRoute {
        case .direct(let mint):
            NDKLogger.log(.info, category: .wallet, "💸 Direct payment using mint: \(mint)")
            // No transfer needed, mint already has sufficient balance
            
        case .crossMint(let sourceMint, let targetMint, let estimatedFee):
            NDKLogger.log(.info, category: .wallet, "💱 Cross-mint transfer required from \(sourceMint) to \(targetMint)")
            if let fee = estimatedFee {
                NDKLogger.log(.info, category: .wallet, "   Estimated fee: \(fee) sats")
            }
            
            // Perform the transfer
            guard let sourceURL = URL(string: sourceMint),
                  let targetURL = URL(string: targetMint) else {
                throw NDKError.invalidRequest("Invalid mint URLs for transfer")
            }
            
            let result = try await CrossMintTransfer.transferBetweenMints(
                amount: nutzapRequest.amountSats,
                from: sourceURL,
                to: targetURL,
                wallet: wallet,
                proofStateManager: proofStateManager,
                eventManager: eventManager,
                mints: mints,
                signer: signer
            )
            
            // Log the actual fee paid
            NDKLogger.log(.info, category: .wallet, "✅ Cross-mint transfer completed. Fee paid: \(result.feePaid) sats")
            
            // Funds are now in the target mint
            
        case .impossible(let reason):
            NDKLogger.log(.error, category: .wallet, "❌ Payment impossible: \(reason)")
            throw NDKError.insufficientBalance(amount: nutzapRequest.amountSats)
        }
        
        // Send nutzap using static functions
        let mintsDict = await mints.getAllMints()
        let nutzapEvent = try await Nutzap.send(
            wallet: wallet,
            amount: nutzapRequest.amountSats,
            to: nutzapRequest.recipientPubkey,  // This is the Nostr pubkey
            recipientP2PKKey: nutzapRequest.recipientP2PK,  // This is the P2PK key from payment request
            comment: nutzapRequest.comment,
            eventId: nil,
            mints: mintsDict,
            proofStateManager: proofStateManager,
            eventManager: eventManager,
            ndk: ndk,
            signer: signer
        )
        
        // Use the appropriate mint URL from the route
        let mintUsed: URL
        switch paymentRoute {
        case .direct(let mint):
            mintUsed = URL(string: mint) ?? nutzapRequest.acceptedMints[0]
        case .crossMint(_, let targetMint, _):
            mintUsed = URL(string: targetMint) ?? nutzapRequest.acceptedMints[0]
        case .impossible:
            mintUsed = nutzapRequest.acceptedMints[0]
        }
        
        return NutzapConfirmation(
            amountSats: nutzapRequest.amountSats,
            timestamp: Date(),
            nutzapEvent: nutzapEvent,
            mintUsed: mintUsed
        )
    }
    
    /// Execute a Lightning invoice payment
    static func executeLightningPayment(
        _ lightningRequest: LightningInvoiceRequest,
        wallet: NIP60Wallet,
        mints: MintManager,
        proofStateManager: ProofStateManager
    ) async throws -> PaymentConfirmation {
        NDKLogger.log(.debug, category: .wallet, "WalletPaymentRouter.executeLightningPayment - amount: \(lightningRequest.amountSats)")
        NDKLogger.log(.debug, category: .wallet, "WalletPaymentRouter.executeLightningPayment - invoice: \(lightningRequest.invoice)")
        
        // Pay Lightning invoice through the mint
        let (preimage, feePaid) = try await wallet.payLightning(
            invoice: lightningRequest.invoice,
            amount: lightningRequest.amountSats
        )
        
        return LightningPaymentConfirmation(
            amountSats: lightningRequest.amountSats,
            timestamp: Date(),
            preimage: preimage,
            paymentHash: nil, // Could extract from invoice if needed
            feePaid: feePaid
        )
    }
}