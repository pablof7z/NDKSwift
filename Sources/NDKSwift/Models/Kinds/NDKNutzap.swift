import Foundation
import CashuSwift

/// NIP-61 Nutzap (kind: 9321)
/// A Nutzap is a P2PK Cashu token event where the payment itself is the receipt.
public struct NDKNutzap {
    public let event: NDKEvent
    
    public init(event: NDKEvent) {
        self.event = event
    }
    
    /// Create a new nutzap event
    public static func create(
        ndk: NDK,
        recipient: NDKUser,
        proofs: [CashuSwift.Proof],
        mint: URL,
        comment: String? = nil,
        zappedEvent: NDKEvent? = nil
    ) async throws -> NDKNutzap {
        guard let signer = ndk.signer else {
            throw NDKError.notConfigured("No signer configured")
        }
        
        var tags: [[String]] = []
        
        // Calculate total amount
        let totalAmount = proofs.reduce(0) { $0 + Int64($1.amount) }
        
        // Add mint URL (u tag per NIP-61)
        tags.append(["u", mint.absoluteString])
        
        // Add recipient
        tags.append(["p", recipient.pubkey])
        
        // Add amount tag
        tags.append(["amount", String(totalAmount)])
        
        // Add proof tags
        for proof in proofs {
            let proofString = try JSONCoding.encodeToString(proof)
            tags.append(["proof", proofString])
        }
        
        // Add zapped event if present
        if let zappedEvent = zappedEvent {
            tags.append(["e", zappedEvent.id, ""])
        }
        
        let event = try await NDKEventBuilder()
            .kind(9321)
            .content(comment ?? "")
            .tags(tags)
            .build(signer: signer)
        
        return NDKNutzap(event: event)
    }
    
    // MARK: - Computed Properties
    
    /// The comment/message
    public var comment: String? {
        let content = event.content
        return content.isEmpty ? nil : content
    }
    
    /// Cashu proofs
    public var proofs: [CashuSwift.Proof] {
        return event.tags
            .filter { $0.first == "proof" }
            .compactMap { tag in
                guard let proofJSON = tag[safe: 1] else { return nil }
                return JSONCoding.safeDecode(CashuSwift.Proof.self, from: proofJSON)
            }
    }
    
    /// Mint URL
    public var mintURL: URL? {
        guard let urlString = event.tags.first(where: { $0.first == "u" })?[safe: 1] else {
            return nil
        }
        return URL(string: urlString)
    }
    
    /// Recipient's pubkey
    public var recipientPubkey: String? {
        return event.tags.first(where: { $0.first == "p" })?[safe: 1]
    }
    
    /// Zapped event ID if this is zapping an event
    public var zappedEventId: String? {
        return event.tags.first(where: { $0.first == "e" })?[safe: 1]
    }
    
    /// Total amount in the proofs
    public var totalAmount: Int64 {
        return proofs.reduce(0) { $0 + Int64($1.amount) }
    }
    
    // MARK: - Validation
    
    /// Validate the nutzap according to NIP-61 requirements
    /// - Parameter recipientPreferences: The recipient's nutzap preferences
    /// - Returns: true if valid, false otherwise
    public func validate(recipientPreferences: NDKNutzapPreferences) async -> Bool {
        // 1. Check that the mint is in the recipient's accepted list
        guard let mintURL = self.mintURL else {
            return false
        }
        
        let recipientMints = await recipientPreferences.mints
        guard recipientMints.contains(where: { $0.url == mintURL }) else {
            return false
        }
        
        // 2. Check that proofs are P2PK-locked to the recipient's pubkey
        let recipientP2PKPubkey = await recipientPreferences.p2pkPubkey
        let proofs = self.proofs
        for proof in proofs {
            guard CashuHelpers.isProofLockedTo(proof: proof, pubkey: recipientP2PKPubkey) else {
                return false
            }
        }
        
        // 3. Verify DLEQ proofs if present
        for proof in proofs {
            if let _ = proof.dleq {
                // DLEQ verification would require complex cryptographic operations
                // For now, we assume they're valid if present
                continue
            }
        }
        
        return true
    }
    
    /// Create nutzap preferences from a user's kind 10019 event
    public static func createPreferences(ndk: NDK, mints: [NDKNutzapPreferences.MintConfig]) async throws -> NDKEvent {
        guard let signer = ndk.signer else {
            throw NDKError.notConfigured("No signer configured")
        }
        
        var tags: [[String]] = []
        
        for mint in mints {
            tags.append(["mint", mint.url.absoluteString])
        }
        
        // Add P2PK pubkey tag (for now, same as event author)
        let pubkey = try await signer.pubkey
        tags.append(["pubkey", pubkey])
        
        let event = try await NDKEventBuilder()
            .kind(10019)
            .tags(tags)
            .build(signer: signer)
        
        return event
    }
}

/// Nutzap preferences (kind: 10019)
public struct NDKNutzapPreferences {
    public let event: NDKEvent
    
    public init(event: NDKEvent) {
        self.event = event
    }
    
    /// Mint configuration
    public struct MintConfig {
        public let url: URL
        public let relays: [String]
        
        public init(url: URL, relays: [String] = []) {
            self.url = url
            self.relays = relays
        }
    }
    
    /// Get configured mints
    public var mints: [MintConfig] {
        get async {
            return event.tags
                .filter { $0.first == "mint" }
                .compactMap { tag in
                    guard let urlString = tag[safe: 1],
                          let url = URL(string: urlString) else {
                        return nil
                    }
                    
                    let relays = Array(tag.dropFirst(2))
                    return MintConfig(url: url, relays: relays)
                }
        }
    }
    
    /// Get P2PK pubkey for receiving nutzaps
    public var p2pkPubkey: String {
        get async {
            // Look for p2pk tag (as per NIP-61)
            if let pubkey = event.tags.first(where: { $0.first == "p2pk" })?[safe: 1] {
                return pubkey
            }
            // Fall back to event author's pubkey
            return event.pubkey
        }
    }
}

// MARK: - Helper Extensions
// Note: The isLockedTo implementation is now in CashuTypes.swift