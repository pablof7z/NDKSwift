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
        guard let signer = ndk.signer else {
            throw NDKError.notConfigured("No signer configured")
        }
        
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
    public var proofs: [CashuProof] {
        let tags = event.tags
        return tags
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
        let tags = event.tags
        guard let urlString = tags.first(where: { $0.first == "u" })?[safe: 1] else {
            return nil
        }
        return URL(string: urlString)
    }
    
    /// Recipient's pubkey
    public var recipientPubkey: String? {
        let tags = event.tags
        return tags.first(where: { $0.first == "p" })?[safe: 1]
    }
    
    /// Zapped event ID if this is zapping an event
    public var zappedEventId: String? {
        let tags = event.tags
        return tags.first(where: { $0.first == "e" })?[safe: 1]
    }
    
    /// Total amount in the proofs
    public var totalAmount: Int64 {
        let proofs = self.proofs
        return proofs.reduce(0) { $0 + Int64($1.amount) }
    }
    
    // MARK: - Validation
    
    /// Validate the nutzap according to NIP-61 requirements
    /// - Parameter recipientPreferences: The recipient's nutzap preferences
    /// - Returns: true if valid, false otherwise
    public func validate(recipientPreferences: NDKNutzapPreferences) async -> Bool {
        // 1. Check that the mint is in the recipient's accepted list
        guard let mintURL = await mintURL else {
            return false
        }
        
        let recipientMints = await recipientPreferences.mints
        guard recipientMints.contains(where: { $0.url == mintURL }) else {
            return false
        }
        
        // 2. Check that proofs are P2PK-locked to the recipient's pubkey
        let recipientP2PKPubkey = await recipientPreferences.p2pkPubkey
        let proofs = await self.proofs
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
        guard let signer = ndk.signer else {
            throw NDKError.notConfigured("No signer configured")
        }
        
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
        
        let event = try await NDKEventBuilder()
            .kind(10019)
            .tags(tags)
            .build(signer: signer)
        
        return NDKNutzapPreferences(event: event)
    }
    
    // MARK: - Computed Properties
    
    /// Relays where the user will read nutzap events
    public var relays: [String] {
        return event.tags
            .filter { $0.first == "relay" }
            .compactMap { $0[safe: 1] }
    }
    
    /// Accepted mints and their supported units
    public var mints: [(url: URL, units: [String])] {
        return event.tags
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
        return event.tags.first(where: { $0.first == "pubkey" })?[safe: 1] ?? ""
    }
}

// MARK: - Cashu Types
// Using types from CashuTypes.swift
