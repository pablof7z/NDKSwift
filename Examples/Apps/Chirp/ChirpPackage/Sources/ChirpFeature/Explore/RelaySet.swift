import Foundation
import NDKSwiftCore

/// Represents a relay set (kind 30002) - a curated list of relays
struct RelaySet: Identifiable, Sendable {
    let id: String
    let event: NDKEvent
    let name: String
    let description: String?
    let relays: [RelayEntry]
    let creatorPubkey: String

    struct RelayEntry: Sendable {
        let url: String
        let marker: String? // "read", "write", or nil for both
    }

    var relayCount: Int { relays.count }

    init?(event: NDKEvent) {
        guard event.kind == 30002 else { return nil }

        self.id = event.id
        self.event = event
        self.creatorPubkey = event.pubkey

        // Extract name from "d" tag
        let dTag = event.tags.first { $0.first == "d" }
        self.name = dTag?.dropFirst().first ?? "Relay Set"

        // Extract description from content or "description" tag
        let descTag = event.tags.first { $0.first == "description" }
        self.description = descTag?.dropFirst().first ?? (event.content.isEmpty ? nil : event.content)

        // Extract relays from "relay" or "r" tags
        self.relays = event.tags
            .filter { $0.first == "relay" || $0.first == "r" }
            .compactMap { tag -> RelayEntry? in
                guard let url = tag.dropFirst().first else { return nil }
                let marker = tag.dropFirst(2).first
                return RelayEntry(url: url, marker: marker)
            }
    }

    /// Returns icon based on relay set type/name
    var icon: String {
        let lowercaseName = name.lowercased()
        if lowercaseName.contains("inbox") || lowercaseName.contains("read") {
            return "📥"
        } else if lowercaseName.contains("outbox") || lowercaseName.contains("write") {
            return "📤"
        } else if lowercaseName.contains("dm") || lowercaseName.contains("message") {
            return "🔐"
        } else if lowercaseName.contains("search") {
            return "🔍"
        } else {
            return "⚡"
        }
    }

    /// Returns gradient type based on relay set type
    var gradientType: GradientType {
        let lowercaseName = name.lowercased()
        if lowercaseName.contains("inbox") || lowercaseName.contains("read") {
            return .inbox
        } else if lowercaseName.contains("outbox") || lowercaseName.contains("write") {
            return .outbox
        } else if lowercaseName.contains("dm") || lowercaseName.contains("message") {
            return .dm
        } else {
            return .general
        }
    }

    enum GradientType {
        case general
        case inbox
        case outbox
        case dm
    }
}
