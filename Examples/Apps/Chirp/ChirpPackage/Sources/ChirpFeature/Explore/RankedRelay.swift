import Foundation
import NDKSwiftCore

/// Represents a relay ranked by how often it appears in users' relay feeds (kind 10012)
public struct RankedRelay: Identifiable, Sendable {
    public let id: String
    public let url: String
    public let appearanceCount: Int
    public let normalizedScore: Double // 0.0 to 1.0
    public var nip11Info: NDKRelayInformation?

    /// Whether NIP-11 info is available for this relay
    public var hasNIP11Info: Bool {
        nip11Info != nil
    }

    /// Display name - either from NIP-11 or extracted from URL
    public var displayName: String {
        nip11Info?.name ?? extractNameFromURL()
    }

    /// Description from NIP-11 if available
    public var description: String? {
        nip11Info?.description
    }

    /// Icon URL from NIP-11 if available
    public var iconURL: String? {
        nip11Info?.icon
    }

    private func extractNameFromURL() -> String {
        guard let urlComponents = URLComponents(string: url),
              let host = urlComponents.host else {
            return url
        }
        return host
    }

    public init(url: String, appearanceCount: Int, totalUsers: Int) {
        self.id = url
        self.url = url
        self.appearanceCount = appearanceCount
        self.normalizedScore = totalUsers > 0 ? Double(appearanceCount) / Double(totalUsers) : 0.0
    }
}

/// Aggregates relay URLs from kind 10012 events and ranks them
actor RelayFeedAggregator {
    private var relayAppearances: [String: Int] = [:]
    private var totalUsers: Int = 0

    /// Add relay URLs from a kind 10012 event
    func addRelaysFromEvent(_ event: NDKEvent) {
        guard event.kind == 10012 else { return }

        // Extract relay URLs from "relay" tags
        let relayTags = event.tags.filter { $0.first == "relay" }
        var seenRelays: Set<String> = []

        for tag in relayTags {
            guard tag.count > 1 else { continue }
            let relayURL = tag[1]
            guard !relayURL.isEmpty else { continue }

            // Normalize the URL
            let normalizedURL = URLNormalizer.tryNormalizeRelayUrl(relayURL) ?? relayURL

            // Only count each relay once per user
            if !seenRelays.contains(normalizedURL) {
                seenRelays.insert(normalizedURL)
                relayAppearances[normalizedURL, default: 0] += 1
            }
        }

        if !seenRelays.isEmpty {
            totalUsers += 1
        }
    }

    /// Get ranked relays sorted by appearance count
    func getRankedRelays() -> [RankedRelay] {
        relayAppearances.map { url, count in
            RankedRelay(url: url, appearanceCount: count, totalUsers: totalUsers)
        }
        .sorted { lhs, rhs in
            // Primary sort: by appearance count (descending)
            if lhs.appearanceCount != rhs.appearanceCount {
                return lhs.appearanceCount > rhs.appearanceCount
            }
            // Secondary sort: alphabetically by URL
            return lhs.url < rhs.url
        }
    }

    func reset() {
        relayAppearances.removeAll()
        totalUsers = 0
    }
}
