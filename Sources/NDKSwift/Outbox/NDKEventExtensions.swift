import CryptoKit
import Foundation

/// Extensions to NDKEvent for outbox model support
public extension NDKEvent {
    /// Generate Proof of Work for this event
    func generatePow(targetDifficulty: Int) async throws {
        // Calculate the target based on difficulty
        let targetHex = String(repeating: "0", count: targetDifficulty / 4)
        let targetBits = targetDifficulty % 4
        let targetChar: Character

        switch targetBits {
        case 0:
            targetChar = "f"
        case 1:
            targetChar = "7"
        case 2:
            targetChar = "3"
        case 3:
            targetChar = "1"
        default:
            targetChar = "0"
        }

        let fullTarget = targetHex + String(targetChar)

        // Add nonce tag if not present
        var nonceTagIndex: Int?
        for (index, tag) in tags.enumerated() {
            if tag.first == "nonce" {
                nonceTagIndex = index
                break
            }
        }

        if nonceTagIndex == nil {
            tags.append(["nonce", "0", String(targetDifficulty)])
            nonceTagIndex = tags.count - 1
        }

        // Try different nonces until we find one that works
        var nonce: UInt64 = 0
        let maxAttempts: UInt64 = 10_000_000 // Prevent infinite loop

        while nonce < maxAttempts {
            // Update nonce in tags
            tags[nonceTagIndex!] = ["nonce", String(nonce), String(targetDifficulty)]

            // Regenerate event ID
            let newId = try generateID()

            // Check if it meets difficulty
            if newId.hasPrefix(fullTarget) ||
                (targetBits > 0 && newId.hasPrefix(targetHex) &&
                    newId[newId.index(newId.startIndex, offsetBy: targetHex.count)] <= targetChar)
            {
                // Success! Update the event ID
                self.id = newId
                self.sig = nil // Clear signature as event changed
                return
            }

            nonce += 1

            // Yield periodically to avoid blocking
            if nonce % 1000 == 0 {
                await Task.yield()
            }
        }

        throw NDKError.powGenerationFailed
    }

    /// Extract p tags (mentioned pubkeys)
    var pTags: [String] {
        tags.compactMap { tag in
            guard tag.count >= 2, tag[0] == "p" else { return nil }
            return tag[1]
        }
    }

    /// Extract e tags with optional recommended relay
    var eTags: [(eventId: String, recommendedRelay: String?)] {
        tags.compactMap { tag in
            guard tag.count >= 2, tag[0] == "e" else { return nil }
            let eventId = tag[1]
            let recommendedRelay = tag.count > 2 ? tag[2] : nil
            return (eventId, recommendedRelay)
        }
    }
}
