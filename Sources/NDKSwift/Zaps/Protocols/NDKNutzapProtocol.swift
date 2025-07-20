import Foundation
import CashuSwift

/// NIP-61 Nutzap protocol implementation
public class NDKNutzapProtocol: NDKZapProtocol {
    public let type = ZapType.nutzap
    
    private let ndk: NDK
    
    public init(ndk: NDK) {
        self.ndk = ndk
    }
    
    public func canZap(user: NDKUser) async throws -> Bool {
        // Check if user has nutzap preferences
        guard let preferences = try? await fetchNutzapPreferences(for: user) else {
            return false
        }
        
        // We can zap if they have at least one mint configured
        return !(await preferences.mints).isEmpty
    }
    
    public func prepareZap(
        event: NDKEvent?,
        to user: NDKUser,
        amountSats: Int64,
        comment: String?
    ) async throws -> PreparedZap {
        // 1. Fetch recipient's nutzap preferences
        guard let preferences = try await fetchNutzapPreferences(for: user) else {
            throw ZapError.nutzapPreferencesNotFound
        }
        
        // 2. Get all accepted mints
        let acceptedMints = (await preferences.mints).map { $0.url }
        guard !acceptedMints.isEmpty else {
            throw ZapError.invalidMint
        }
        
        // 3. Create payment request with ALL accepted mints
        // Payment provider will choose the optimal one
        let paymentRequest = NutzapPaymentRequest(
            amountSats: amountSats,
            recipientPubkey: user.pubkey,  // Nostr pubkey for p tag
            recipientP2PK: await preferences.p2pkPubkey,  // P2PK key for locking proofs
            acceptedMints: acceptedMints,
            comment: comment
        )
        
        // 4. Store metadata for completion
        let metadata: [String: Any] = [
            "preferences": preferences
        ]
        
        return PreparedZap(
            paymentRequest: paymentRequest,
            recipient: user,
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
        guard let _ = prepared.metadata["preferences"] as? NDKNutzapPreferences,
              let relays = prepared.metadata["relays"] as? [String] else {
            throw NDKError.invalidInput(message: "Missing nutzap metadata")
        }
        
        // Extract Cashu proofs from confirmation
        guard let cashuConfirmation = confirmation as? CashuPaymentConfirmation else {
            throw NDKError.invalidInput(message: "Invalid payment confirmation type for nutzap")
        }
        
        // Create nutzap event using the mint from the confirmation
        let nutzap = try await NDKNutzap.create(
            ndk: ndk,
            recipient: prepared.recipient,
            proofs: cashuConfirmation.proofs,
            mint: cashuConfirmation.mintURL,  // Use the mint that was actually used
            comment: prepared.comment,
            zappedEvent: prepared.zappedEvent
        )
        
        // Publish to recipient's preferred relays
        _ = try await ndk.publish(nutzap.event, to: Set(relays))
        
        // Create result - Nutzaps are complete immediately
        return ZapResult(
            type: .nutzap,
            amountSats: prepared.paymentRequest.amountSats,
            receiptEvent: nil,
            nutzapEvent: nutzap.event
        )
    }
    
    // MARK: - Mint Communication
    
    /// Get available mints for a recipient
    public func getAcceptedMints(for user: NDKUser) async throws -> [URL] {
        guard let preferences = try await fetchNutzapPreferences(for: user) else {
            return []
        }
        return (await preferences.mints).map { $0.url }
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
    
    // MARK: - Private Methods
    
    private func fetchNutzapPreferences(for user: NDKUser) async throws -> NDKNutzapPreferences? {
        var filter = NDKFilter()
        filter.authors = [user.pubkey]
        filter.kinds = [EventKind.nutzapPreferences]
        
        // Use NDKDataSource for fetching preferences
        let dataSource = NDKDataSource(
            ndk: ndk,
            filter: filter,
            maxAge: 300 // 5 minutes - preferences don't change often
        )
        
        let events = await dataSource.currentValue()
        guard let event = events.first else {
            return nil
        }
        
        return NDKNutzapPreferences(event: event)
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