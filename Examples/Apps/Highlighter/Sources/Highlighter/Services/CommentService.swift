import Foundation
import NDKSwift
import Combine

@MainActor
class CommentService: ObservableObject {
    // MARK: - Published Properties
    @Published private(set) var comments: [String: [Comment]] = [:] // Keyed by highlight ID
    @Published private(set) var isLoadingComments: [String: Bool] = [:]
    @Published private(set) var replyingTo: Comment?
    
    // MARK: - Properties
    private var ndk: NDK?
    private var signer: NDKSigner?
    private var cancellables = Set<AnyCancellable>()
    private var activeSubscriptions: [String: AnyCancellable] = [:]
    
    // MARK: - Configuration
    
    func configure(with ndk: NDK, signer: NDKSigner?) {
        self.ndk = ndk
        self.signer = signer
    }
    
    // MARK: - Public Methods
    
    /// Load comments for a highlight
    func loadComments(for highlightId: String) async {
        guard let ndk = ndk else { return }
        
        // Mark as loading
        await MainActor.run {
            isLoadingComments[highlightId] = true
        }
        
        // Create filter for comments on this highlight
        let filter = NDKFilter(
            kinds: [1], // Regular text notes
            tags: ["e": [highlightId]]
        )
        
        // Subscribe to comments
        let dataSource = await ndk.outbox.observe(
            filter: filter,
            maxAge: 300, // 5 minute cache
            cachePolicy: .cacheWithNetwork
        )
        
        // Cancel any existing subscription
        activeSubscriptions[highlightId]?.cancel()
        
        // Process comments as they arrive
        let subscription = dataSource.events
            .sink(
                receiveCompletion: { _ in
                    Task { @MainActor in
                        self.isLoadingComments[highlightId] = false
                    }
                },
                receiveValue: { event in
                    Task {
                        if let comment = await self.processCommentEvent(event, highlightId: highlightId) {
                            await MainActor.run {
                                if self.comments[highlightId] == nil {
                                    self.comments[highlightId] = []
                                }
                                
                                // Add if not already present
                                if !self.comments[highlightId]!.contains(where: { $0.id == comment.id }) {
                                    self.comments[highlightId]!.append(comment)
                                    
                                    // Sort by timestamp
                                    self.comments[highlightId]!.sort { $0.createdAt > $1.createdAt }
                                }
                                
                                // Mark as loaded after first comment
                                self.isLoadingComments[highlightId] = false
                            }
                        }
                    }
                }
            )
        
        activeSubscriptions[highlightId] = subscription
    }
    
    /// Post a comment on a highlight
    func postComment(
        on highlightId: String,
        content: String,
        replyingTo: Comment? = nil
    ) async throws {
        guard let ndk = ndk, let signer = signer else {
            throw CommentError.notConfigured
        }
        
        // Build tags
        var tags: [[String]] = [
            ["e", highlightId, "", "root"] // Reference to the highlight
        ]
        
        // Add reply tag if replying
        if let replyComment = replyingTo {
            tags.append(["e", replyComment.id, "", "reply"])
            tags.append(["p", replyComment.author]) // Mention the author
        }
        
        // Create the comment event
        let event = try await NDKEventBuilder(ndk: ndk)
            .kind(1) // Regular text note
            .content(content)
            .tags(tags)
            .build(signer: signer)
        
        // Publish the comment
        try await ndk.publish(event)
        
        // Create local comment object
        let comment = Comment(
            id: event.id,
            author: event.pubkey,
            content: content,
            createdAt: event.createdAt,
            highlightId: highlightId,
            replyToId: replyingTo?.id,
            likes: 0,
            isLiked: false
        )
        
        // Add to local state immediately for better UX
        await MainActor.run {
            if self.comments[highlightId] == nil {
                self.comments[highlightId] = []
            }
            self.comments[highlightId]!.insert(comment, at: 0)
        }
        
        HapticManager.shared.notification(.success)
    }
    
    /// Like a comment
    func likeComment(_ comment: Comment) async throws {
        guard let ndk = ndk, let signer = signer else {
            throw CommentError.notConfigured
        }
        
        // Create reaction event (NIP-25)
        let event = try await NDKEventBuilder(ndk: ndk)
            .kind(7) // Reaction
            .content("+") // Like emoji
            .tags([
                ["e", comment.id],
                ["p", comment.author]
            ])
            .build(signer: signer)
        
        try await ndk.publish(event)
        
        // Update local state
        await MainActor.run {
            if let highlightComments = self.comments[comment.highlightId],
               let index = highlightComments.firstIndex(where: { $0.id == comment.id }) {
                self.comments[comment.highlightId]![index].likes += 1
                self.comments[comment.highlightId]![index].isLiked = true
            }
        }
        
        HapticManager.shared.impact(.light)
    }
    
