import Foundation
import NDKSwiftCore

/// Nutzap preferences (kind: 10019)
public struct NDKNutzapPreferences {
    public let event: NDKEvent

    public init(event: NDKEvent) {
        self.event = event
    }

    /// Mint configuration
    public struct MintConfig {
        public let url: URL
        public let relays: [String]

        public init(url: URL, relays: [String] = []) {
            self.url = url
            self.relays = relays
        }
    }

    /// Check if any mints are configured (synchronous)
    public var hasMints: Bool {
        event.tags.contains { $0.first == NostrConstants.TagName.mint }
    }

    /// Get configured mints
    public var mints: [MintConfig] {
        get async {
            return event.tags
                .filter { $0.first == NostrConstants.TagName.mint }
                .compactMap { tag in
                    guard let urlString = tag[safe: 1],
                          let url = URL(string: urlString) else {
                        return nil
                    }

                    let relays = Array(tag.dropFirst(2))
                    return MintConfig(url: url, relays: relays)
                }
        }
    }

    /// Get P2PK pubkey for receiving nutzaps
    public var p2pkPubkey: String {
        get async {
            // Look for p2pk tag (as per NIP-61)
            if let pubkey = event.tags.firstTagValue(named: NostrConstants.TagName.p2pk) {
                return pubkey
            }
            // Fall back to event author's pubkey
            return event.pubkey
        }
    }
}
