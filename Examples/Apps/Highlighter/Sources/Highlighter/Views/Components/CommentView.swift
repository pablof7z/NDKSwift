import SwiftUI
import NDKSwift

struct CommentView: View {
    let comment: Comment
    let authorProfile: NDKUserProfile?
    let isReply: Bool
    let onReply: () -> Void
    let onLike: () -> Void
    let onDelete: (() -> Void)?
    let onAuthorTap: () -> Void
    
    @State private var showOptions = false
    @State private var likeScale: CGFloat = 1.0
    
    init(
        comment: Comment,
        authorProfile: NDKUserProfile? = nil,
        onReply: @escaping () -> Void,
        onLike: @escaping () -> Void,
        onDelete: (() -> Void)? = nil,
        onAuthorTap: @escaping () -> Void
    ) {
        self.comment = comment
        self.authorProfile = authorProfile
        self.isReply = comment.isReply
        self.onReply = onReply
        self.onLike = onLike
        self.onDelete = onDelete
        self.onAuthorTap = onAuthorTap
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: .ds.base) {
            // Reply indicator
            if isReply {
                Rectangle()
                    .fill(DesignSystem.Colors.divider)
                    .frame(width: 2)
                    .padding(.leading, 20)
            }
            
            // Author avatar
            Button(action: onAuthorTap) {
                AuthorAvatar(
                    pubkey: comment.author,
                    profile: authorProfile,
                    size: isReply ? 32 : 40
                )
            }
            .buttonStyle(.plain)
            
            VStack(alignment: .leading, spacing: .ds.small) {
                // Header
                HStack(alignment: .center, spacing: .ds.small) {
                    Button(action: onAuthorTap) {
                        Text(displayName)
                            .font(isReply ? .ds.footnoteMedium : .ds.bodyMedium)
                            .foregroundColor(.ds.text)
                    }
                    .buttonStyle(.plain)
                    
                    Text("·")
                        .font(.ds.caption)
                        .foregroundColor(.ds.textTertiary)
                    
                    Text(comment.formattedTime)
                        .font(.ds.caption)
                        .foregroundColor(.ds.textTertiary)
                    
                    Spacer()
                    
                    if let onDelete = onDelete {
                        Menu {
                            Button(role: .destructive, action: onDelete) {
                                Label("Delete", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.ds.textTertiary)
                                .frame(width: 24, height: 24)
                        }
                    }
                }
                
                // Content
                Text(comment.content)
                    .font(isReply ? .ds.callout : .ds.body)
                    .foregroundColor(.ds.text)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                
                // Actions
                HStack(spacing: .ds.large) {
                    // Like button
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            likeScale = 1.2
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                likeScale = 1.0
                            }
                        }
                        onLike()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: comment.isLiked ? "heart.fill" : "heart")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(comment.isLiked ? .red : .ds.textTertiary)
                                .scaleEffect(likeScale)
                            
                            if comment.likes > 0 {
                                Text("\(comment.likes)")
                                    .font(.ds.caption)
                                    .foregroundColor(.ds.textSecondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    
                    // Reply button
                    Button(action: onReply) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrowshape.turn.up.left")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.ds.textTertiary)
                            
                            Text("Reply")
                                .font(.ds.caption)
                                .foregroundColor(.ds.textSecondary)
                        }
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                }
                .padding(.top, .ds.micro)
            }
        }
        .padding(.vertical, .ds.small)
        .padding(.horizontal, .ds.screenPadding)
        .contentShape(Rectangle())
    }
    
    private var displayName: String {
        if let profile = authorProfile {
            return profile.displayName ?? profile.name ?? PubkeyFormatter.formatShort(comment.author)
        }
        return PubkeyFormatter.formatShort(comment.author)
    }
}

// MARK: - Author Avatar

struct AuthorAvatar: View {
    let pubkey: String
    let profile: NDKUserProfile?
    let size: CGFloat
    
    var body: some View {
        Group {
            if let picture = profile?.picture, let url = URL(string: picture) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .empty, .failure:
                        placeholderAvatar
                    @unknown default:
                        placeholderAvatar
                    }
                }
            } else {
                placeholderAvatar
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(DesignSystem.Colors.border, lineWidth: 0.5)
        )
    }
    
    private var placeholderAvatar: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: generateColorForPubkey(pubkey)),
                            Color(hex: generateColorForPubkey(pubkey)).opacity(0.8)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Text(avatarInitial)
                .font(.system(size: size * 0.45, weight: .medium))
                .foregroundColor(.white)
        }
    }
    
    private var avatarInitial: String {
        if let profile = profile {
            let name = profile.displayName ?? profile.name ?? "?"
            return String(name.prefix(1)).uppercased()
        }
        return PubkeyFormatter.formatForAvatar(pubkey)
    }
    
    private func generateColorForPubkey(_ pubkey: String) -> String {
        let colors = ["FF6B6B", "4ECDC4", "45B7D1", "96CEB4", "FECA57", "FF9FF3", "54A0FF"]
        let index = abs(pubkey.hashValue) % colors.count
        return colors[index]
    }
}

