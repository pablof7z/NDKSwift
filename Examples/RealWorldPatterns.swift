// Real-world usage patterns for NDKSwift's declarative API
// This demonstrates common app scenarios using the new architecture

import Foundation

// Mock types (same as StandaloneDeclarativeDemo)
struct NDKEvent {
    let id: String
    let pubkey: String
    let content: String
    let kind: Int
    let createdAt: Int64
    let tags: [[String]]
}

struct NDKFilter {
    var kinds: [Int]?
    var authors: [String]?
    var ids: [String]?
    var limit: Int?
    var since: Int64?
    var until: Int64?
    var tags: [[String]] = []
    
    mutating func addTagFilter(_ tag: String, value: String) {
        tags.append([tag, value])
    }
}

struct NDKUserProfile: Codable {
    let name: String?
    let displayName: String?
    let about: String?
    let picture: String?
    let nip05: String?
}

@MainActor
class NDKDataSource<T>: ObservableObject {
    @Published private(set) var data: [T] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var error: Error?
    
    let filter: NDKFilter
    private let transform: ((NDKEvent) -> T?)?
    
    init(filter: NDKFilter, transform: ((NDKEvent) -> T?)? = nil) {
        self.filter = filter
        self.transform = transform
        simulateDataLoading()
    }
    
    private func simulateDataLoading() {
        Task {
            isLoading = true
            try? await Task.sleep(nanoseconds: 500_000_000)
            
            // Simulate data based on filter
            if let kinds = filter.kinds {
                if kinds.contains(0) {
                    loadProfiles()
                } else if kinds.contains(1) {
                    loadNotes()
                } else if kinds.contains(7) {
                    loadReactions()
                }
            }
            
            isLoading = false
        }
    }
    
    private func loadProfiles() {
        let mockProfile = NDKEvent(
            id: "profile123",
            pubkey: filter.authors?.first ?? "mock_pubkey",
            content: """
            {"name":"Alice","displayName":"Alice in Nostrland","about":"Building the future of social media","picture":"https://example.com/alice.jpg"}
            """,
            kind: 0,
            createdAt: Int64(Date().timeIntervalSince1970),
            tags: []
        )
        
        if let transform = transform {
            if let transformed = transform(mockProfile) {
                data = [transformed]
            }
        }
    }
    
    private func loadNotes() {
        let notes = (0..<5).map { i in
            NDKEvent(
                id: "note\(i)",
                pubkey: filter.authors?.first ?? "author\(i)",
                content: "Interesting thought #\(i + 1): The future is decentralized! 🚀",
                kind: 1,
                createdAt: Int64(Date().timeIntervalSince1970) - Int64(i * 3600),
                tags: [["t", "nostr"], ["t", "decentralized"]]
            )
        }
        
        if T.self == NDKEvent.self {
            data = notes as! [T]
        }
    }
    
    private func loadReactions() {
        let reactions = ["❤️", "🔥", "👍", "🚀", "⚡"]
        let mockReactions = reactions.enumerated().map { i, emoji in
            NDKEvent(
                id: "reaction\(i)",
                pubkey: "reactor\(i)",
                content: emoji,
                kind: 7,
                createdAt: Int64(Date().timeIntervalSince1970) - Int64(i * 60),
                tags: [["e", filter.tags.first { $0[0] == "e" }?[1] ?? "target_event"]]
            )
        }
        
        if let transform = transform {
            data = mockReactions.compactMap(transform)
        } else if T.self == NDKEvent.self {
            data = mockReactions as! [T]
        }
    }
}

// Real-world usage patterns
struct RealWorldPatterns {
    
    // Pattern 1: User Profile View
    @MainActor
    static func userProfilePattern() async {
        print("👤 Pattern 1: User Profile View")
        print("================================\n")
        
        let userPubkey = "82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2"
        
        // Profile data
        let profileData = NDKDataSource<NDKUserProfile>(
            filter: NDKFilter(
                kinds: [0],
                authors: [userPubkey],
                limit: 1
            )
        ) { event in
            guard let data = event.content.data(using: .utf8),
                  let profile = try? JSONDecoder().decode(NDKUserProfile.self, from: data) else {
                return nil
            }
            return profile
        }
        
        // User's notes
        let userNotes = NDKDataSource<NDKEvent>(
            filter: NDKFilter(
                kinds: [1],
                authors: [userPubkey],
                limit: 20
            )
        )
        
        // User's followers (who has them in their contact list)
        let followers = NDKDataSource<String>(
            filter: NDKFilter(
                kinds: [3],
                limit: 100,
                tags: [["p", userPubkey]]
            )
        ) { event in
            event.pubkey // Transform to just the follower's pubkey
        }
        
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        print("Profile loaded: \(profileData.data.first?.displayName ?? "Unknown")")
        print("Recent notes: \(userNotes.data.count)")
        print("Followers: \(followers.data.count)")
        print()
    }
    
