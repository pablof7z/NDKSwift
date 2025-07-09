import Foundation

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
        return !preferences.mints.isEmpty
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
        
        // 2. For now, select the first mint
        // In a real implementation, this could be smarter (e.g., check balances)
        guard let selectedMint = preferences.mints.first else {
            throw ZapError.invalidMint
        }
        
        // 3. Create payment request for Cashu proofs
        let paymentRequest = CashuProofRequest(
            amountSats: amountSats,
            mintURL: selectedMint.url,
            recipientP2PK: preferences.p2pkPubkey,
            comment: comment
        )
        
        // 4. Store metadata for completion
        let metadata: [String: Any] = [
            "preferences": preferences,
            "selectedMint": selectedMint.url,
            "relays": preferences.relays
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
        guard let preferences = prepared.metadata["preferences"] as? NDKNutzapPreferences,
              let mintURL = prepared.metadata["selectedMint"] as? URL,
              let relays = prepared.metadata["relays"] as? [String] else {
            throw NDKError.invalidInput(message: "Missing nutzap metadata")
        }
        
        // Extract Cashu proofs from confirmation
        guard let cashuConfirmation = confirmation as? CashuPaymentConfirmation else {
            throw NDKError.invalidInput(message: "Invalid payment confirmation type for nutzap")
        }
        
        // Create nutzap event
        let nutzap = try await NDKNutzap.create(
            ndk: ndk,
            recipient: prepared.recipient,
            proofs: cashuConfirmation.proofs,
            mint: mintURL,
            comment: prepared.comment,
            zappedEvent: prepared.zappedEvent
        )
        
        // Publish to recipient's preferred relays
        _ = try await ndk.publish(event: nutzap.event, to: Set(relays))
        
        // Create result - Nutzaps are complete immediately
        let awaitConfirmation: () async throws -> NDKEvent? = {
            // Nutzaps don't have a separate confirmation step
            return nutzap.event
        }
        
        return ZapResult(
            type: .nutzap,
            amountSats: confirmation.amount,
            receiptEvent: nil,
            nutzapEvent: nutzap.event
        )
    }
    
    // MARK: - Private Methods
    
    private func fetchNutzapPreferences(for user: NDKUser) async throws -> NDKNutzapPreferences? {
        var filter = NDKFilter()
        filter.authors = [user.pubkey]
        filter.kinds = [EventKind.nutzapPreferences]
        
        guard let event = try await ndk.fetchEvent(filter) else {
            return nil
        }
        
        return NDKNutzapPreferences(event: event)
    }
}