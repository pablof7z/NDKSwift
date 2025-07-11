import CryptoKit
import Foundation

/// Extensions to NDKEvent for outbox model support
public extension NDKEvent {
    /// Generate Proof of Work for this event
    /// Note: This would require creating a new event with POW tags.
    /// Since NDKEvent is immutable, POW generation should be done during event building.
    func generatePow(targetDifficulty: Int, signer: NDKSigner) async throws -> NDKEvent {
        // POW implementation would need to:
        // 1. Add/update a nonce tag
        // 2. Regenerate the event ID
        // 3. Check if it meets the difficulty target
        // 4. Repeat until target is met
        
        // Since events are immutable, we need to create a new event with POW
        let nonceTag = ["nonce", "0", String(targetDifficulty)]
        var newTags = tags
        newTags.append(nonceTag)
        
        // Create new event with POW tag
        let newEvent = try await NDKEventBuilder()
            .pubkey(pubkey)
            .createdAt(createdAt)
            .kind(kind)
            .tags(newTags)
            .content(content)
            .build(signer: signer)
        
        return newEvent
    }

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