    // Pattern 2: Social Feed
    @MainActor
    static func socialFeedPattern() async {
        print("📱 Pattern 2: Social Feed")
        print("=========================\n")
        
        // Assume we have a list of followed pubkeys
        let followedPubkeys = [
            "82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2",
            "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"
        ]
        
        // Main feed - notes from followed users
        let mainFeed = NDKDataSource<NDKEvent>(
            filter: NDKFilter(
                kinds: [1, 6], // Notes and reposts
                authors: followedPubkeys,
                limit: 50,
                since: Int64(Date().timeIntervalSince1970 - 3600) // Last hour
            )
        )
        
        // Global trending notes (based on reactions)
        let trendingNotes = NDKDataSource<NDKEvent>(
            filter: NDKFilter(
                kinds: [1],
                limit: 10
            )
        )
        
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        print("Feed items: \(mainFeed.data.count)")
        print("Trending: \(trendingNotes.data.count)")
        print("✅ Feed automatically updates as new events arrive!")
        print()
    }
    
    // Pattern 3: Thread View with Replies
    @MainActor
    static func threadViewPattern() async {
        print("💬 Pattern 3: Thread View")
        print("=========================\n")
        
        let rootNoteId = "abc123"
        
        // The root note
        let rootNote = NDKDataSource<NDKEvent>(
            filter: NDKFilter(
                kinds: [1],
                ids: [rootNoteId],
                limit: 1
            )
        )
        
        // Direct replies
        let replies = NDKDataSource<NDKEvent>(
            filter: NDKFilter(
                kinds: [1],
                limit: 100,
                tags: [["e", rootNoteId, "", "reply"]]
            )
        )
        
        // Reactions to the root note
        let reactions = NDKDataSource<(String, Int)>(
            filter: NDKFilter(
                kinds: [7],
                limit: 500,
                tags: [["e", rootNoteId]]
            )
        ) { event in
            (event.content.isEmpty ? "👍" : event.content, 1)
        }
        
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        print("Root note loaded: \(rootNote.data.count)")
        print("Replies: \(replies.data.count)")
        print("Reactions: \(reactions.data.count)")
        print()
    }
    
    // Pattern 4: Real-time Chat
    @MainActor
    static func chatPattern() async {
        print("💬 Pattern 4: Real-time Chat")
        print("============================\n")
        
        let chatRoomId = "chat123"
        
        // Chat messages (NIP-28)
        let chatMessages = NDKDataSource<NDKEvent>(
            filter: NDKFilter(
                kinds: [42],
                limit: 100,
                since: Int64(Date().timeIntervalSince1970 - 3600),
                tags: [["e", chatRoomId]]
            )
        )
        
        // Online participants
        let participants = NDKDataSource<String>(
            filter: NDKFilter(
                kinds: [10000], // Hypothetical "presence" event
                since: Int64(Date().timeIntervalSince1970 - 300), // Last 5 min
                tags: [["e", chatRoomId]]
            )
        ) { event in
            event.pubkey
        }
        
        print("💡 Chat automatically updates with new messages")
        print("💡 No manual subscription management needed!")
        print()
    }
    
    // Pattern 5: Marketplace (NIP-15)
    @MainActor
    static func marketplacePattern() async {
        print("🛍️ Pattern 5: Marketplace")
        print("=========================\n")
        
        // Product listings
        var productFilter = NDKFilter(
            kinds: [30018], // Parameterized replaceable event for products
            limit: 20
        )
        productFilter.addTagFilter("t", value: "bitcoin")
        productFilter.addTagFilter("t", value: "merchandise")
        
        let products = NDKDataSource<NDKEvent>(filter: productFilter)
        
        // Product reviews/ratings
        let reviews = NDKDataSource<NDKEvent>(
            filter: NDKFilter(
                kinds: [1985], // NIP-32 labeling
                limit: 50,
                tags: [["L", "review"]]
            )
        )
        
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        print("Products found: \(products.data.count)")
        print("Reviews loaded: \(reviews.data.count)")
        print("✅ Updates automatically when new products are listed!")
        print()
    }
    
    static func main() async {
        print("🚀 Real-World NDKSwift Declarative Patterns")
        print("==========================================\n")
        
        await userProfilePattern()
        await socialFeedPattern()
        await threadViewPattern()
        await chatPattern()
        await marketplacePattern()
        
        print("\n🎯 Key Benefits Demonstrated:")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("✅ Clean, declarative code - just describe what data you want")
        print("✅ Automatic subscription lifecycle management")
        print("✅ Built-in temporal grouping for efficiency")
        print("✅ Reactive updates - UI stays in sync automatically")
        print("✅ Transform support for data shaping")
        print("✅ Complex filters with tag support")
        print("✅ Outbox model integration (automatic relay routing)")
        print("\n🚫 No more manual subscription management!")
        print("🚫 No more subscription cleanup code!")
        print("🚫 No more relay selection logic!")
        print("\n✨ Just declare your data needs and let NDKSwift handle the rest!")
    }
}

// Run the demo
Task {
    await RealWorldPatterns.main()
    exit(0)
}

RunLoop.main.run()