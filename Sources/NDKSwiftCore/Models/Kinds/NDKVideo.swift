import CoreGraphics
import Foundation

/// NDKVideo represents a Nostr short-form video event (kind 22) per NIP-71
public struct NDKVideo {
    // MARK: - Static Properties

    /// The primary kind for short-form video events (NIP-71)
    public static let kind: Kind = 22

    /// All supported kinds for this event type
    public static let kinds: [Kind] = [22]

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

    /// The event kind (always 22 for NDKVideo)
    public var kind: Kind {
        return event.kind
    }

    /// The event content (video description/summary)
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

    /// Create an NDKVideo from an existing NDKEvent
    public init(event: NDKEvent) {
        self.event = event
    }

    /// Create an NDKVideo from an existing NDKEvent
    public static func from(event: NDKEvent) -> NDKVideo {
        return NDKVideo(event: event)
    }

    // MARK: - Validation

    /// Check if this video event is valid (has at least one imeta tag with a URL)
    public var isValid: Bool {
        let metaTags = imetas
        return !metaTags.isEmpty && metaTags.contains { $0.url != nil }
    }

    // MARK: - Imeta Tag Management

    /// Get all imeta tags from this video event
    public var imetas: [NDKImetaTag] {
        return event.tags
            .filter { $0.first == "imeta" }
            .compactMap { ImetaUtils.mapImetaTag($0) }
            .filter { $0.url != nil }
    }

    // MARK: - Video Properties

    /// Get the primary video URL (from the first imeta tag)
    public var primaryVideoURL: String? {
        return imetas.first?.url
    }

    /// Get all video URLs
    public var videoURLs: [String] {
        return imetas.compactMap { $0.url }
    }

    /// Get dimensions for the primary video
    public var primaryVideoDimensions: (width: Int, height: Int)? {
        guard let dim = imetas.first?.dim else { return nil }
        let parts = dim.split(separator: "x")
        guard parts.count == 2,
              let width = Int(parts[0]),
              let height = Int(parts[1]) else { return nil }
        return (width, height)
    }

    /// Get the blurhash for the primary video thumbnail
    public var primaryBlurhash: String? {
        return imetas.first?.blurhash
    }

    /// Get the alt text for the primary video (accessibility)
    public var primaryAlt: String? {
        return imetas.first?.alt
    }

    /// Get the aspect ratio for the primary video (width / height)
    public var primaryAspectRatio: CGFloat? {
        guard let dims = primaryVideoDimensions, dims.height > 0 else { return nil }
        return CGFloat(dims.width) / CGFloat(dims.height)
    }

    /// Get the MIME type for the primary video
    public var primaryMimeType: String? {
        return imetas.first?.m
    }

    /// Get the thumbnail/preview image URL
    /// Checks multiple sources: imeta "image" field, "thumb" tag, "image" tag
    public var thumbnailURL: String? {
        // 1. Check imeta additionalFields for "image" key (NIP-71 style)
        if let firstImeta = imetas.first,
           let imageUrl = firstImeta.additionalFields["image"] {
            return imageUrl
        }

        // 2. Check for "thumb" tag at event level
        if let thumbUrl = tagValue("thumb") {
            return thumbUrl
        }

        // 3. Check for "image" tag at event level
        if let imageUrl = tagValue("image") {
            return imageUrl
        }

        // 4. Check for "preview" in additionalFields
        if let firstImeta = imetas.first,
           let previewUrl = firstImeta.additionalFields["preview"] {
            return previewUrl
        }

        return nil
    }

    /// Get the video duration in seconds from imeta tag
    public var duration: TimeInterval? {
        guard let firstImeta = imetas.first,
              let durationStr = firstImeta.additionalFields["duration"],
              let durationValue = Double(durationStr) else { return nil }
        return durationValue
    }

    /// Get the title tag value (NIP-71)
    public var title: String? {
        return tagValue("title")
    }

    // MARK: - Convenience Tag Methods

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
