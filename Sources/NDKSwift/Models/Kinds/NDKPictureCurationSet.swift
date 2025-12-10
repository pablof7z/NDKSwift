import Foundation

/// NDKPictureCurationSet represents a Nostr picture curation set event (kind 30006)
/// Following NIP-51 pattern for parameterized replaceable lists of pictures (kind 20)
public struct NDKPictureCurationSet: Sendable {
    // MARK: - Static Properties

    /// The kind for picture curation set events
    public static let kind: Kind = EventKind.pictureCurationSet

    // MARK: - Properties

    /// The underlying event
    public let event: NDKEvent

    // MARK: - Event Property Forwarding

    public var id: EventID { event.id }
    public var pubkey: PublicKey { event.pubkey }
    public var createdAt: Timestamp { event.createdAt }
    public var content: String { event.content }
    public var tags: [[String]] { event.tags }
    public var sig: String { event.sig }

    // MARK: - Initialization

    public init(event: NDKEvent) {
        self.event = event
    }

    public static func from(event: NDKEvent) -> NDKPictureCurationSet {
        NDKPictureCurationSet(event: event)
    }

    // MARK: - List Metadata Properties

    /// The unique identifier for this set (d-tag value)
    public var identifier: String? {
        tagValue(NostrConstants.TagName.identifier)
    }

    /// The title of this collection
    public var title: String? {
        tagValue(NostrConstants.TagName.title)
    }

    /// Description of this collection
    public var listDescription: String? {
        tagValue(NostrConstants.TagName.description)
    }

    /// Cover image URL for this collection
    public var image: String? {
        tagValue(NostrConstants.TagName.image)
    }

    // MARK: - Picture References

    /// All picture event IDs in this set (from "e" tags)
    public var pictureEventIds: [EventID] {
        event.tags
            .filter { $0.first == NostrConstants.TagName.event && $0.count > 1 }
            .map { $0[1] }
    }

    /// Number of pictures in this collection
    public var count: Int {
        pictureEventIds.count
    }

    /// Check if this set contains a specific picture event ID
    public func contains(eventId: EventID) -> Bool {
        pictureEventIds.contains(eventId)
    }

    // MARK: - Tag Helpers

    public func tags(withName tagName: String) -> [[String]] {
        event.tags.filter { $0.first == tagName }
    }

    public func tagValue(_ tagName: String) -> String? {
        let matching = tags(withName: tagName)
        return matching.first?.count ?? 0 > 1 ? matching.first?[1] : nil
    }

    // MARK: - Address for Referencing

    /// The "a" tag coordinate for this set: "30006:pubkey:identifier"
    public var tagAddress: String {
        "\(NDKPictureCurationSet.kind):\(pubkey):\(identifier ?? "")"
    }
}
