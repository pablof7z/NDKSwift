import Foundation
import NDKSwift

struct AudioEvent: Identifiable {
    let id: String
    let event: NDKEvent
    let author: NDKUser
    let audioURL: String
    let createdAt: Date
    let isReply: Bool
    let replyTo: String?
    let webOfTrustScore: Double
    
    // Reaction tracking (populated separately)
    var likeCount: Int = 0
    var zapCount: Int = 0
    var replyCount: Int = 0
    
    var sortScore: Double {
        // Combine recency and web of trust
        let recencyScore = 1.0 - (Date().timeIntervalSince(createdAt) / (7 * 24 * 60 * 60)) // Decay over 7 days
        return (webOfTrustScore * 0.7) + (max(0, recencyScore) * 0.3)
    }
    
    static func from(event: NDKEvent, webOfTrustScore: Double) -> AudioEvent? {
        guard let audioURL = extractAudioURL(from: event.content) else { return nil }
        
        let isReply = event.kind == 1244
        let replyTo = isReply ? extractReplyTo(from: event) : nil
        
        return AudioEvent(
            id: event.id,
            event: event,
            author: NDKUser(pubkey: event.pubkey),
            audioURL: audioURL,
            createdAt: Date(timeIntervalSince1970: TimeInterval(event.createdAt)),
            isReply: isReply,
            replyTo: replyTo,
            webOfTrustScore: webOfTrustScore
        )
    }
    
    private static func extractAudioURL(from content: String) -> String? {
        // Content should be a direct URL
        guard let url = URL(string: content),
              url.scheme == "https" || url.scheme == "http" else {
            return nil
        }
        return content
    }
    
    private static func extractReplyTo(from event: NDKEvent) -> String? {
        // Look for 'e' tag that marks the reply target
        for tag in event.tags {
            if tag.count >= 2 && tag[0] == "e" {
                return tag[1]
            }
        }
        return nil
    }
}