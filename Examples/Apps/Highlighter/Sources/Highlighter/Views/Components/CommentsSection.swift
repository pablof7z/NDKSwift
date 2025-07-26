import SwiftUI
import NDKSwift

struct CommentsSection: View {
    let highlightId: String
    @EnvironmentObject var appState: AppState
    @State private var comments: [CommentEvent] = []
    @State private var isLoading = true
    @State private var newCommentText = ""
    @State private var isPostingComment = false
    @State private var commentAuthors: [String: NDKUserProfile] = [:]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section header
            HStack {
                Text("Comments")
                    .font(DesignSystem.Typography.headline)
                
                Spacer()
                
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            .padding(.horizontal)
            
            // Comments list
            if comments.isEmpty && !isLoading {
                EmptyCommentsView()
                    .padding(.horizontal)
            } else {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(comments) { comment in
                        CommentView(
                            comment: comment,
                            author: commentAuthors[comment.author]
                        )
                    }
                }
                .padding(.horizontal)
            }
            
            // New comment composer
            HStack(spacing: 12) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(DesignSystem.Colors.primary.opacity(0.5))
                
                HStack {
                    TextField("Add a comment...", text: $newCommentText)
                        .font(DesignSystem.Typography.body)
                        .disabled(isPostingComment)
                    
                    if !newCommentText.isEmpty {
                        Button(action: postComment) {
                            if isPostingComment {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(DesignSystem.Colors.primary)
                            }
                        }
                        .disabled(isPostingComment || newCommentText.isEmpty)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(DesignSystem.Colors.surface)
                .cornerRadius(20)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .task {
            await loadComments()
        }
    }
    
    private func loadComments() async {
        guard let ndk = appState.ndk else { return }
        
        let filter = NDKFilter(
            kinds: [1],
            limit: 50,
            tags: ["e": [highlightId]]
        )
        
        let dataSource = await ndk.outbox.observe(
            filter: filter,
            maxAge: 300,
            cachePolicy: .cacheWithNetwork
        )
        
        var hasReceivedFirstComment = false
        
        for await event in dataSource.events {
            // Check if this is a reply to the highlight
            let eTags = event.tags.filter { $0.tag == "e" }
            let isReplyToHighlight = eTags.contains { tag in
                tag.value == highlightId
            }
            
            if isReplyToHighlight,
               let comment = try? CommentEvent(from: event) {
                await MainActor.run {
                    if !comments.contains(where: { $0.id == comment.id }) {
                        comments.append(comment)
                        comments.sort { $0.createdAt > $1.createdAt }
                        
                        if !hasReceivedFirstComment {
                            hasReceivedFirstComment = true
                            isLoading = false
                        }
                    }
                }
                
                // Load author profile
                Task {
                    await loadAuthorProfile(for: comment.author)
                }
            }
        }
        
        // Set loading to false after a timeout if no comments found
        if !hasReceivedFirstComment {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                isLoading = false
            }
        }
    }
    
    private func loadAuthorProfile(for pubkey: String) async {
        guard let ndk = appState.ndk else { return }
        
        if commentAuthors[pubkey] != nil { return }
        
        for await profile in await ndk.profileManager.observe(for: pubkey, maxAge: TimeConstants.hour) {
            await MainActor.run {
                self.commentAuthors[pubkey] = profile
            }
            break
        }
    }
    
    private func postComment() {
        guard let ndk = appState.ndk,
              let signer = appState.signer,
              !newCommentText.isEmpty else { return }
        
        isPostingComment = true
        
        Task {
            do {
                // Create comment event using NDKEventBuilder
                let commentEvent = try await NDKEventBuilder(ndk: ndk)
                    .kind(1)
                    .content(newCommentText)
                    .tags([["e", highlightId]])
                    .build(signer: signer)
                
                // Publish
                _ = try await ndk.publish(commentEvent)
                
                await MainActor.run {
                    newCommentText = ""
                    isPostingComment = false
                    HapticManager.shared.impact(.light)
                }
            } catch {
                print("Failed to post comment: \(error)")
                await MainActor.run {
                    isPostingComment = false
                }
            }
        }
    }
}

struct EmptyCommentsView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.3))
            
            Text("No comments yet")
                .font(DesignSystem.Typography.body)
                .foregroundColor(DesignSystem.Colors.textSecondary)
            
            Text("Be the first to share your thoughts")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// Comment event model
struct CommentEvent: Identifiable {
    let id: String
    let event: NDKEvent
    let content: String
    let author: String
    let createdAt: Date
    
    init(from event: NDKEvent) throws {
        self.id = event.id
        self.event = event
        self.content = event.content
        self.author = event.pubkey
        self.createdAt = Date(timeIntervalSince1970: TimeInterval(event.createdAt))
    }
}