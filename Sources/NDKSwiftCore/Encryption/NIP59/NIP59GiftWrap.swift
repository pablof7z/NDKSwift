import Foundation

/// NIP-59: Gift Wrap
///
/// This module implements the NIP-59 gift wrap protocol for obscuring event metadata.
/// It provides sealing and gift wrapping functionality to protect event content and metadata.
///
/// Specification: https://github.com/nostr-protocol/nips/blob/master/59.md

public enum NIP59 {
    // MARK: - Errors

    public enum NIP59Error: LocalizedError {
        case invalidRumor(String)
        case sealingFailed(String)
        case wrapFailed(String)
        case unwrapFailed(String)
        case missingPrivateKey
        case invalidGiftWrap(String)
        case decryptionFailed(String)

        public var errorDescription: String? {
            switch self {
            case let .invalidRumor(reason):
                return "Invalid rumor event: \(reason)"
            case let .sealingFailed(reason):
                return "Failed to seal event: \(reason)"
            case let .wrapFailed(reason):
                return "Failed to wrap event: \(reason)"
            case let .unwrapFailed(reason):
                return "Failed to unwrap event: \(reason)"
            case .missingPrivateKey:
                return "Private key required for this operation"
            case let .invalidGiftWrap(reason):
                return "Invalid gift wrap: \(reason)"
            case let .decryptionFailed(reason):
                return "Decryption failed: \(reason)"
            }
        }
    }

    // MARK: - Create Rumor

    /// Creates an unsigned "rumor" event (the inner content to be sealed)
    /// - Parameters:
    ///   - kind: Event kind
    ///   - content: Event content
    ///   - tags: Event tags
    ///   - pubkey: Author's public key
    ///   - createdAt: Optional timestamp (defaults to now)
    /// - Returns: Unsigned NDKEvent (rumor)
    public static func createRumor(
        kind: Kind,
        content: String,
        tags: [Tag] = [],
        pubkey: PublicKey,
        createdAt: Timestamp? = nil
    ) -> NDKEvent {
        let event = NDKEvent(
            kind: kind,
            content: content,
            tags: tags,
            pubkey: pubkey,
            createdAt: createdAt ?? .now
        )
        // Don't sign the rumor - it remains unsigned
        return event
    }

    // MARK: - Seal Event

    /// Seals a rumor event by encrypting it and creating a kind 13 seal event
    /// - Parameters:
    ///   - rumor: The unsigned rumor event to seal
    ///   - signer: Signer to use for the seal
    ///   - recipientPubkey: Public key of the recipient (for encryption)
    /// - Returns: Sealed event (kind 13)
    public static func seal(
        rumor: NDKEvent,
        signer: NDKSigner,
        recipientPubkey: PublicKey
    ) async throws -> NDKEvent {
        // Validate rumor is unsigned
        guard rumor.id.isEmpty || rumor.sig.isEmpty else {
            throw NIP59Error.invalidRumor("Rumor must be unsigned")
        }

        // For NIP-59, we need direct access to private key for NIP-44 encryption
        // This is a limitation - NIP-59 requires NDKPrivateKeySigner
        guard let privateKeySigner = signer as? NDKPrivateKeySigner else {
            throw NIP59Error.missingPrivateKey
        }

        // Serialize rumor to JSON
        let rumorJSON = try rumor.toJSON()

        // Encrypt rumor content using NIP-44
        let encryptedContent = try NIP44.encrypt(
            message: rumorJSON,
            privateKey: privateKeySigner.privateKeyForNIP59,
            pubkey: recipientPubkey
        )

        // Create seal event (kind 13)
        let sealPubkey = try await signer.pubkey

        // Build seal event using a temporary builder
        let sealEvent = NDKEvent(
            id: "", // Will be set during signing
            pubkey: sealPubkey,
            createdAt: .now,
            kind: EventKind.seal,
            tags: [],
            content: encryptedContent,
            sig: "" // Will be set during signing
        )

        // Calculate event ID and sign
        let sealId = try calculateEventId(event: sealEvent)
        let signature = try await signer.sign(NDKEvent(
            id: sealId,
            pubkey: sealEvent.pubkey,
            createdAt: sealEvent.createdAt,
            kind: sealEvent.kind,
            tags: sealEvent.tags,
            content: sealEvent.content,
            sig: ""
        ))

        // Return signed seal event
        return NDKEvent(
            id: sealId,
            pubkey: sealEvent.pubkey,
            createdAt: sealEvent.createdAt,
            kind: sealEvent.kind,
            tags: sealEvent.tags,
            content: sealEvent.content,
            sig: signature
        )
    }