// MARK: - Comments Section

struct CommentsSection: View {
    let highlightId: String
    @EnvironmentObject var appState: AppState
    @StateObject private var profileCache = ProfileCacheManager()
    @State private var isExpanded = false
    @State private var showingReplyField = false
    @State private var replyText = ""
    @State private var replyingTo: Comment?
    @FocusState private var isReplyFieldFocused: Bool
    
    var commentService: CommentService {
        appState.commentService
    }
    
    var comments: [Comment] {
        commentService.comments[highlightId] ?? []
    }
    
    var isLoading: Bool {
        commentService.isLoadingComments[highlightId] ?? false
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: .ds.medium) {
            // Header
            Button(action: toggleExpanded) {
                HStack {
                    Label {
                        Text("Comments")
                            .font(.ds.headline)
                        
                        if comments.count > 0 {
                            Text("(\(comments.count))")
                                .font(.ds.footnoteMedium)
                                .foregroundColor(.ds.textSecondary)
                        }
                    } icon: {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 16, weight: .medium))
                    }
                    .foregroundColor(.ds.text)
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.ds.textSecondary)
                }
                .padding(.horizontal, .ds.screenPadding)
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                VStack(spacing: 0) {
                    if isLoading && comments.isEmpty {
                        LoadingCommentsView()
                            .transition(.opacity)
                    } else if comments.isEmpty {
                        EmptyCommentsView(onComment: showReplyField)
                            .transition(.opacity)
                    } else {
                        // Comments list
                        LazyVStack(spacing: 0) {
                            ForEach(comments) { comment in
                                CommentView(
                                    comment: comment,
                                    authorProfile: profileCache.profiles[comment.author],
                                    onReply: {
                                        replyingTo = comment
                                        showReplyField()
                                    },
                                    onLike: {
                                        Task {
                                            try? await commentService.likeComment(comment)
                                        }
                                    },
                                    onDelete: canDelete(comment) ? {
                                        Task {
                                            try? await commentService.deleteComment(comment)
                                        }
                                    } : nil,
                                    onAuthorTap: {
                                        // Navigate to profile
                                    }
                                )
                                .transition(.asymmetric(
                                    insertion: .push(from: .bottom).combined(with: .opacity),
                                    removal: .push(from: .top).combined(with: .opacity)
                                ))
                                
                                if comment.id != comments.last?.id {
                                    Divider()
                                        .padding(.leading, isReply ? 74 : 56)
                                }
                            }
                        }
                    }
                    
                    // Reply field
                    if showingReplyField {
                        CommentInputField(
                            text: $replyText,
                            replyingTo: replyingTo,
                            isLoading: false,
                            onCancel: {
                                replyingTo = nil
                                showingReplyField = false
                                replyText = ""
                            },
                            onSubmit: postComment
                        )
                        .focused($isReplyFieldFocused)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .onAppear {
                            isReplyFieldFocused = true
                        }
                    } else {
                        // Add comment button
                        Button(action: showReplyField) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 20))
                                Text("Add a comment")
                                    .font(.ds.callout)
                                Spacer()
                            }
                            .foregroundColor(.ds.primary)
                            .padding(.horizontal, .ds.screenPadding)
                            .padding(.vertical, .ds.base)
                            .background(DesignSystem.Colors.primaryLight.opacity(0.1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: .ds.large, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: .ds.large, style: .continuous)
                        .stroke(DesignSystem.Colors.border, lineWidth: 0.5)
                )
                .padding(.horizontal, .ds.screenPadding)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isExpanded)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showingReplyField)
        .task {
            if isExpanded {
                await commentService.loadComments(for: highlightId)
                await loadProfiles()
            }
        }
        .onChange(of: isExpanded) { _, newValue in
            if newValue {
                Task {
                    await commentService.loadComments(for: highlightId)
                    await loadProfiles()
                }
            }
        }
    }
    
    private func toggleExpanded() {
        withAnimation {
            isExpanded.toggle()
        }
        HapticManager.shared.impact(.light)
    }
    
    private func showReplyField() {
        withAnimation {
            showingReplyField = true
        }
    }
    
    private func postComment() {
        let content = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        
        Task {
            do {
                try await commentService.postComment(
                    on: highlightId,
                    content: content,
                    replyingTo: replyingTo
                )
                
                await MainActor.run {
                    replyText = ""
                    replyingTo = nil
                    showingReplyField = false
                }
            } catch {
                print("Failed to post comment: \(error)")
            }
        }
    }
    
    private func canDelete(_ comment: Comment) -> Bool {
        // Check if current user is the author
        if let signer = appState.activeSigner {
            Task {
                let userPubkey = try? await signer.publicKey(format: .hex)
                return userPubkey == comment.author
            }
        }
        return false
    }
    
    private func loadProfiles() async {
        let authors = Set(comments.map { $0.author })
        await profileCache.loadProfiles(for: Array(authors), using: appState.ndk)
    }
}

