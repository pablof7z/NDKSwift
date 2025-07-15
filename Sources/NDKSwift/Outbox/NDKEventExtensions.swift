import CryptoKit
import Foundation

/// Extensions to NDKEvent for outbox model support
public extension NDKEvent {

    /// Extract p tags (mentioned pubkeys)
    var pTags: [String] {
        return tags.compactMap { tag in
            guard tag.count >= 2, tag[0] == "p" else { return nil }
            return tag[1]
        }
    }

    /// Extract e tags with optional recommended relay
    var eTags: [(eventId: String, recommendedRelay: String?)] {
        return tags.compactMap { tag in
            guard tag.count >= 2, tag[0] == "e" else { return nil }
            let eventId = tag[1]
            let recommendedRelay = tag.count > 2 ? tag[2] : nil
            return (eventId, recommendedRelay)
        }
    }
}
