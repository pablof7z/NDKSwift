// PostCard.swift
import SwiftUI
import NDKSwift
import NDKSwiftUI

public struct PostCard: View {
    let event: NDKEvent
    let ndk: NDK
    let onProfileTap: ((String) -> Void)?

    @State private var isLiked = false
    @State private var showLikeAnimation = false
    @State private var showComments = false
    @State private var likeCount = 0
    @State private var commentCount = 0
    @State private var zapAmount = 0

    public init(event: NDKEvent, ndk: NDK, onProfileTap: ((String) -> Void)? = nil) {
        self.event = event
        self.ndk = ndk
        self.onProfileTap = onProfileTap
    }

    private var image: NDKImage {
        NDKImage(event: event)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            postHeader
            postImage
            postActions
            postCaption
        }
        .task {
            await loadReactions()
        }
        .sheet(isPresented: $showComments) {
            CommentsSheet(event: event, ndk: ndk)
        }
    }

    private var postHeader: some View {
        HStack(spacing: 12) {
            NDKUIProfilePicture(ndk: ndk, pubkey: event.pubkey, size: 40)
                .clipShape(Circle())
                .onTapGesture {
                    onProfileTap?(event.pubkey)
                }

            VStack(alignment: .leading, spacing: 2) {
                NDKUIDisplayName(ndk: ndk, pubkey: event.pubkey)
                    .font(.subheadline.weight(.semibold))
                    .onTapGesture {
                        onProfileTap?(event.pubkey)
                    }

                NDKUIRelativeTime(timestamp: event.createdAt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                // More options
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var postImage: some View {
        ZStack {
            Group {
                if let imageURL = image.primaryImageURL, let url = URL(string: imageURL) {
                    CachedAsyncImage(url: url) { loadedImage in
                        loadedImage
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } placeholder: {
                        Rectangle()
                            .fill(Color.gray.opacity(0.1))
                            .aspectRatio(1, contentMode: .fit)
                            .overlay(
                                ProgressView()
                                    .tint(OlasTheme.Colors.deepTeal)
                            )
                    }
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.1))
                        .aspectRatio(1, contentMode: .fit)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                        )
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                handleDoubleTap()
            }

            // Like animation overlay
            LikeAnimation(isAnimating: $showLikeAnimation)
        }
    }

    private var postActions: some View {
        HStack(spacing: 20) {
            LikeButton(isLiked: $isLiked, likeCount: likeCount) {
                Task { await toggleLike() }
            }

            CommentButton(commentCount: commentCount) {
                showComments = true
            }

            ZapButton(zapAmount: zapAmount) {
                // Zap action
            }

            Spacer()

            ShareButton {
                // Share action
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var postCaption: some View {
        Group {
            if !event.content.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    PostCaptionText(ndk: ndk, pubkey: event.pubkey, content: event.content)
                        .lineLimit(3)

                    if likeCount > 0 {
                        Text("\(likeCount) like\(likeCount == 1 ? "" : "s")")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            } else if likeCount > 0 {
                Text("\(likeCount) like\(likeCount == 1 ? "" : "s")")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
        }
    }

    private func handleDoubleTap() {
        guard !isLiked else { return }

        // Haptic feedback
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()

        // Show animation
        showLikeAnimation = true

        // Update state
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            isLiked = true
            likeCount += 1
        }

        // Publish reaction
        Task { await publishReaction() }
    }

    private func toggleLike() async {
        if isLiked {
            // Unlike - we don't actually delete, just update UI
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                likeCount = max(0, likeCount - 1)
            }
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                likeCount += 1
            }
            await publishReaction()
        }
    }

    private func publishReaction() async {
        do {
            _ = try await ndk.publish { builder in
                builder
                    .kind(OlasConstants.EventKinds.reaction)
                    .content("+")
                    .tag(["e", event.id])
                    .tag(["p", event.pubkey])
                    .tag(["k", "\(event.kind)"])
            }
        } catch {
            // Revert on error
            withAnimation {
                isLiked = false
                likeCount = max(0, likeCount - 1)
            }
        }
    }

    private func loadReactions() async {
        // Load reactions (kind 7)
        let reactionFilter = NDKFilter(
            kinds: [OlasConstants.EventKinds.reaction],
            limit: 500
        )

        let subscription = ndk.subscribe(filter: reactionFilter)
        var reactions = 0

        for await reactionEvent in subscription.events {
            let referencesOurEvent = reactionEvent.tags.contains { tag in
                tag.first == "e" && tag.count > 1 && tag[1] == event.id
            }

            if referencesOurEvent && reactionEvent.content == "+" {
                reactions += 1
            }

            if reactions >= 100 { break }
        }

        await MainActor.run {
            likeCount = reactions
        }

        // Load comments count
        let commentFilter = NDKFilter(
            kinds: [OlasConstants.EventKinds.comment],
            limit: 100
        )

        let commentSub = ndk.subscribe(filter: commentFilter)
        var comments = 0

        for await commentEvent in commentSub.events {
            let referencesOurEvent = commentEvent.tags.contains { tag in
                tag.first == "e" && tag.count > 1 && tag[1] == event.id
            }

            if referencesOurEvent {
                comments += 1
            }

            if comments >= 50 { break }
        }

        await MainActor.run {
            commentCount = comments
        }
    }
}

// MARK: - PostCaptionText

/// A component that displays username and caption as flowing inline text
private struct PostCaptionText: View {
    let ndk: NDK
    let pubkey: String
    let content: String

    @State private var metadata: NDKUserMetadata?
    @State private var profileTask: Task<Void, Never>?

    var body: some View {
        (Text(displayName).fontWeight(.semibold) + Text(" ") + Text(content))
            .font(.subheadline)
            .onAppear { loadProfile() }
            .onDisappear { profileTask?.cancel() }
    }

    private var displayName: String {
        if let displayName = metadata?.displayName, !displayName.isEmpty {
            return displayName
        }
        if let name = metadata?.name, !name.isEmpty {
            return name
        }
        let npub = NDKUser(pubkey: pubkey).npub
        return String(npub.prefix(16)) + "..."
    }

    private func loadProfile() {
        profileTask?.cancel()
        profileTask = Task {
            for await metadata in await ndk.profileManager.subscribe(for: pubkey) {
                await MainActor.run {
                    self.metadata = metadata
                }
            }
        }
    }
}