// MARK: - Supporting Views

struct LoadingCommentsView: View {
    @State private var shimmer = false
    
    var body: some View {
        VStack(spacing: .ds.base) {
            ForEach(0..<3) { _ in
                HStack(alignment: .top, spacing: .ds.base) {
                    Circle()
                        .fill(DesignSystem.Colors.surfaceSecondary)
                        .frame(width: 40, height: 40)
                        .shimmer(when: shimmer)
                    
                    VStack(alignment: .leading, spacing: .ds.small) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(DesignSystem.Colors.surfaceSecondary)
                            .frame(width: 120, height: 14)
                            .shimmer(when: shimmer)
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(DesignSystem.Colors.surfaceSecondary)
                            .frame(width: 200, height: 12)
                            .shimmer(when: shimmer)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, .ds.screenPadding)
                .padding(.vertical, .ds.small)
            }
        }
        .onAppear {
            shimmer = true
        }
    }
}

struct EmptyCommentsView: View {
    let onComment: () -> Void
    
    var body: some View {
        VStack(spacing: .ds.medium) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(.ds.textTertiary)
            
            Text("No comments yet")
                .font(.ds.body)
                .foregroundColor(.ds.textSecondary)
            
            Button(action: onComment) {
                Text("Be the first to comment")
                    .font(.ds.calloutMedium)
                    .foregroundColor(.ds.primary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, .ds.xxl)
    }
}

struct CommentInputField: View {
    @Binding var text: String
    let replyingTo: Comment?
    let isLoading: Bool
    let onCancel: () -> Void
    let onSubmit: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: .ds.small) {
            if let replyingTo = replyingTo {
                HStack {
                    Text("Replying to @\(PubkeyFormatter.formatShort(replyingTo.author))")
                        .font(.ds.caption)
                        .foregroundColor(.ds.textSecondary)
                    
                    Spacer()
                    
                    Button(action: onCancel) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.ds.textTertiary)
                    }
                }
                .padding(.horizontal, .ds.screenPadding)
                .padding(.top, .ds.small)
            }
            
            HStack(alignment: .bottom, spacing: .ds.base) {
                TextField("Add a comment...", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .padding(.ds.base)
                    .background(
                        RoundedRectangle(cornerRadius: .ds.medium)
                            .fill(DesignSystem.Colors.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: .ds.medium)
                                    .stroke(DesignSystem.Colors.border, lineWidth: 1)
                            )
                    )
                
                Button(action: onSubmit) {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(
                                text.isEmpty ? Color.ds.textTertiary : Color.ds.primary
                            )
                    }
                }
                .disabled(text.isEmpty || isLoading)
            }
            .padding(.horizontal, .ds.screenPadding)
            .padding(.vertical, .ds.base)
            .background(DesignSystem.Colors.surfaceSecondary)
        }
    }
}

// MARK: - Profile Cache Manager

@MainActor
class ProfileCacheManager: ObservableObject {
    @Published var profiles: [String: NDKUserProfile] = [:]
    
    func loadProfiles(for pubkeys: [String], using ndk: NDK?) async {
        guard let ndk = ndk else { return }
        
        let unknownPubkeys = pubkeys.filter { profiles[$0] == nil }
        guard !unknownPubkeys.isEmpty else { return }
        
        let filter = NDKFilter(
            authors: unknownPubkeys,
            kinds: [0]
        )
        
        let dataSource = await ndk.outbox.observe(
            filter: filter,
            maxAge: 3600,
            cachePolicy: .cacheWithNetwork
        )
        
        for await event in dataSource.events {
            if let profile = JSONCoding.safeDecode(NDKUserProfile.self, from: event.content) {
                await MainActor.run {
                    self.profiles[event.pubkey] = profile
                }
            }
        }
    }
}

// MARK: - Shimmer Effect

extension View {
    func shimmer(when isActive: Bool) -> some View {
        self.modifier(ShimmerModifier(isActive: isActive))
    }
}

struct ShimmerModifier: ViewModifier {
    let isActive: Bool
    @State private var phase: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.white.opacity(0),
                        Color.white.opacity(0.3),
                        Color.white.opacity(0)
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: phase * 200 - 100)
                .opacity(isActive ? 1 : 0)
                .animation(
                    isActive ? .linear(duration: 1.5).repeatForever(autoreverses: false) : .default,
                    value: phase
                )
                .mask(content)
            )
            .onAppear {
                if isActive {
                    phase = 1
                }
            }
    }
}