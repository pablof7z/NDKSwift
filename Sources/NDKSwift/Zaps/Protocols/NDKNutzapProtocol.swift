import Foundation
import CashuSwift

/// NIP-61 Nutzap protocol implementation
public class NDKNutzapProtocol: NDKZapProtocol {
    public let type = ZapType.nutzap
    
    private let ndk: NDK
    
    public init(ndk: NDK) {
        self.ndk = ndk
    }
    
    public func canZap(recipientInfo: RecipientZapInfo) -> Bool {
        // Simply check the pre-fetched info
        return recipientInfo.hasNutzapSupport
    }
    
    public func prepareZap(
        event: NDKEvent?,
        recipientInfo: RecipientZapInfo,
        amountSats: Int64,
        comment: String?
    ) async throws -> PreparedZap {
        NDKLogger.log(.debug, category: .wallet, "prepareZap")
        // We already have the preferences!
        guard let preferences = recipientInfo.nutzapPreferences else {
            throw ZapError.nutzapPreferencesNotFound
        }
        
        // Get all accepted mints
        let acceptedMints = await recipientInfo.nutzapMintURLs
        guard !acceptedMints.isEmpty else {
            throw ZapError.invalidMint
        }
        
        // Get P2PK pubkey
        guard let p2pkPubkey = await recipientInfo.nutzapP2PKPubkey else {
            throw ZapError.nutzapPreferencesNotFound
        }
        
        // Create payment request with ALL accepted mints
        // Payment provider will choose the optimal one
        let paymentRequest = NutzapPaymentRequest(
            amountSats: amountSats,
            recipientPubkey: recipientInfo.pubkey,  // Nostr pubkey for p tag
            recipientP2PK: p2pkPubkey,  // P2PK key for locking proofs
            acceptedMints: acceptedMints,
            comment: comment
        )
        
        // Get all relays (including mint-specific ones)
        let allRelays = await recipientInfo.nutzapRelays
        
        // Store metadata for completion
        let metadata: [String: Any] = [
            "preferences": preferences,
            "relays": Array(allRelays)
        ]
        
        // Create prepared zap with NDKUser
        let recipient = NDKUser(pubkey: recipientInfo.pubkey)
        
        return PreparedZap(
            paymentRequest: paymentRequest,
            recipient: recipient,
            zappedEvent: event,
            comment: comment,
            metadata: metadata
        )
    }
    
    public func completeZap(
        prepared: PreparedZap,
        confirmation: PaymentConfirmation
    ) async throws -> ZapResult {
        // Extract metadata
        guard let _ = prepared.metadata["preferences"] as? NDKNutzapPreferences else {
            throw NDKError.missingRequired("nutzap preferences", in: "metadata")
        }
        
        // Handle NutzapConfirmation - the nutzap event is already created
        guard let nutzapConfirmation = confirmation as? NutzapConfirmation else {
            NDKLogger.log(.error, category: .wallet, "Invalid confirmation type: \(confirmation)")
            throw NDKError.invalidDataFormat("payment confirmation", details: "Expected NutzapConfirmation type")
        }
        
        // The nutzap event is already created and included in the confirmation
        let nutzapEvent = nutzapConfirmation.nutzapEvent
        
        // Publish to recipient's preferred relays if available, otherwise use default behavior
        let relays = prepared.metadata["relays"] as? [String]
        if let relays = relays, !relays.isEmpty {
            _ = try await ndk.publish(nutzapEvent, to: Set(relays))
        } else {
            // Publish without specifying relays - use NDK's default relay selection
            _ = try await ndk.publish(nutzapEvent)
        }
        
        // Create result - Nutzaps are complete immediately
        return ZapResult(
            type: .nutzap,
            amountSats: prepared.paymentRequest.amountSats,
            receiptEvent: nil,
            nutzapEvent: nutzapEvent
        )
    }
    
    // MARK: - Mint Communication
    
    /// Get available mints for a recipient
    public func getAcceptedMints(recipientInfo: RecipientZapInfo) async -> [URL] {
        return await recipientInfo.nutzapMintURLs
    }
    
    /// Create a mint quote for Lightning-to-Cashu conversion
    public func createMintQuote(
        invoice: String,
        mint: URL,
        amount: Int64
    ) async throws -> MintQuote {
        // Load the mint
        let cashuMint = try await CashuSwift.loadMint(url: mint)
        
        // Request a mint quote from the mint
        let quoteRequest = CashuSwift.Bolt11.RequestMintQuote(
            unit: "sat",
            amount: Int(amount)
        )
        
        do {
            let quote = try await CashuSwift.getQuote(mint: cashuMint, quoteRequest: quoteRequest)
            
            guard let mintQuote = quote as? CashuSwift.Bolt11.MintQuote else {
                throw ZapError.mintQuoteFailed(mint: mint.host ?? mint.absoluteString, reason: "Invalid quote type")
            }
            
            return MintQuote(
                id: mintQuote.quote,
                mint: mint,
                amount: amount,
                invoice: mintQuote.request,  // The Lightning invoice to pay
                expiry: Date(timeIntervalSince1970: TimeInterval(mintQuote.expiry ?? 0))
            )
        } catch {
            throw ZapError.mintQuoteFailed(mint: mint.host ?? mint.absoluteString, reason: error.localizedDescription)
        }
    }
}

// MARK: - Mint Quote Support

public struct MintQuote {
    public let id: String
    public let mint: URL
    public let amount: Int64
    public let invoice: String
    public let expiry: Date
}