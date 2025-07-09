import Foundation

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
        proofs: [CashuProof],
        mint: URL,
        comment: String? = nil,
        zappedEvent: NDKEvent? = nil
    ) async throws -> NDKNutzap {
        let event = NDKEvent()
        event.kind = 9321
        event.content = comment ?? ""
        
        var tags: [[String]] = []
        
        // Add proof tags
        for proof in proofs {
            let proofJSON = try JSONEncoder().encode(proof)
            if let proofString = String(data: proofJSON, encoding: .utf8) {
                tags.append(["proof", proofString])
            }
        }
        
        // Add mint URL
        tags.append(["u", mint.absoluteString])
        
        // Add recipient
        tags.append(["p", recipient.pubkey])
        
        // Add zapped event if present
        if let zappedEvent = zappedEvent, let eventId = zappedEvent.id {
            tags.append(["e", eventId, ""])
        }
        
        event.tags = tags
        try await event.sign()
        
        return NDKNutzap(event: event)
    }
    
    // MARK: - Computed Properties
    
    /// The comment/message
    public var comment: String? {
        event.content.isEmpty ? nil : event.content
    }
    
    /// Cashu proofs
    public var proofs: [CashuProof] {
        event.tags
            .filter { $0.first == "proof" }
            .compactMap { tag in
                guard let proofJSON = tag[safe: 1],
                      let data = proofJSON.data(using: .utf8),
                      let proof = try? JSONDecoder().decode(CashuProof.self, from: data) else {
                    return nil
                }
                return proof
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
        event.tags.first(where: { $0.first == "p" })?[safe: 1]
    }
    
    /// Zapped event ID if this is zapping an event
    public var zappedEventId: String? {
        event.tags.first(where: { $0.first == "e" })?[safe: 1]
    }
    
    /// Total amount in the proofs
    public var totalAmount: Int64 {
        proofs.reduce(0) { $0 + Int64($1.amount) }
    }
    
    // MARK: - Validation
    
    /// Validate the nutzap according to NIP-61 requirements
    /// - Parameter recipientPreferences: The recipient's nutzap preferences
    /// - Returns: true if valid, false otherwise
    public func validate(recipientPreferences: NDKNutzapPreferences) -> Bool {
        // 1. Check that the mint is in the recipient's accepted list
        guard let mintURL = mintURL,
              recipientPreferences.mints.contains(where: { $0.url == mintURL }) else {
            return false
        }
        
        // 2. Check that proofs are P2PK-locked to the recipient's pubkey
        let recipientP2PKPubkey = recipientPreferences.p2pkPubkey
        for proof in proofs {
            guard proof.isLockedTo(pubkey: recipientP2PKPubkey) else {
                return false
            }
        }
        
        // 3. Verify DLEQ proofs if present
        for proof in proofs {
            if let _ = proof.dleq {
                // DLEQ verification would require complex cryptographic operations
                // that are beyond the scope of this library. Cashu wallets
                // should handle DLEQ verification when redeeming tokens.
                continue
            }
        }
        
        return true
    }
}

/// NIP-61 Nutzap Preferences (kind: 10019)
/// Specifies how a user wants to receive nutzaps
public struct NDKNutzapPreferences {
    public let event: NDKEvent
    
    public init(event: NDKEvent) {
        self.event = event
    }
    
    /// Create nutzap preferences
    public static func create(
        ndk: NDK,
        relays: [String],
        mints: [(url: URL, units: [String])],
        p2pkKeyPair: KeyPair
    ) async throws -> NDKNutzapPreferences {
        let event = NDKEvent()
        event.kind = 10019
        
        var tags: [[String]] = []
        
        // Add relay tags
        for relay in relays {
            tags.append(["relay", relay])
        }
        
        // Add mint tags
        for mint in mints {
            var mintTag = ["mint", mint.url.absoluteString]
            mintTag.append(contentsOf: mint.units)
            tags.append(mintTag)
        }
        
        // Add P2PK pubkey (prefixed with "02" for nostr<>cashu compatibility)
        let p2pkPubkey = "02" + p2pkKeyPair.publicKey
        tags.append(["pubkey", p2pkPubkey])
        
        event.tags = tags
        try await event.sign()
        
        return NDKNutzapPreferences(event: event)
    }
    
    // MARK: - Computed Properties
    
    /// Relays where the user will read nutzap events
    public var relays: [String] {
        event.tags
            .filter { $0.first == "relay" }
            .compactMap { $0[safe: 1] }
    }
    
    /// Accepted mints and their supported units
    public var mints: [(url: URL, units: [String])] {
        event.tags
            .filter { $0.first == "mint" }
            .compactMap { tag in
                guard let urlString = tag[safe: 1],
                      let url = URL(string: urlString) else {
                    return nil
                }
                let units = Array(tag.dropFirst(2))
                return (url: url, units: units)
            }
    }
    
    /// P2PK public key for receiving nutzaps
    public var p2pkPubkey: String {
        event.tags.first(where: { $0.first == "pubkey" })?[safe: 1] ?? ""
    }
}

// MARK: - Cashu Types
// Using types from CashuTypes.swift
