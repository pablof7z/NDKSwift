import Foundation

/// NIP-17: Private Direct Messages
///
/// This module implements the NIP-17 standard for private direct messages in Nostr.
/// It builds on NIP-44 encryption and NIP-59 seals/gift wraps to provide metadata-private messaging.
///
/// Specification: https://github.com/nostr-protocol/nips/blob/master/17.md

// MARK: - Event Kinds for NIP-17

public extension EventKind {
    /// Sealed event (NIP-59)
    static let seal = 13
    
    /// Chat message (NIP-17)
    static let chatMessage = 14
    
    /// File message (NIP-17)  
    static let fileMessage = 15
    
    /// Gift wrap event (NIP-59)
    static let giftWrap = 1059
}

// MARK: - NIP-17 Data Structures

/// Represents a message recipient
public struct NIP17Recipient: Sendable {
    /// The recipient's public key (hex encoded)
    public let pubkey: PublicKey
    
    /// Optional relay URL where the recipient can be reached
    public let relayURL: RelayURL?
    
    public init(pubkey: PublicKey, relayURL: RelayURL? = nil) {
        self.pubkey = pubkey
        self.relayURL = relayURL
    }
}

/// Represents a message being replied to
public struct NIP17ReplyTo: Sendable {
    /// The event ID being replied to
    public let eventId: EventID
    
    /// Optional relay URL where the original message can be found
    public let relayURL: RelayURL?
    
    public init(eventId: EventID, relayURL: RelayURL? = nil) {
        self.eventId = eventId
        self.relayURL = relayURL
    }
}

/// Configuration for creating NIP-17 messages
public struct NIP17MessageConfig: Sendable {
    /// Recipients of the message
    public let recipients: [NIP17Recipient]
    
    /// Optional conversation title/subject
    public let subject: String?
    
    /// Optional event being replied to
    public let replyTo: NIP17ReplyTo?
    
    /// Additional tags to include in the message
    public let additionalTags: [Tag]
    
    public init(
        recipients: [NIP17Recipient],
        subject: String? = nil,
        replyTo: NIP17ReplyTo? = nil,
        additionalTags: [Tag] = []
    ) {
        self.recipients = recipients
        self.subject = subject
        self.replyTo = replyTo
        self.additionalTags = additionalTags
    }
}

/// Result of wrapping events for multiple recipients
public struct NIP17WrappedEvents: Sendable {
    /// Wrapped events ready to be published, indexed by recipient pubkey
    public let events: [PublicKey: NDKEvent]
    
    /// The original sealed event (before gift wrapping)
    public let sealedEvent: NDKEvent
}

// MARK: - NIP-17 Errors

public enum NIP17Error: LocalizedError, Equatable {
    case noRecipients
    case invalidRecipient(String)
    case sealingFailed(String)
    case wrapFailed(String)
    case unwrapFailed(String)
    case invalidEventKind(Int)
    case missingNIP59Implementation
    
    public var errorDescription: String? {
        switch self {
        case .noRecipients:
            return "No recipients specified for the message"
        case .invalidRecipient(let pubkey):
            return "Invalid recipient public key: \(pubkey)"
        case .sealingFailed(let reason):
            return "Failed to seal event: \(reason)"
        case .wrapFailed(let reason):
            return "Failed to wrap event: \(reason)"
        case .unwrapFailed(let reason):
            return "Failed to unwrap event: \(reason)"
        case .invalidEventKind(let kind):
            return "Invalid event kind for NIP-17: \(kind)"
        case .missingNIP59Implementation:
            return "NIP-59 implementation is required for NIP-17"
        }
    }
}