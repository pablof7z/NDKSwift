import Foundation
import NDKSwiftCore

/// Represents a follow pack (kind 39089 or 39092) - a curated list of accounts
public struct FollowPack: Identifiable, Sendable {
    public let id: String
    public let event: NDKEvent
    public let name: String
    public let description: String?
    public let imageURL: URL?
    public let pubkeys: [String]
    public let creatorPubkey: String

    public var memberCount: Int { pubkeys.count }

    public init?(event: NDKEvent) {
        // Only accept follow pack kinds
        guard event.kind == 39089 || event.kind == 39092 else { return nil }

        self.id = event.id
        self.event = event
        self.creatorPubkey = event.pubkey

        // Extract name from "title" tag, fall back to "d" tag
        let titleTag = event.tags.first { $0.first == "title" }
        let dTag = event.tags.first { $0.first == "d" }
        self.name = titleTag?.dropFirst().first ?? dTag?.dropFirst().first ?? "Unnamed Pack"

        // Extract description
        let descTag = event.tags.first { $0.first == "description" }
        self.description = descTag?.dropFirst().first ?? (event.content.isEmpty ? nil : event.content)

        // Extract image URL
        if let imageTag = event.tags.first(where: { $0.first == "image" }),
           let urlString = imageTag.dropFirst().first,
           let url = URL(string: urlString) {
            self.imageURL = url
        } else {
            self.imageURL = nil
        }

        // Extract pubkeys from "p" tags
        self.pubkeys = event.tags
            .filter { $0.first == "p" }
            .compactMap { $0.dropFirst().first }
    }
}
