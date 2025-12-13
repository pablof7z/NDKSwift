import Foundation

/// Represents a Follow Pack event (NIP-51, kinds 39089 and 39092)
/// Follow packs are collections of pubkeys with metadata like title, description, and image
public struct NDKFollowPack {
    // MARK: - Properties

    /// The underlying NDK event
    public let event: NDKEvent

    /// Associated NDK instance
    public let ndk: NDK?

    // MARK: - Static Properties

    /// Supported kinds for follow packs
    public static let supportedKinds = [EventKind.followPack, EventKind.mediaFollowPack]

    // MARK: - Initialization

    public init(event: NDKEvent, ndk: NDK? = nil) {
        self.event = event
        self.ndk = ndk
    }

    /// Create a follow pack from an NDKEvent
    public static func from(event: NDKEvent, ndk: NDK? = nil) -> NDKFollowPack {
        return NDKFollowPack(event: event, ndk: ndk)
    }

    // MARK: - Computed Properties

    /// Get the title from tags
    public var title: String? {
        return getTagValue("title")
    }

    /// Get the description from tags
    public var description: String? {
        return getTagValue("description")
    }

    /// Get the image
    /// Looks for an imeta tag first (returns its url), then falls back to the image tag
    public var image: String? {
        // Look for an "imeta" tag first
        if let imetaTag = event.tags.first(where: { $0.first == "imeta" }),
           let imeta = ImetaUtils.mapImetaTag(imetaTag),
           let url = imeta.url
        {
            return url
        }
        // Fallback to "image" tag
        return getTagValue("image")
    }

    /// Get the identifier (d tag) for parameterized replaceable events
    public var identifier: String? {
        return getTagValue("d")
    }

    // MARK: - Private Methods

    /// Helper to get tag value by name
    private func getTagValue(_ tagName: String) -> String? {
        return event.tags.first { $0.count > 1 && $0[0] == tagName }?[1]
    }

    /// Get all pubkeys from p tags
    public var pubkeys: [String] {
        return event.tags
            .filter { $0.count > 1 && $0[0] == "p" }
            .map { $0[1] }
    }

    /// Check if a pubkey is in the follow pack
    public func containsPubkey(_ pubkey: String) -> Bool {
        return pubkeys.contains(pubkey)
    }
}

// MARK: - Builder Pattern

/// Builder for creating follow packs
public class NDKFollowPackBuilder {
    private let ndk: NDK
    private var kind: Kind = EventKind.followPack
    private var tags: [Tag] = []
    private var content: String = ""
    private var identifier: String?

    public init(ndk: NDK) {
        self.ndk = ndk
    }

    /// Set the kind (regular or media follow pack)
    public func kind(_ kind: Kind) -> NDKFollowPackBuilder {
        self.kind = kind
        return self
    }

    /// Set the title
    public func title(_ title: String) -> NDKFollowPackBuilder {
        tags = tags.filter { $0.first != "title" }
        tags.append(["title", title])
        return self
    }

    /// Set the description
    public func description(_ description: String) -> NDKFollowPackBuilder {
        tags = tags.filter { $0.first != "description" }
        tags.append(["description", description])
        return self
    }

    /// Set the identifier (d tag)
    public func identifier(_ identifier: String) -> NDKFollowPackBuilder {
        self.identifier = identifier
        tags = tags.filter { $0.first != "d" }
        tags.append(["d", identifier])
        return self
    }

    /// Set the image URL
    public func image(_ url: String) -> NDKFollowPackBuilder {
        tags = tags.filter { $0.first != "image" && $0.first != "imeta" }
        tags.append(["image", url])
        return self
    }

    /// Set the image with NDKImetaTag
    public func image(_ imeta: NDKImetaTag) -> NDKFollowPackBuilder {
        tags = tags.filter { $0.first != "image" && $0.first != "imeta" }
        tags.append(ImetaUtils.imetaTagToTag(imeta))
        if let url = imeta.url {
            tags.append(["image", url])
        }
        return self
    }

    /// Add pubkeys
    public func pubkeys(_ pubkeys: [String]) -> NDKFollowPackBuilder {
        tags = tags.filter { $0.first != "p" }
        for pubkey in pubkeys {
            tags.append(["p", pubkey])
        }
        return self
    }

    /// Add a single pubkey
    public func addPubkey(_ pubkey: String) -> NDKFollowPackBuilder {
        tags.append(["p", pubkey])
        return self
    }

    /// Set content
    public func content(_ content: String) -> NDKFollowPackBuilder {
        self.content = content
        return self
    }

    /// Build and sign the follow pack
    public func build() async throws -> NDKFollowPack {
        let eventBuilder = NDKEventBuilder(ndk: ndk)
            .kind(kind)
            .content(content)

        // Add all tags
        for tag in tags {
            eventBuilder.tag(tag)
        }

        let event = try await eventBuilder.build()
        return NDKFollowPack(event: event, ndk: ndk)
    }

    /// Build, sign, and publish the follow pack
    public func publish() async throws -> NDKFollowPack {
        let followPack = try await build()
        _ = try await ndk.publish(followPack.event)
        return followPack
    }
}
