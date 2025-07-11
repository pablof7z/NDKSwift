import Foundation

/// NDKImage represents a Nostr image event (kind 20)
public struct NDKImage {
    // MARK: - Static Properties

    /// The primary kind for image events
    public static let kind: Kind = EventKind.image

    /// All supported kinds for this event type
    public static let kinds: [Kind] = [EventKind.image]

    // MARK: - Properties

    /// The underlying event
    public let event: NDKEvent

    /// Cached imeta tags for performance
    private var _imetas: [NDKImetaTag]?

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

    /// The event kind (always EventKind.image for NDKImage)
    public var kind: Kind {
        return event.kind
    }

    /// The event content
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

    /// Initialize a new NDKImage event
    public init(ndk: NDK? = nil, pubkey: PublicKey = "") {
        // Create a placeholder event - this will need to be properly signed later
        self.event = NDKEvent(
            id: "", // Will be set when signed
            pubkey: pubkey,
            createdAt: Timestamp(Date().timeIntervalSince1970),
            kind: NDKImage.kind,
            tags: [],
            content: "",
            sig: "" // Will be set when signed
        )
    }
    

    /// Create an NDKImage from an existing NDKEvent
    public init(event: NDKEvent) {
        self.event = event
    }

    /// Create an NDKImage from an existing NDKEvent
    public static func from(event: NDKEvent) -> NDKImage {
        return NDKImage(event: event)
    }

    // MARK: - Validation

    /// Check if this image event is valid (has at least one imeta tag with a URL)
    public var isValid: Bool {
        return !imetas.isEmpty && imetas.contains { $0.url != nil }
    }

    // MARK: - Imeta Tag Management

    /// Get all imeta tags from this image event
    public var imetas: [NDKImetaTag] {
        return event.tags
            .filter { $0.first == "imeta" }
            .compactMap { ImetaUtils.mapImetaTag($0) }
            .filter { $0.url != nil }
    }

    // Note: NDKEvent is immutable, so we cannot modify tags.
    // To create a new image with different imeta tags, use NDKEventBuilder.

    // MARK: - Convenience Methods

    // Note: NDKEvent is immutable, so we cannot add tags.
    // To create a new image with additional imeta tags, use NDKEventBuilder.

    /// Get the primary image URL (from the first imeta tag)
    public var primaryImageURL: String? {
        return imetas.first?.url
    }

    /// Get all image URLs
    public var imageURLs: [String] {
        get async {
            let metaTags = await imetas
            return metaTags.compactMap { $0.url }
        }
    }

    /// Get dimensions for the primary image
    public var primaryImageDimensions: (width: Int, height: Int)? {
        get async {
            let metaTags = await imetas
            guard let dim = metaTags.first?.dim else { return nil }
            let parts = dim.split(separator: "x")
            guard parts.count == 2,
                  let width = Int(parts[0]),
                  let height = Int(parts[1]) else { return nil }
            return (width, height)
        }
    }

    // MARK: - Convenience Tag Methods

    /// Add a tag to the image
    public mutating func addTag(_ tag: [String]) async {
        await event.addTag(tag)
    }

    /// Get tags matching a specific tag name
    public func tags(withName tagName: String) -> [[String]] {
        return event.tags(withName: tagName)
    }

    /// Get the first value of a tag with the given name
    public func tagValue(_ tagName: String) -> String? {
        return event.tagValue(tagName)
    }
}
