import Foundation

/// NIP-17: Private Direct Messages
///
/// This module implements the NIP-17 private messaging protocol using NIP-44 encryption
/// and NIP-59 gift wrapping for metadata privacy.
public enum NIP17 {
    // MARK: - Create Event

    /// Creates a base private message event (kind 14 or 15)
    /// - Parameters:
    ///   - content: The message content
    ///   - config: Configuration including recipients, subject, and reply-to
    ///   - senderPubkey: The sender's public key
    ///   - kind: Event kind (default: .chatMessage)
    /// - Returns: Unsigned event (rumor) ready to be sealed
    public static func createEvent(
        content: String,
        config: NIP17MessageConfig,
        senderPubkey: PublicKey,
        kind: Kind = EventKind.chatMessage
    ) throws -> NDKEvent {
        // Validate kind
        guard kind == EventKind.chatMessage || kind == EventKind.fileMessage else {
            throw NIP17Error.invalidEventKind(kind)
        }

        // Validate recipients
        guard !config.recipients.isEmpty else {
            throw NIP17Error.noRecipients
        }

        // Build tags
        var tags: [Tag] = []

        // Add recipient tags
        for recipient in config.recipients {
            var tag = ["p", recipient.pubkey]
            if let relay = recipient.relayURL {
                tag.append(relay)
            }
            tags.append(tag)
        }

        // Add subject tag if provided
        if let subject = config.subject {
            tags.append(["subject", subject])
        }

        // Add reply tags if provided
        if let replyTo = config.replyTo {
            var tag = ["e", replyTo.eventId, "", "reply"]
            if let relay = replyTo.relayURL {
                tag[2] = relay
            }
            tags.append(tag)
        }

        // Add any additional tags
        tags.append(contentsOf: config.additionalTags)

        // Create unsigned event (rumor)
        return NDKEvent(
            kind: kind,
            content: content,
            tags: tags,
            pubkey: senderPubkey,
            createdAt: .now
        )
    }

    // MARK: - Wrap Event

    /// Wraps a private message event for a specific recipient
    /// - Parameters:
    ///   - event: The message event (rumor)
    ///   - signer: The sender's signer
    ///   - recipient: The recipient to wrap for
    /// - Returns: Gift wrapped event ready to send
    public static func wrapEvent(
        _ event: NDKEvent,
        signer: NDKSigner,
        recipient: NIP17Recipient
    ) async throws -> NDKEvent {
        // Validate event kind
        guard event.kind == EventKind.chatMessage || event.kind == EventKind.fileMessage else {
            throw NIP17Error.invalidEventKind(event.kind)
        }

        // Use NIP-59 to seal and wrap
        return try await NIP59.sealAndWrap(
            rumor: event,
            signer: signer,
            recipientPubkey: recipient.pubkey
        )
    }

    // MARK: - Wrap Many Events

    /// Creates wrapped events for multiple recipients
    /// - Parameters:
    ///   - event: The message event (rumor)
    ///   - signer: The sender's signer
    ///   - recipients: Recipients to wrap for (if empty, uses event's p tags)
    /// - Returns: Wrapped events ready to send
    public static func wrapManyEvents(
        _ event: NDKEvent,
        signer: NDKSigner,
        recipients: [NIP17Recipient]? = nil
    ) async throws -> NIP17WrappedEvents {
        // Get recipients from parameter or event tags
        let targetRecipients: [NIP17Recipient]
        if let recipients = recipients, !recipients.isEmpty {
            targetRecipients = recipients
        } else {
            // Extract recipients from p tags
            targetRecipients = event.tags
                .filter { $0.count >= 2 && $0[0] == "p" }
                .map { tag in
                    let pubkey = tag[1]
                    let relay = tag.count > 2 ? tag[2] : nil
                    return NIP17Recipient(pubkey: pubkey, relayURL: relay)
                }
        }

        guard !targetRecipients.isEmpty else {
            throw NIP17Error.noRecipients
        }

        // Include sender as the first recipient
        let senderPubkey = try await signer.pubkey
        let allRecipients = [NIP17Recipient(pubkey: senderPubkey)] + targetRecipients

        // Seal the event once
        let sealedEvent = try await NIP59.seal(
            rumor: event,
            signer: signer,
            recipientPubkey: senderPubkey // Self-encrypt for the seal
        )

        // Create wrapped events for each recipient
        var wrappedEvents: [PublicKey: NDKEvent] = [:]

        for recipient in allRecipients {
            let wrapped = try await NIP59.wrap(
                seal: sealedEvent,
                recipientPubkey: recipient.pubkey
            )
            wrappedEvents[recipient.pubkey] = wrapped
        }

        return NIP17WrappedEvents(
            events: wrappedEvents,
            sealedEvent: sealedEvent
        )
    }

    // MARK: - Unwrap Event

    /// Unwraps a received private message
    /// - Parameters:
    ///   - giftWrap: The gift wrapped event
    ///   - recipientSigner: The recipient's signer
    /// - Returns: The original message event
    public static func unwrapEvent(
        _ giftWrap: NDKEvent,
        recipientSigner: NDKSigner
    ) async throws -> NDKEvent {
        // Use NIP-59 to unwrap and unseal
        let rumor = try await NIP59.unwrapAndUnseal(
            giftWrap: giftWrap,
            recipientSigner: recipientSigner
        )

        // Validate it's a valid NIP-17 message
        guard rumor.kind == EventKind.chatMessage || rumor.kind == EventKind.fileMessage else {
            throw NIP17Error.invalidEventKind(rumor.kind)
        }

        return rumor
    }

    // MARK: - Convenience Methods

    /// Send a simple text message to a recipient
    /// - Parameters:
    ///   - message: The message text
    ///   - to: The recipient
    ///   - signer: The sender's signer
    ///   - subject: Optional conversation subject
    /// - Returns: Gift wrapped event ready to send
    public static func sendMessage(
        _ message: String,
        to recipient: NIP17Recipient,
        signer: NDKSigner,
        subject: String? = nil
    ) async throws -> NDKEvent {
        let config = NIP17MessageConfig(
            recipients: [recipient],
            subject: subject
        )

        let event = try createEvent(
            content: message,
            config: config,
            senderPubkey: await signer.pubkey
        )

        return try await wrapEvent(event, signer: signer, recipient: recipient)
    }

    /// Send a message to multiple recipients
    /// - Parameters:
    ///   - message: The message text
    ///   - to: The recipients
    ///   - signer: The sender's signer
    ///   - subject: Optional conversation subject
    /// - Returns: Wrapped events for each recipient
    public static func sendToMany(
        _ message: String,
        to recipients: [NIP17Recipient],
        signer: NDKSigner,
        subject: String? = nil
    ) async throws -> NIP17WrappedEvents {
        let config = NIP17MessageConfig(
            recipients: recipients,
            subject: subject
        )

        let event = try createEvent(
            content: message,
            config: config,
            senderPubkey: await signer.pubkey
        )

        return try await wrapManyEvents(event, signer: signer, recipients: recipients)
    }
}