    /// Delete a comment (if author)
    func deleteComment(_ comment: Comment) async throws {
        guard let ndk = ndk, let signer = signer else {
            throw CommentError.notConfigured
        }
        
        // Verify the user is the author
        let userPubkey = try await signer.publicKey(format: .hex)
        guard comment.author == userPubkey else {
            throw CommentError.notAuthor
        }
        
        // Create deletion event (NIP-09)
        let event = try await NDKEventBuilder(ndk: ndk)
            .kind(5) // Deletion
            .content("Deleted comment")
            .tags([["e", comment.id]])
            .build(signer: signer)
        
        try await ndk.publish(event)
        
        // Remove from local state
        await MainActor.run {
            if var highlightComments = self.comments[comment.highlightId] {
                highlightComments.removeAll { $0.id == comment.id }
                self.comments[comment.highlightId] = highlightComments
            }
        }
        
        HapticManager.shared.notification(.success)
    }
    
    /// Get comment count for a highlight
    func getCommentCount(for highlightId: String) -> Int {
        comments[highlightId]?.count ?? 0
    }
    
    /// Set reply target
    func setReplyTarget(_ comment: Comment?) {
        replyingTo = comment
        if comment != nil {
            HapticManager.shared.impact(.light)
        }
    }
    
    /// Clear all subscriptions
    func clearSubscriptions() {
        activeSubscriptions.values.forEach { $0.cancel() }
        activeSubscriptions.removeAll()
    }
    
    // MARK: - Private Methods
    
    private func processCommentEvent(_ event: NDKEvent, highlightId: String) async -> Comment? {
        // Filter out deletions and other non-comment events
        guard event.kind == 1 else { return nil }
        
        // Extract reply-to if exists
        let replyTag = event.tags.first { $0.count >= 4 && $0[0] == "e" && $0[3] == "reply" }
        let replyToId = replyTag?[1]
        
        // Count existing reactions for this comment
        let reactionCount = await countReactions(for: event.id)
        let isLiked = await checkIfLiked(event.id)
        
        return Comment(
            id: event.id,
            author: event.pubkey,
            content: event.content,
            createdAt: event.createdAt,
            highlightId: highlightId,
            replyToId: replyToId,
            likes: reactionCount,
            isLiked: isLiked
        )
    }
    
    private func countReactions(for eventId: String) async -> Int {
        guard let ndk = ndk else { return 0 }
        
        let filter = NDKFilter(
            kinds: [7], // Reactions
            tags: ["e": [eventId]]
        )
        
        do {
            let events = try await ndk.fetchEvents(filter, timeout: 2.0)
            return events.filter { $0.content == "+" || $0.content == "❤️" }.count
        } catch {
            return 0
        }
    }
    
    private func checkIfLiked(_ eventId: String) async -> Bool {
        guard let ndk = ndk, let signer = signer else { return false }
        
        do {
            let userPubkey = try await signer.publicKey(format: .hex)
            
            let filter = NDKFilter(
                authors: [userPubkey],
                kinds: [7], // Reactions
                tags: ["e": [eventId]]
            )
            
            let events = try await ndk.fetchEvents(filter, timeout: 1.0)
            return events.contains { $0.content == "+" || $0.content == "❤️" }
        } catch {
            return false
        }
    }
}

// MARK: - Supporting Types

struct Comment: Identifiable, Equatable {
    let id: String
    let author: String
    let content: String
    let createdAt: Timestamp
    let highlightId: String
    let replyToId: String?
    var likes: Int
    var isLiked: Bool
    
    var isReply: Bool {
        replyToId != nil
    }
    
    var formattedTime: String {
        RelativeTimeFormatter.relativeTime(from: createdAt)
    }
}

enum CommentError: LocalizedError {
    case notConfigured
    case notAuthor
    case publishFailed
    
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Comment service not configured"
        case .notAuthor:
            return "You can only delete your own comments"
        case .publishFailed:
            return "Failed to publish comment"
        }
    }
}