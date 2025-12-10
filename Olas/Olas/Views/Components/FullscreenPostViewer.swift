import SwiftUI
import AVKit
import NDKSwift
import NDKSwiftUI

struct FullscreenPostViewer: View {
    let event: NDKEvent
    let ndk: NDK
    @Binding var isPresented: Bool

    @State private var player: AVPlayer?
    @State private var isMuted = false
    @State private var isLiked = false
    @State private var showLikeAnimation = false
    @State private var likeCount = 0
    @State private var dragOffset: CGFloat = 0

    private var isVideo: Bool {
        event.kind == OlasConstants.EventKinds.shortVideo
    }

    private var image: NDKImage {
        NDKImage(event: event)
    }

    private var video: NDKVideo {
        NDKVideo(event: event)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()

                if isVideo {
                    videoContent
                } else {
                    imageContent
                }

                // Overlay UI
                VStack {
                    // Top bar with close button
                    HStack {
                        Spacer()
                        Button {
                            isPresented = false
                        } label: {
                            Image(systemName: "xmark")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                        .padding()
                    }

                    Spacer()

                    // Bottom info overlay
                    bottomOverlay
                }

                // Like animation
                LikeAnimation(isAnimating: $showLikeAnimation)
            }
            .offset(y: dragOffset)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if abs(value.translation.height) > abs(value.translation.width) {
                            dragOffset = value.translation.height
                        }
                    }
                    .onEnded { value in
                        if abs(value.translation.height) > 100 {
                            isPresented = false
                        } else {
                            withAnimation(.spring(response: 0.3)) {
                                dragOffset = 0
                            }
                        }
                    }
            )
        }
        .statusBarHidden()
        .task {
            if isVideo {
                setupPlayer()
            }
            await loadReactions()
        }
        .onDisappear {
            player?.pause()
        }
    }

    // MARK: - Video Content

    private var videoContent: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
                    .disabled(true)
                    .aspectRatio(video.primaryAspectRatio ?? (9.0 / 16.0), contentMode: .fit)
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            handleDoubleTap()
        }
        .onTapGesture(count: 1) {
            toggleMute()
        }
        .overlay(alignment: .bottomLeading) {
            // Mute indicator
            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.caption)
                .foregroundStyle(.white)
                .padding(8)
                .background(.black.opacity(0.5))
                .clipShape(Circle())
                .padding()
        }
    }

    // MARK: - Image Content

    @State private var imageScale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var imageOffset: CGSize = .zero

    private var imageContent: some View {
        Group {
            if let imageURL = image.primaryImageURL, let url = URL(string: imageURL) {
                CachedAsyncImage(
                    url: url,
                    blurhash: image.primaryBlurhash,
                    aspectRatio: image.primaryAspectRatio
                ) { loadedImage in
                    loadedImage
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(imageScale)
                        .offset(imageOffset)
                } placeholder: {
                    ProgressView()
                        .tint(.white)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if imageScale > 1 {
                withAnimation(.spring()) {
                    imageScale = 1.0
                    imageOffset = .zero
                }
            } else {
                handleDoubleTap()
            }
        }
        .gesture(
            MagnificationGesture()
                .onChanged { value in
                    let delta = value / lastScale
                    lastScale = value
                    imageScale = min(max(imageScale * delta, 1), 5)
                }
                .onEnded { _ in
                    lastScale = 1.0
                    if imageScale < 1.0 {
                        withAnimation(.spring()) {
                            imageScale = 1.0
                            imageOffset = .zero
                        }
                    }
                }
        )
    }

    // MARK: - Bottom Overlay

    private var bottomOverlay: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Author info
            HStack(spacing: 12) {
                NDKUIProfilePicture(ndk: ndk, pubkey: event.pubkey, size: 40)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    NDKUIDisplayName(ndk: ndk, pubkey: event.pubkey)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)

                    NDKUIRelativeTime(timestamp: event.createdAt)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }

                Spacer()
            }

            // Caption
            if !event.content.isEmpty {
                Text(event.content)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .lineLimit(3)
            }

            // Actions
            HStack(spacing: 24) {
                Button {
                    Task {
                        if !isLiked {
                            handleDoubleTap()
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isLiked ? "heart.fill" : "heart")
                            .foregroundStyle(isLiked ? .red : .white)
                        if likeCount > 0 {
                            Text("\(likeCount)")
                                .foregroundStyle(.white)
                        }
                    }
                    .font(.title3)
                }

                ZapButton(event: event, ndk: ndk)
                    .foregroundStyle(.white)

                Spacer()

                ShareButton {}
                    .foregroundStyle(.white)
            }
        }
        .padding()
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - Actions

    private func setupPlayer() {
        guard let videoURLString = video.primaryVideoURL,
              let videoURL = URL(string: videoURLString) else { return }

        let playerItem = AVPlayerItem(url: videoURL)
        let avPlayer = AVPlayer(playerItem: playerItem)
        avPlayer.isMuted = false  // Start with sound ON in fullscreen
        self.isMuted = false
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

        avPlayer.play()
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
}