    // MARK: - Gift Wrap Event

    /// Gift wraps a sealed event by encrypting it with a random key
    /// - Parameters:
    ///   - seal: The sealed event to wrap
    ///   - recipientPubkey: Public key of the recipient
    ///   - randomSigner: Optional random signer (will generate one if not provided)
    /// - Returns: Gift wrapped event (kind 1059)
    public static func wrap(
        seal: NDKEvent,
        recipientPubkey: PublicKey,
        randomSigner: NDKSigner? = nil
    ) async throws -> NDKEvent {
        // Validate seal event
        guard seal.kind == EventKind.seal else {
            throw NIP59Error.wrapFailed("Event must be a seal (kind 13)")
        }

        // Generate random signer if not provided
        let signer = try randomSigner ?? NDKPrivateKeySigner.generate()

        // For NIP-59, we need direct access to private key
        guard let privateKeySigner = signer as? NDKPrivateKeySigner else {
            throw NIP59Error.missingPrivateKey
        }

        // Serialize seal to JSON
        let sealJSON = try seal.toJSON()

        // Encrypt seal content using NIP-44 with random key
        let encryptedContent = try NIP44.encrypt(
            message: sealJSON,
            privateKey: privateKeySigner.privateKeyForNIP59,
            pubkey: recipientPubkey
        )

        // Create gift wrap event with randomized timestamp
        let randomizedTimestamp = randomizeTimestamp()
        let wrapPubkey = try await signer.pubkey

        // Build gift wrap event
        let giftWrapEvent = NDKEvent(
            id: "", // Will be set during signing
            pubkey: wrapPubkey,
            createdAt: randomizedTimestamp,
            kind: EventKind.giftWrap,
            tags: [["p", recipientPubkey]],
            content: encryptedContent,
            sig: "" // Will be set during signing
        )

        // Calculate event ID and sign
        let wrapId = try calculateEventId(event: giftWrapEvent)
        let signature = try await signer.sign(NDKEvent(
            id: wrapId,
            pubkey: giftWrapEvent.pubkey,
            createdAt: giftWrapEvent.createdAt,
            kind: giftWrapEvent.kind,
            tags: giftWrapEvent.tags,
            content: giftWrapEvent.content,
            sig: ""
        ))

        // Return signed gift wrap event
        return NDKEvent(
            id: wrapId,
            pubkey: giftWrapEvent.pubkey,
            createdAt: giftWrapEvent.createdAt,
            kind: giftWrapEvent.kind,
            tags: giftWrapEvent.tags,
            content: giftWrapEvent.content,
            sig: signature
        )
    }

    // MARK: - Unwrap Gift Wrap

    /// Unwraps a gift wrap event to get the sealed event inside
    /// - Parameters:
    ///   - giftWrap: The gift wrap event (kind 1059)
    ///   - recipientSigner: The recipient's signer (with private key)
    /// - Returns: The sealed event inside
    public static func unwrap(
        giftWrap: NDKEvent,
        recipientSigner: NDKSigner
    ) async throws -> NDKEvent {
        // Validate gift wrap
        guard giftWrap.kind == EventKind.giftWrap else {
            throw NIP59Error.invalidGiftWrap("Event must be a gift wrap (kind 1059)")
        }

        // For NIP-59, we need direct access to private key
        guard let privateKeySigner = recipientSigner as? NDKPrivateKeySigner else {
            throw NIP59Error.missingPrivateKey
        }

        // Decrypt content using gift wrap author's pubkey
        let decryptedJSON: String
        do {
            decryptedJSON = try NIP44.decrypt(
                encrypted: giftWrap.content,
                privateKey: privateKeySigner.privateKeyForNIP59,
                pubkey: giftWrap.pubkey
            )
        } catch {
            throw NIP59Error.decryptionFailed("Failed to decrypt gift wrap: \(error.localizedDescription)")
        }

        // Parse sealed event from JSON
        let sealEvent = try NDKEvent.fromJSON(decryptedJSON)

        // Validate it's a seal
        guard sealEvent.kind == EventKind.seal else {
            throw NIP59Error.unwrapFailed("Decrypted event is not a seal")
        }

        return sealEvent
    }

