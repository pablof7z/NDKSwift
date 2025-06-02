import Foundation

/// Routes payments to appropriate payment methods based on recipient capabilities
public class NDKPaymentRouter {
    private let ndk: NDK
    private let walletConfig: NDKWalletConfig
    
    public init(ndk: NDK, walletConfig: NDKWalletConfig) {
        self.ndk = ndk
        self.walletConfig = walletConfig
    }
    
    /// Pay a user with automatic method selection
    public func pay(_ request: NDKPaymentRequest) async throws -> NDKPaymentConfirmation {
        // Get recipient's payment methods
        let paymentMethods = try await getRecipientPaymentMethods(request.recipient)
        
        // Try payment methods in order of preference
        var lastError: Error?
        
        // Try NIP-57 (Lightning) first if available
        if paymentMethods.contains(.lightning), let lnPay = walletConfig.lnPay {
            do {
                let zapRequest = try await createZapRequest(for: request)
                let invoice = try await fetchLightningInvoice(for: request, zapRequest: zapRequest)
                
                if let confirmation = try await lnPay(request, invoice) {
                    walletConfig.onPaymentComplete?(confirmation, nil)
                    return confirmation
                }
            } catch {
                lastError = error
                print("Lightning payment failed: \(error)")
            }
        }
        
        // Try NIP-61 (Nutzap) if available or as fallback
        if paymentMethods.contains(.nutzap) || walletConfig.nutzapAsFallback,
           let cashuPay = walletConfig.cashuPay {
            do {
                if let confirmation = try await cashuPay(request) {
                    // Create and publish nutzap event
                    if let nutzap = confirmation.nutzap {
                        try await publishNutzap(nutzap, for: request)
                    }
                    
                    walletConfig.onPaymentComplete?(confirmation, nil)
                    return confirmation
                }
            } catch {
                lastError = error
                print("Cashu payment failed: \(error)")
            }
        }
        
        // If we get here, all payment methods failed
        let error = lastError ?? NDKError.paymentFailed("No payment methods available")
        walletConfig.onPaymentComplete?(nil, error)
        throw error
    }
    
    /// Get available payment methods for a recipient
    private func getRecipientPaymentMethods(_ recipient: NDKUser) async throws -> Set<NDKPaymentMethod> {
        var methods = Set<NDKPaymentMethod>()
        
        // Check for Lightning support (NIP-57)
        if let profile = try? await recipient.fetchProfile() {
            if profile.lud06 != nil || profile.lud16 != nil {
                methods.insert(.lightning)
            }
        }
        
        // Check for Cashu mint list (NIP-61)
        let mintListFilter = NDKFilter(
            authors: [recipient.pubkey],
            kinds: [EventKind.cashuMintList]
        )
        
        if let mintListEvent = try? await ndk.fetchEvent(mintListFilter) {
            // Parse mint list to verify it has valid mints
            let mints = mintListEvent.tags.filter({ $0.first == "mint" }).compactMap({ $0[safe: 1] })
            if !mints.isEmpty {
                methods.insert(.nutzap)
            }
        }
        
        // TODO: Check for NWC support when implemented
        
        return methods
    }
    
    /// Create a NIP-57 zap request
    private func createZapRequest(for request: NDKPaymentRequest) async throws -> NDKEvent {
        let zapRequest = NDKEvent(content: "", tags: [])
        zapRequest.ndk = ndk
        zapRequest.kind = EventKind.zapRequest
        zapRequest.content = request.comment ?? ""
        zapRequest.tags = [
            ["p", request.recipient.pubkey],
            ["amount", String(request.amount * 1000)], // Convert to millisats
            ["relays"] + (try await getRecipientRelays(request.recipient))
        ]
        
        if let tags = request.tags {
            zapRequest.tags.append(contentsOf: tags)
        }
        
        try await zapRequest.sign()
        return zapRequest
    }
    
    /// Fetch Lightning invoice for a zap request
    private func fetchLightningInvoice(for request: NDKPaymentRequest, zapRequest: NDKEvent) async throws -> String {
        // This would typically fetch from the recipient's LNURL endpoint
        // For now, this is a placeholder
        throw NDKError.notImplemented("Lightning invoice fetching not yet implemented")
    }
    
    /// Publish a nutzap event
    private func publishNutzap(_ nutzap: NDKNutzap, for request: NDKPaymentRequest) async throws {
        let relays = try await getRecipientRelays(request.recipient)
        let relaySet = NDKRelaySet(relayURLs: relays, ndk: ndk)
        try await nutzap.publish(on: relaySet)
    }
    
    /// Get recipient's preferred relays
    private func getRecipientRelays(_ recipient: NDKUser) async throws -> [String] {
        // Try to get relay list from NIP-65
        let relayListFilter = NDKFilter(
            authors: [recipient.pubkey],
            kinds: [EventKind.relayList]
        )
        
        if let relayListEvent = try? await ndk.fetchEvent(relayListFilter) {
            return relayListEvent.tags
                .filter { $0.first == "r" }
                .compactMap { $0[safe: 1] }
        }
        
        // Fallback to connected relays
        return ndk.pool.connectedRelays().map { $0.url }
    }
}

// MARK: - Errors

extension NDKError {
    static func paymentFailed(_ message: String) -> NDKError {
        return NDKError.validation("Payment failed: \(message)")
    }
    
    static func notImplemented(_ message: String) -> NDKError {
        return NDKError.validation("Not implemented: \(message)")
    }
}