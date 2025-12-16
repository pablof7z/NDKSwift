import Foundation

/// NDKArticle represents a Nostr long-form article event (kind 30023)
public struct NDKArticle {
    // MARK: - Static Properties

    /// The primary kind for article events
    public static let kind: Kind = EventKind.longFormContent

    /// All supported kinds for this event type
    public static let kinds: [Kind] = [EventKind.longFormContent]

    // MARK: - Properties

    /// The underlying event
    public let event: NDKEvent

    // MARK: - Event Property Forwarding

    /// The event ID
    public var id: EventID {
        return event.id
    }

    /// The public key of the event creator
    public var pubkey: PublicKey {
        return event.pubkey
    }

    /// The timestamp when the event was created
    public var createdAt: Timestamp {
        return event.createdAt
    }

    /// The event kind (always EventKind.longFormContent for NDKArticle)
    public var kind: Kind {
        return event.kind
    }

    /// The article content (markdown)
    public var content: String {
        return event.content
    }

    /// The event tags
    public var tags: [[String]] {
        return event.tags
    }

    /// The event signature
    public var sig: String {
        return event.sig
    }

    // MARK: - Initialization

    /// Create an NDKArticle from an existing NDKEvent
    public init(event: NDKEvent) {
        self.event = event
    }

    /// Create an NDKArticle from an existing NDKEvent
    public static func from(event: NDKEvent) -> NDKArticle {
        return NDKArticle(event: event)
    }

    // MARK: - Article-Specific Properties

    /// The article title (from "title" tag)
    public var title: String? {
        return tagValue("title")
    }

    /// The article summary (from "summary" or "alt" tag)
    public var summary: String? {
        return tagValue("summary") ?? tagValue("alt")
    }

    /// The article cover image URL (from "image" tag)
    public var imageURL: URL? {
        guard let imageStr = tagValue("image") else { return nil }
        return URL(string: imageStr)
    }

    /// The published timestamp (from "published_at" tag)
    public var publishedAt: Date? {
        guard let timestamp = tagValue("published_at"),
              let timeInterval = TimeInterval(timestamp) else { return nil }
        return Date(timeIntervalSince1970: timeInterval)
    }

    /// Estimated reading time in minutes (based on 200 words per minute)
    public var readingTime: Int {
        let wordCount = content.split(separator: " ").count
        return max(1, wordCount / 200)
    }

    /// The d-tag identifier (for replaceable events)
    public var identifier: String? {
        return tagValue("d")
    }

    // MARK: - Validation

    /// Check if this article is valid (has a title)
    public var isValid: Bool {
        return title != nil && !title!.isEmpty
    }

    // MARK: - Tag Helper Methods

    /// Get tags matching a specific tag name
    public func tags(withName tagName: String) -> [[String]] {
        return event.tags.filter { $0.first == tagName }
    }

    /// Get the first value of a tag with the given name
    public func tagValue(_ tagName: String) -> String? {
        let matchingTags = tags(withName: tagName)
        return matchingTags.first?.count ?? 0 > 1 ? matchingTags.first?[1] : nil
    }
}
