import Foundation
import NDKSwift
import Observation

/// Manages reply tracking for all events in a performant way
@MainActor
@Observable
class ReplyTracker {
    struct ReplyInfo {
        let totalCount: Int
        let followingRepliers: [NDKUserProfile]
        let lastUpdated: Date
    }
    
    private var replyCache: [String: ReplyInfo] = [:]
    private var activeSubscriptions: [String: Task<Void, Never>] = [:]
    private weak var ndk: NDK?
    private var followingSet: Set<String> = []
    
    init(ndk: NDK, following: Set<String>) {
        self.ndk = ndk
        self.followingSet = following
    }
    
    func updateFollowing(_ following: Set<String>) {
        self.followingSet = following
    }
    
    func getReplyInfo(for eventId: String) -> ReplyInfo? {
        return replyCache[eventId]
    }
    
    func startTrackingReplies(for eventId: String) {
        // Don't start duplicate subscriptions
        guard activeSubscriptions[eventId] == nil,
              let ndk = ndk else { return }
        
        let task = Task { [weak self] in
            guard let self = self else { return }
            
            // Create filter for replies
            let replyFilter = NDKFilter(
                kinds: [EventKind.textNote],
                tags: ["e": Set([eventId])]
            )
            
            let dataSource = ndk.observe(filter: replyFilter, maxAge: 300) // 5 min cache
            
            var replyCount = 0
            var seenRepliers = Set<String>()
            var followingReplierProfiles: [NDKUserProfile] = []
            
            for await reply in dataSource.events {
                // Check if this is a direct reply (last "e" tag)
                let isDirectReply = reply.tags
                    .filter { $0.count >= 2 && $0[0] == "e" }
                    .last?.contains(eventId) ?? false
                
                if isDirectReply {
                    replyCount += 1
                    
                    // Check if replier is someone we follow
                    if self.followingSet.contains(reply.pubkey),
                       !seenRepliers.contains(reply.pubkey) {
                        seenRepliers.insert(reply.pubkey)
                        
                        // Fetch profile (with caching via profileManager)
                        let profileStream = await ndk.profileManager.observe(for: reply.pubkey, maxAge: TimeConstants.hour)
                        for await profile in profileStream {
                            if let profile = profile {
                                followingReplierProfiles.append(profile)
                            }
                            break // Only need the first profile
                        }
                    }
                    
                    // Update cache
                    let info = ReplyInfo(
                        totalCount: replyCount,
                        followingRepliers: followingReplierProfiles.sorted { 
                            ($0.name ?? "") < ($1.name ?? "") 
                        },
                        lastUpdated: Date()
                    )
                    
                    await MainActor.run {
                        self.replyCache[eventId] = info
                    }
                }
            }
        }
        
        activeSubscriptions[eventId] = task
    }
    
    func stopTrackingReplies(for eventId: String) {
        activeSubscriptions[eventId]?.cancel()
        activeSubscriptions[eventId] = nil
    }
    
    func stopAllTracking() {
        for task in activeSubscriptions.values {
            task.cancel()
        }
        activeSubscriptions.removeAll()
    }
}