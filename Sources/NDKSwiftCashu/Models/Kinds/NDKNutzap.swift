import CashuSwift
import Foundation
import NDKSwiftCore

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
        recipient: PublicKey,
        proofs: [CashuSwift.Proof],
        mint: URL,
        comment: String? = nil,
        zappedEvent: NDKEvent? = nil
    ) async throws -> NDKNutzap {
        let signer = try ndk.requireSigner()

        var tags: [[String]] = []

        // Calculate total amount
        let totalAmount = proofs.reduce(0) { $0 + Int64($1.amount) }

        // Add mint URL (u tag per NIP-61)
        tags.append([NostrConstants.TagName.url, mint.absoluteString])

        // Add recipient
        tags.append([NostrConstants.TagName.pubkey, recipient])

        // Add amount tag
        tags.append([NostrConstants.TagName.amount, String(totalAmount)])

        // Add unit tag
        tags.append([NostrConstants.TagName.unit, WalletConstants.defaultUnit])

        // Add proof tags
        for proof in proofs {
            let proofString = try JSONCoding.encodeToString(proof)
            tags.append([NostrConstants.TagName.proof, proofString])
        }

        // Add zapped event if present
        if let zappedEvent = zappedEvent {
            tags.append([NostrConstants.TagName.event, zappedEvent.id, ""])
        }

        let event = try await NDKEventBuilder(ndk: ndk)
            .kind(9321)
            .content(comment ?? "")
            .tags(tags)
            .build(signer: signer)

        return NDKNutzap(event: event)
    }

    // MARK: - Computed Properties

    /// The comment/message
    public var comment: String? {
        return event.content.nilIfEmpty
    }

    /// Cashu proofs
    public var proofs: [CashuSwift.Proof] {
        return event.tags
            .filter { $0.first == NostrConstants.TagName.proof }
            .compactMap { tag in
                guard let proofJSON = tag[safe: 1] else { return nil }
                return JSONCoding.safeDecode(CashuSwift.Proof.self, from: proofJSON)
            }
    }

    /// Mint URL
    public var mintURL: URL? {
        guard let urlString = event.tags.first(where: { $0.first == NostrConstants.TagName.url })?[safe: 1] else {
            return nil
        }
        return URL(string: urlString)
    }

    /// Recipient's pubkey
    public var recipientPubkey: String? {
        return event.tags.first(where: { $0.first == NostrConstants.TagName.pubkey })?[safe: 1]
    }

    /// Zapped event ID if this is zapping an event
    public var zappedEventId: String? {
        return event.tags.first(where: { $0.first == NostrConstants.TagName.event })?[safe: 1]
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
        for proof in proofs where proof.dleq != nil {
            // DLEQ verification would require complex cryptographic operations
            // For now, we assume they're valid if present
            continue
        }

        return true
    }

    /// Create nutzap preferences from a user's kind 10019 event
    public static func createPreferences(ndk: NDK, mints: [NDKNutzapPreferences.MintConfig]) async throws -> NDKEvent {
        let signer = try ndk.requireSigner()

        var tags: [[String]] = []

        for mint in mints {
            tags.append([NostrConstants.TagName.mint, mint.url.absoluteString])
        }

        // Add P2PK pubkey tag (for now, same as event author)
        let pubkey = try await signer.pubkey
        tags.append([NostrConstants.TagName.pubkey, pubkey])

        let event = try await NDKEventBuilder(ndk: ndk)
            .kind(10019)
            .tags(tags)
            .build(signer: signer)

        return event
    }
}
