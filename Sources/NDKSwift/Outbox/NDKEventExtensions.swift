import CryptoKit
import Foundation

/// Extensions to NDKEvent for outbox model support
public extension NDKEvent {
    /// Generate Proof of Work for this event
    /// Note: This is currently a placeholder implementation. 
    /// Proper POW would require modifying event tags and regenerating the ID,
    /// which requires internal access to the event's mutable state.
    func generatePow(targetDifficulty: Int) async throws {
        // POW implementation would need to:
        // 1. Add/update a nonce tag
        // 2. Regenerate the event ID
        // 3. Check if it meets the difficulty target
        // 4. Repeat until target is met
        
        // Since we cannot modify tags directly from an extension,
        // this would need to be implemented within NDKEvent itself
        // or through a different approach
        
        // For now, just add the nonce tag to indicate POW was requested
        let nonceTag = ["nonce", "0", String(targetDifficulty)]
        await addTag(nonceTag)
    }

    /// Extract p tags (mentioned pubkeys)
    var pTags: [String] {
        get async {
            let allTags = await tags
            return allTags.compactMap { tag in
                guard tag.count >= 2, tag[0] == "p" else { return nil }
                return tag[1]
            }
        }
    }

    /// Extract e tags with optional recommended relay
    var eTags: [(eventId: String, recommendedRelay: String?)] {
        get async {
            let allTags = await tags
            return allTags.compactMap { tag in
                guard tag.count >= 2, tag[0] == "e" else { return nil }
                let eventId = tag[1]
                let recommendedRelay = tag.count > 2 ? tag[2] : nil
                return (eventId, recommendedRelay)
            }
        }
    }
}
