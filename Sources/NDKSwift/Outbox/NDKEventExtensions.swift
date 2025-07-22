/// Extensions to NDKEvent for outbox model support
public extension NDKEvent {

    /// Extract p tags (mentioned pubkeys)
    var pTags: [String] {
        return tags.compactMap { tag in
            guard tag.count >= 2, tag[0] == NostrTagConstants.TagName.pubkey else { return nil }
            return tag[1]
        }
    }

    /// Extract e tags with optional recommended relay
    var eTags: [(eventId: String, recommendedRelay: String?)] {
        return tags.extractTags(named: NostrTagConstants.TagName.event).compactMap { tag in
            let eventId = tag[1]
            let recommendedRelay = tag[safe: 2]
            return (eventId, recommendedRelay)
        }
    }
}
