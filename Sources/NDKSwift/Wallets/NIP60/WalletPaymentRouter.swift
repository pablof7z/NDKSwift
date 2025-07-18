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
        guard let nutzapRequest = request as? NutzapPaymentRequest else {
            throw NDKError.invalidRequest("NIP60Wallet only supports nutzap payments")
        }
        
        print("WalletPaymentRouter.executePayment - amount: \(nutzapRequest.amountSats)")
        print("WalletPaymentRouter.executePayment - proofStateManager: \(ObjectIdentifier(proofStateManager))")
        
        // Find the best payment route
        let acceptedMintURLs = Set(nutzapRequest.acceptedMints.map { $0.absoluteString })
        print("WalletPaymentRouter.executePayment - acceptedMints: \(acceptedMintURLs)")
        
        let paymentRoute = await CrossMintTransfer.findBestPaymentRoute(
            amount: nutzapRequest.amountSats,
            acceptedMints: acceptedMintURLs,
            mints: mints,
            proofStateManager: proofStateManager
        )
        
        // Determine which mint to use and perform any necessary transfers
        switch paymentRoute {
        case .direct(let mint):
            print("💸 Direct payment using mint: \(mint)")
            // No transfer needed, mint already has sufficient balance
            
        case .crossMint(let sourceMint, let targetMint, let estimatedFee):
            print("💱 Cross-mint transfer required from \(sourceMint) to \(targetMint)")
            if let fee = estimatedFee {
                print("   Estimated fee: \(fee) sats")
            }
            
            // Perform the transfer
            guard let sourceURL = URL(string: sourceMint),
                  let targetURL = URL(string: targetMint) else {
                throw NDKError.invalidRequest("Invalid mint URLs for transfer")
            }
            
            _ = try await CrossMintTransfer.transferBetweenMints(
                amount: nutzapRequest.amountSats,
                from: sourceURL,
                to: targetURL,
                wallet: wallet,
                proofStateManager: proofStateManager,
                eventManager: eventManager,
                mints: mints,
                signer: signer
            )
            
            // Funds are now in the target mint
            
        case .impossible(let reason):
            print("❌ Payment impossible: \(reason)")
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
}