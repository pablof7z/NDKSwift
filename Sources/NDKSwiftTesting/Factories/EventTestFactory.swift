//
// EventTestFactory.swift
// NDKSwift
//
// Factory methods for creating test events with common patterns.
//

import Foundation
import NDKSwiftCore

/// Factory for creating test events with common Nostr patterns
///
/// Example:
/// ```swift
/// // Create a text note
/// let note = EventTestFactory.textNote(content: "Hello!")
///
/// // Create a reply
/// let reply = EventTestFactory.reply(to: parentEvent, content: "Nice!")
///
/// // Create a metadata event
/// let profile = EventTestFactory.metadata(name: "Alice", about: "Testing")
/// ```
public enum EventTestFactory {
    // MARK: - Text Notes (kind: 1)

    /// Create a text note event
    public static func textNote(
        content: String = "Test note",
        pubkey: String = TestKeyPairs.alice.publicKey,
        tags: [[String]] = [],
        createdAt: Timestamp = Timestamp.now
    ) -> NDKEvent {
        NDKEvent.test(
            kind: 1,
            content: content,
            tags: tags,
            pubkey: pubkey,
            createdAt: createdAt
        )
    }

    // MARK: - Replies (kind: 1111 or 1)

    /// Create a generic reply event (kind: 1111) with NIP-22 tags
    ///
    /// - Parameters:
    ///   - rootEvent: The thread root event (uppercase E tag)
    ///   - parentEvent: The event being replied to (lowercase e tag), defaults to rootEvent
    ///   - content: Reply content
    ///   - pubkey: Author's public key
    public static func reply(
        toRoot rootEvent: NDKEvent,
        parent parentEvent: NDKEvent? = nil,
        content: String = "Test reply",
        pubkey: String = TestKeyPairs.bob.publicKey,
        createdAt: Timestamp = Timestamp.now
    ) -> NDKEvent {
        var tags: [[String]] = [
            // Uppercase E for root (NIP-22)
            ["E", rootEvent.id],
            ["K", String(rootEvent.kind)],
            ["P", rootEvent.pubkey]
        ]

        // Add lowercase e for parent if different from root
        if let parentEvent, parentEvent.id != rootEvent.id {
            tags.append(["e", parentEvent.id, "", "reply"])
            tags.append(["p", parentEvent.pubkey])
        }

        return NDKEvent.test(
            kind: 1111,
            content: content,
            tags: tags,
            pubkey: pubkey,
            createdAt: createdAt
        )
    }

    /// Create a kind:1 reply with NIP-10 tags
    public static func textNoteReply(
        to parentEvent: NDKEvent,
        content: String = "Test reply",
        pubkey: String = TestKeyPairs.bob.publicKey,
        createdAt: Timestamp = Timestamp.now
    ) -> NDKEvent {
        let tags: [[String]] = [
            ["e", parentEvent.id, "", "reply"],
            ["p", parentEvent.pubkey]
        ]

        return NDKEvent.test(
            kind: 1,
            content: content,
            tags: tags,
            pubkey: pubkey,
            createdAt: createdAt
        )
    }

    // MARK: - Metadata (kind: 0)

    /// Create a metadata event
    public static func metadata(
        name: String = "Test User",
        about: String = "Test user description",
        picture: String? = nil,
        nip05: String? = nil,
        pubkey: String = TestKeyPairs.alice.publicKey,
        createdAt: Timestamp = Timestamp.now
    ) -> NDKEvent {
        var metadata: [String: String] = [
            "name": name,
            "about": about
        ]
        if let picture { metadata["picture"] = picture }
        if let nip05 { metadata["nip05"] = nip05 }

        let content = (try? JSONSerialization.data(withJSONObject: metadata))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

        return NDKEvent.test(
            kind: 0,
            content: content,
            pubkey: pubkey,
            createdAt: createdAt
        )
    }

    // MARK: - Contact List (kind: 3)

    /// Create a contact list event
    public static func contactList(
        contacts: [String],
        pubkey: String = TestKeyPairs.alice.publicKey,
        createdAt: Timestamp = Timestamp.now
    ) -> NDKEvent {
        let tags = contacts.map { ["p", $0] }
        return NDKEvent.test(
            kind: 3,
            content: "",
            tags: tags,
            pubkey: pubkey,
            createdAt: createdAt
        )
    }

    // MARK: - Reactions (kind: 7)

    /// Create a reaction event
    public static func reaction(
        to event: NDKEvent,
        content: String = "+",
        pubkey: String = TestKeyPairs.bob.publicKey,
        createdAt: Timestamp = Timestamp.now
    ) -> NDKEvent {
        let tags: [[String]] = [
            ["e", event.id],
            ["p", event.pubkey]
        ]
        return NDKEvent.test(
            kind: 7,
            content: content,
            tags: tags,
            pubkey: pubkey,
            createdAt: createdAt
        )
    }

    // MARK: - Deletion (kind: 5)

    /// Create a deletion event
    public static func deletion(
        eventIds: [String],
        reason: String = "Test deletion",
        pubkey: String = TestKeyPairs.alice.publicKey,
        createdAt: Timestamp = Timestamp.now
    ) -> NDKEvent {
        let tags = eventIds.map { ["e", $0] }
        return NDKEvent.test(
            kind: 5,
            content: reason,
            tags: tags,
            pubkey: pubkey,
            createdAt: createdAt
        )
    }

    // MARK: - Typing Indicators (kind: 24111, 24112)

    /// Create a user typing indicator event
    public static func typingIndicator(
        threadID: String,
        isAgent: Bool = false,
        pubkey: String = TestKeyPairs.alice.publicKey,
        createdAt: Timestamp = Timestamp.now
    ) -> NDKEvent {
        let kind: Kind = isAgent ? 24_112 : 24_111
        return NDKEvent.test(
            kind: kind,
            content: "",
            tags: [["e", threadID]],
            pubkey: pubkey,
            createdAt: createdAt
        )
    }

    // MARK: - Streaming Delta (kind: 21111)

    /// Create a streaming delta event for AI responses
    public static func streamingDelta(
        messageID: String,
        delta: String,
        pubkey: String = TestKeyPairs.alice.publicKey,
        createdAt: Timestamp = Timestamp.now
    ) -> NDKEvent {
        NDKEvent.test(
            kind: 21_111,
            content: delta,
            tags: [["e", messageID]],
            pubkey: pubkey,
            createdAt: createdAt
        )
    }
}