    // MARK: - Unseal Event

    /// Unseals a sealed event to get the original rumor
    /// - Parameters:
    ///   - seal: The sealed event (kind 13)
    ///   - recipientSigner: The recipient's signer (with private key)
    /// - Returns: The original rumor event
    public static func unseal(
        seal: NDKEvent,
        recipientSigner: NDKSigner
    ) async throws -> NDKEvent {
        // Validate seal
        guard seal.kind == EventKind.seal else {
            throw NIP59Error.invalidGiftWrap("Event must be a seal (kind 13)")
        }

        // For NIP-59, we need direct access to private key
        guard let privateKeySigner = recipientSigner as? NDKPrivateKeySigner else {
            throw NIP59Error.missingPrivateKey
        }

        // Decrypt content using seal author's pubkey
        let decryptedJSON: String
        do {
            decryptedJSON = try NIP44.decrypt(
                encrypted: seal.content,
                privateKey: privateKeySigner.privateKeyForNIP59,
                pubkey: seal.pubkey
            )
        } catch {
            throw NIP59Error.decryptionFailed("Failed to decrypt seal: \(error.localizedDescription)")
        }

        // Parse rumor event from JSON
        let rumor = try NDKEvent.fromJSON(decryptedJSON)

        return rumor
    }

    // MARK: - Full Wrap/Unwrap Flow

    /// Convenience method to seal and gift wrap an event in one operation
    /// - Parameters:
    ///   - rumor: The unsigned rumor event
    ///   - signer: The author's signer
    ///   - recipientPubkey: The recipient's public key
    /// - Returns: Gift wrapped event ready to send
    public static func sealAndWrap(
        rumor: NDKEvent,
        signer: NDKSigner,
        recipientPubkey: PublicKey
    ) async throws -> NDKEvent {
        let seal = try await seal(rumor: rumor, signer: signer, recipientPubkey: recipientPubkey)
        return try await wrap(seal: seal, recipientPubkey: recipientPubkey)
    }

    /// Convenience method to unwrap and unseal an event in one operation
    /// - Parameters:
    ///   - giftWrap: The gift wrap event
    ///   - recipientSigner: The recipient's signer
    /// - Returns: The original rumor event
    public static func unwrapAndUnseal(
        giftWrap: NDKEvent,
        recipientSigner: NDKSigner
    ) async throws -> NDKEvent {
        let seal = try await unwrap(giftWrap: giftWrap, recipientSigner: recipientSigner)
        let rumor = try await unseal(seal: seal, recipientSigner: recipientSigner)

        // NIP-59: the seal's pubkey is the true sender; the gift-wrap pubkey is an
        // ephemeral wrapping key. A malicious wrapper can put any pubkey into the
        // inner rumor, so we MUST verify the rumor's claimed author matches the
        // seal author to prevent sender forgery.
        guard rumor.pubkey == seal.pubkey else {
            throw NIP59Error.unwrapFailed("rumor.pubkey does not match seal.pubkey — sender forgery attempt")
        }

        return rumor
    }

    // MARK: - Utilities

    /// Randomizes a timestamp into the recent past to prevent send-time leakage.
    /// NIP-59 requires the wrap created_at be a randomized past timestamp; future
    /// timestamps are commonly rejected by relays (created_at > now + tolerance).
    private static func randomizeTimestamp() -> Timestamp {
        let twoDaysInSeconds: Int64 = 2 * 24 * 60 * 60
        let randomOffset = Int64.random(in: 0 ... twoDaysInSeconds)
        return .now - randomOffset
    }

    /// Calculate the event ID for an event
    private static func calculateEventId(event: NDKEvent) throws -> EventID {
        // Create array in the format for hashing: [0, pubkey, created_at, kind, tags, content]
        let eventArray: [Any] = [
            0,
            event.pubkey,
            event.createdAt,
            event.kind,
            event.tags,
            event.content
        ]

        // Serialize to canonical JSON
        let jsonData = try JSONSerialization.data(withJSONObject: eventArray, options: [.withoutEscapingSlashes])

        // Calculate SHA256 hash
        let hash = Crypto.sha256(jsonData)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
