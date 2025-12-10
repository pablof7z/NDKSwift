import SwiftUI
import NDKSwift

struct PostCard: View {
    let event: NDKEvent
    let ndk: NDK
    let onProfileTap: ((String) -> Void)?

    @State private var isLiked = false
    @State private var showLikeAnimation = false
    @State private var likeCount = 0
    @State private var commentCount = 0
    @State private var showComments = false
    @State private var showReportSheet = false
    @State private var showAddToCollection = false
    @State private var showFullscreenImage = false

    @Environment(MuteListManager.self) private var muteListManager

    public init(event: NDKEvent, ndk: NDK, onProfileTap: ((String) -> Void)? = nil) {
        self.event = event
        self.ndk = ndk
        self.onProfileTap = onProfileTap
    }

    private var isVideo: Bool {
        event.kind == OlasConstants.EventKinds.shortVideo
    }

    private var image: NDKImage {
        NDKImage(event: event)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PostHeader(
                event: event,
                ndk: ndk,
                onProfileTap: onProfileTap,
                onCopyId: copyEventId,
                onReport: { showReportSheet = true },
                onMute: { Task { await muteAuthor() } }
            )

            mediaContent

            PostActions(
                event: event,
                ndk: ndk,
                isLiked: $isLiked,
                likeCount: likeCount,
                commentCount: commentCount,
                onLikeTap: { Task { await toggleLike() } },
                onCommentTap: { showComments = true },
                onAddToCollection: { showAddToCollection = true },
                onShare: sharePost
            )

            PostCaption(
                ndk: ndk,
                pubkey: event.pubkey,
                content: event.content,
                likeCount: likeCount
            )
        }
        .accessibilityIdentifier(isVideo ? "video_post_card" : "post_card")
        .task { await loadReactions() }
        .sheet(isPresented: $showComments) {
            CommentsSheet(event: event, ndk: ndk)
        }
        .sheet(isPresented: $showReportSheet) {
            ReportSheet(event: event, ndk: ndk)
        }
        .sheet(isPresented: $showAddToCollection) {
            AddToCollectionSheet(pictureEvent: event)
        }
        .fullScreenCover(isPresented: $showFullscreenImage) {
            if let imageURL = image.primaryImageURL, let url = URL(string: imageURL) {
                FullscreenImageViewer(
                    url: url,
                    blurhash: image.primaryBlurhash,
                    aspectRatio: image.primaryAspectRatio,
                    isPresented: $showFullscreenImage
                )
            }
        }
    }

    // MARK: - Media Content

    @ViewBuilder
    private var mediaContent: some View {
        if isVideo {
            VideoMediaView(
                event: event,
                showLikeAnimation: $showLikeAnimation,
                onDoubleTap: handleDoubleTap
            )
        } else {
            ImageMediaView(
                event: event,
                showLikeAnimation: $showLikeAnimation,
                onDoubleTap: handleDoubleTap,
                onTap: { showFullscreenImage = true }
            )
        }
    }

    // MARK: - Interactions

    private func handleDoubleTap() {
        guard !isLiked else { return }

        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()

        showLikeAnimation = true

        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            isLiked = true
            likeCount += 1
        }

        Task { await publishReaction() }
    }

    private func toggleLike() async {
        if isLiked {
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
            withAnimation {
                isLiked = false
                likeCount = max(0, likeCount - 1)
            }
        }
    }

    // MARK: - Loading Reactions

    private func loadReactions() async {
        async let reactionTask: () = loadReactionCount()
        async let commentTask: () = loadCommentCount()
        _ = await (reactionTask, commentTask)
    }

    private func loadReactionCount() async {
        let reactionFilter = NDKFilter(
            kinds: [OlasConstants.EventKinds.reaction],
            limit: 500
        )

        let subscription = ndk.subscribe(filter: reactionFilter)

        for await reactionEvent in subscription.events {
            let referencesOurEvent = reactionEvent.tags.contains { tag in
                tag.first == "e" && tag.count > 1 && tag[1] == event.id
            }

            if referencesOurEvent && reactionEvent.content == "+" {
                likeCount += 1
            }
        }
    }

    private func loadCommentCount() async {
        let commentFilter = NDKFilter(
            kinds: [OlasConstants.EventKinds.comment],
            limit: 100
        )

        let commentSub = ndk.subscribe(filter: commentFilter)

        for await commentEvent in commentSub.events {
            let referencesOurEvent = commentEvent.tags.contains { tag in
                tag.first == "e" && tag.count > 1 && tag[1] == event.id
            }

            if referencesOurEvent {
                commentCount += 1
            }
        }
    }

    // MARK: - Actions

    private func muteAuthor() async {
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()

        do {
            try await muteListManager.mute(event.pubkey)
        } catch {
            // Mute failed silently - user can retry
        }
    }

    private func copyEventId() {
        guard let nevent = try? Bech32.nevent(eventId: event.id, author: event.pubkey, kind: event.kind) else {
            return
        }
        UIPasteboard.general.string = nevent

        let impact = UINotificationFeedbackGenerator()
        impact.notificationOccurred(.success)
    }

    private func sharePost() {
        guard let nevent = try? Bech32.nevent(eventId: event.id, author: event.pubkey, kind: event.kind) else {
            return
        }
        let url = "https://njump.me/\(nevent)"
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
}
