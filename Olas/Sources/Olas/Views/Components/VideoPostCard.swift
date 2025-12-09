import SwiftUI
import AVKit
import NDKSwift
import NDKSwiftUI

public struct VideoPostCard: View {
    let event: NDKEvent
    let ndk: NDK
    let onProfileTap: ((String) -> Void)?

    @StateObject private var settings = SettingsManager.shared
    @State private var player: AVPlayer?
    @State private var isMuted = true
    @State private var isLiked = false
    @State private var showLikeAnimation = false
    @State private var showComments = false
    @State private var showReportSheet = false
    @State private var likeCount = 0
    @State private var commentCount = 0

    @EnvironmentObject private var muteListManager: MuteListManager

    public init(event: NDKEvent, ndk: NDK, onProfileTap: ((String) -> Void)? = nil) {
        self.event = event
        self.ndk = ndk
        self.onProfileTap = onProfileTap
    }

    private var video: NDKVideo {
        NDKVideo(event: event)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            postHeader
            videoContent
            postActions
            postCaption
        }
        .accessibilityIdentifier("video_post_card")
        .task {
            setupPlayer()
            await loadReactions()
        }
        .onDisappear {
            player?.pause()
        }
        .sheet(isPresented: $showComments) {
            CommentsSheet(event: event, ndk: ndk)
        }
        .sheet(isPresented: $showReportSheet) {
            ReportSheet(event: event, ndk: ndk)
        }
    }

    private var postHeader: some View {
        HStack(spacing: 12) {
            profilePictureButton

            VStack(alignment: .leading, spacing: 2) {
                Button {
                    onProfileTap?(event.pubkey)
                } label: {
                    NDKUIDisplayName(ndk: ndk, pubkey: event.pubkey)
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("video_post_author_name")

                NDKUIRelativeTime(timestamp: event.createdAt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Menu {
                Button {
                    copyEventId()
                } label: {
                    Label("Copy ID", systemImage: "doc.on.doc")
                }

                Button(role: .destructive) {
                    showReportSheet = true
                } label: {
                    Label("Report", systemImage: "exclamationmark.triangle")
                }

                Button(role: .destructive) {
                    Task { await muteAuthor() }
                } label: {
                    Label("Mute Author", systemImage: "speaker.slash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityIdentifier("video_post_author_header")
    }

    private var profilePictureButton: some View {
        Button {
            onProfileTap?(event.pubkey)
        } label: {
            NDKUIProfilePicture(ndk: ndk, pubkey: event.pubkey, size: 40)
                .clipShape(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("video_post_author_avatar")
    }

    private var videoContent: some View {
        ZStack {
            if let player {
                VideoPlayer(player: player)
                    .aspectRatio(video.primaryAspectRatio ?? (9.0 / 16.0), contentMode: .fit)
                    .disabled(true) // Disable default controls
                    .overlay(videoOverlay)
            } else {
                // Thumbnail/placeholder while loading
                thumbnailView
            }

            // Like animation overlay
            LikeAnimation(isAnimating: $showLikeAnimation)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            handleDoubleTap()
        }
        .onTapGesture(count: 1) {
            toggleMute()
        }
    }

    private var thumbnailView: some View {
        Group {
            if let thumbnailURLString = video.thumbnailURL,
               let thumbnailURL = URL(string: thumbnailURLString) {
                CachedAsyncImage(
                    url: thumbnailURL,
                    blurhash: video.primaryBlurhash,
                    aspectRatio: video.primaryAspectRatio
                ) { loadedImage in
                    loadedImage
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } placeholder: {
                    videoPlaceholder
                }
            } else {
                videoPlaceholder
            }
        }
        .overlay(
            Image(systemName: "play.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.white.opacity(0.8))
        )
    }

    private var videoPlaceholder: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.1))
            .aspectRatio(video.primaryAspectRatio ?? (9.0 / 16.0), contentMode: .fit)
            .overlay(
                ProgressView()
                    .tint(OlasTheme.Colors.deepTeal)
            )
    }

    private var videoOverlay: some View {
        VStack {
            Spacer()
            HStack {
                // Mute indicator
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(.black.opacity(0.5))
                    .clipShape(Circle())
                    .padding(8)

                Spacer()

                // Duration badge
                if let duration = video.duration {
                    Text(formatDuration(duration))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.5))
                        .cornerRadius(4)
                        .padding(8)
                }
            }
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

            ZapButton(event: event, ndk: ndk)

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
                    VideoCaptionText(ndk: ndk, pubkey: event.pubkey, content: event.content)
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

    // MARK: - Actions

    private func setupPlayer() {
        guard let videoURLString = video.primaryVideoURL,
              let videoURL = URL(string: videoURLString) else { return }

        let playerItem = AVPlayerItem(url: videoURL)
        let avPlayer = AVPlayer(playerItem: playerItem)
        avPlayer.isMuted = true
        self.player = avPlayer

        // Loop video
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { _ in
            avPlayer.seek(to: .zero)
            avPlayer.play()
        }

        // Autoplay if enabled
        if settings.autoplayVideos {
            avPlayer.play()
        }
    }

    private func toggleMute() {
        isMuted.toggle()
        player?.isMuted = isMuted

        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
    }

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

    private func muteAuthor() async {
        do {
            try await muteListManager.mute(event.pubkey)
        } catch {
            // Mute failed silently
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

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - VideoCaptionText

private struct VideoCaptionText: View {
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
