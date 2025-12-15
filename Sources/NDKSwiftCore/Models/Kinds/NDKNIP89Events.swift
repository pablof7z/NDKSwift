import Foundation

// MARK: - NIP-89 Event Kinds

/// NIP-89 Application Handler kinds
public enum NIP89Kind: Kind {
    /// Recommendation event (kind 31989)
    case recommendation = 31989

    /// Handler information event (kind 31990)
    case handlerInfo = 31990
}

// MARK: - NIP-89 Handler Information

/// Represents a NIP-89 handler information event (kind 31990)
public struct NIP89HandlerInfo {
    /// The supported event kinds
    public let supportedKinds: [Kind]

    /// The handler URLs by platform
    public let handlerURLs: [String: String]

    /// Optional metadata about the handler
    public let metadata: NIP89HandlerMetadata?

    /// The d-tag identifier for this handler
    public let identifier: String

    public init(supportedKinds: [Kind], handlerURLs: [String: String], metadata: NIP89HandlerMetadata? = nil, identifier: String) {
        self.supportedKinds = supportedKinds
        self.handlerURLs = handlerURLs
        self.metadata = metadata
        self.identifier = identifier
    }
}

/// Metadata for NIP-89 handlers
public struct NIP89HandlerMetadata: Codable {
    /// Application name
    public let name: String?

    /// Application description
    public let about: String?

    /// Application icon URL
    public let picture: String?

    /// Application website
    public let website: String?

    /// Lightning address for the application
    public let lud16: String?

    public init(name: String? = nil, about: String? = nil, picture: String? = nil, website: String? = nil, lud16: String? = nil) {
        self.name = name
        self.about = about
        self.picture = picture
        self.website = website
        self.lud16 = lud16
    }
}

// MARK: - NIP-89 Recommendation

/// Represents a NIP-89 recommendation event (kind 31989)
public struct NIP89Recommendation {
    /// The event kind being recommended
    public let eventKind: Kind

    /// The recommended handlers
    public let handlers: [NIP89HandlerReference]

    public init(eventKind: Kind, handlers: [NIP89HandlerReference]) {
        self.eventKind = eventKind
        self.handlers = handlers
    }
}

/// Reference to a NIP-89 handler
public struct NIP89HandlerReference {
    /// The handler address (31990:pubkey:identifier)
    public let address: String

    /// Optional relay hint
    public let relay: String?

    /// Platform this handler is for
    public let platform: String?

    public init(address: String, relay: String? = nil, platform: String? = nil) {
        self.address = address
        self.relay = relay
        self.platform = platform
    }
}

// MARK: - NDKEvent Extensions for NIP-89

public extension NDKEvent {
    /// Parse this event as a NIP-89 handler information event
    ///
    /// - Returns: Handler information if this is a valid kind 31990 event
    func asNIP89HandlerInfo() -> NIP89HandlerInfo? {
        guard kind == NIP89Kind.handlerInfo.rawValue else { return nil }

        // Get the d-tag identifier
        guard let identifier = tagValue("d") else { return nil }

        // Parse supported kinds from k tags
        let supportedKinds = tags(withName: "k").compactMap { tag -> Kind? in
            guard tag.count >= 2, let kind = Kind(tag[1]) else { return nil }
            return kind
        }

        // Parse handler URLs from platform tags
        var handlerURLs: [String: String] = [:]
        for tag in tags where tag.count >= 2 && tag[0] != "k" && tag[0] != "d" {
            let platform = tag[0]
            let url = tag[1]
            handlerURLs[platform] = url
        }

        // Parse metadata from content if present
        let metadata: NIP89HandlerMetadata?
        if !content.isEmpty {
            do {
                guard let data = content.data(using: .utf8) else {
                    NDKLogger.log(.warning, category: .event, "Failed to convert NIP-89 handler content to UTF-8")
                    metadata = nil
                    return NIP89HandlerInfo(
                        supportedKinds: supportedKinds,
                        handlerURLs: handlerURLs,
                        metadata: metadata,
                        identifier: identifier
                    )
                }
                metadata = try JSONCoding.decode(NIP89HandlerMetadata.self, from: data)
            } catch {
                NDKLogger.log(.warning, category: .event, "Failed to parse NIP-89 handler metadata: \(error)")
                metadata = nil
            }
        } else {
            metadata = nil
        }

        return NIP89HandlerInfo(
            supportedKinds: supportedKinds,
            handlerURLs: handlerURLs,
            metadata: metadata,
            identifier: identifier
        )
    }

    /// Parse this event as a NIP-89 recommendation event
    ///
    /// - Returns: Recommendation information if this is a valid kind 31989 event
    func asNIP89Recommendation() -> NIP89Recommendation? {
        guard kind == NIP89Kind.recommendation.rawValue else { return nil }

        // Get the event kind from d-tag
        guard let dTag = tagValue("d"), let eventKind = Kind(dTag) else { return nil }

        // Parse handler references from a tags
        let handlers = tags(withName: "a").compactMap { tag -> NIP89HandlerReference? in
            guard tag.count >= 2 else { return nil }

            let address = tag[1]
            let relay = tag.count >= 3 ? tag[2] : nil
            let platform = tag.count >= 4 ? tag[3] : nil

            return NIP89HandlerReference(address: address, relay: relay, platform: platform)
        }

        return NIP89Recommendation(eventKind: eventKind, handlers: handlers)
    }
}

// MARK: - NDKEventBuilder Extensions for NIP-89

public extension NDKEventBuilder {
    /// Create a NIP-89 handler information event (kind 31990)
    ///
    /// - Parameters:
    ///   - identifier: Unique identifier for this handler
    ///   - supportedKinds: List of event kinds this handler supports
    ///   - handlerURLs: Dictionary mapping platform names to handler URLs
    ///   - metadata: Optional metadata about the handler
    ///
    /// - Returns: Self for chaining
    @discardableResult
    func nip89HandlerInfo(
        identifier: String,
        supportedKinds: [Kind],
        handlerURLs: [String: String],
        metadata: NIP89HandlerMetadata? = nil
    ) -> NDKEventBuilder {
        return kind(NIP89Kind.handlerInfo.rawValue)
            .dTag(identifier)
            .tags(supportedKinds.map { ["k", String($0)] })
            .tags(handlerURLs.map { platform, url in
                if platform == "web" {
                    return [platform, url, "nevent"]
                } else {
                    return [platform, url]
                }
            })
            .content(metadata?.toJSON() ?? "")
    }

    /// Create a NIP-89 recommendation event (kind 31989)
    ///
    /// - Parameters:
    ///   - eventKind: The event kind being recommended
    ///   - handlers: List of handler references
    ///
    /// - Returns: Self for chaining
    @discardableResult
    func nip89Recommendation(
        eventKind: Kind,
        handlers: [NIP89HandlerReference]
    ) -> NDKEventBuilder {
        return kind(NIP89Kind.recommendation.rawValue)
            .dTag(String(eventKind))
            .tags(handlers.map { handler in
                var tag = ["a", handler.address]
                if let relay = handler.relay {
                    tag.append(relay)
                }
                if let platform = handler.platform {
                    if tag.count == 2 {
                        tag.append("") // Empty relay
                    }
                    tag.append(platform)
                }
                return tag
            })
    }
}

// MARK: - Helper Extensions

extension NIP89HandlerMetadata {
    /// Convert to JSON string
    func toJSON() -> String {
        do {
            return try JSONCoding.encodeToString(self)
        } catch {
            NDKLogger.log(.warning, category: .event, "Failed to encode NIP-89 handler metadata to JSON: \(error)")
            return ""
        }
    }
}
