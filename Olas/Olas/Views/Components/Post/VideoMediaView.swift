import SwiftUI
import AVKit
import NDKSwift

struct VideoMediaView: View {
    let event: NDKEvent
    @Binding var showLikeAnimation: Bool
    let onDoubleTap: () -> Void

    @State private var player: AVPlayer?
    @State private var isMuted = true
    @State private var loopObserver: NSObjectProtocol?

    private var video: NDKVideo {
        NDKVideo(event: event)
    }

    var body: some View {
        ZStack {
            if let player {
                VideoPlayer(player: player)
                    .aspectRatio(video.primaryAspectRatio ?? (9.0 / 16.0), contentMode: .fit)
                    .disabled(true)
                    .overlay(videoOverlay)
            } else {
                thumbnailView
            }

            LikeAnimation(isAnimating: $showLikeAnimation)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onDoubleTap() }
        .onTapGesture(count: 1) { toggleMute() }
        .task { setupPlayer() }
        .onDisappear { cleanupPlayer() }
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
                    .tint(OlasTheme.Colors.brandPrimary)
            )
    }

    private var videoOverlay: some View {
        VStack {
            Spacer()
            HStack {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(.black.opacity(0.5))
                    .clipShape(Circle())
                    .padding(8)

                Spacer()

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

    private func setupPlayer() {
        guard let videoURLString = video.primaryVideoURL,
              let videoURL = URL(string: videoURLString) else { return }

        let playerItem = AVPlayerItem(url: videoURL)
        let avPlayer = AVPlayer(playerItem: playerItem)
        avPlayer.isMuted = true

        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { _ in
            avPlayer.seek(to: .zero)
            avPlayer.play()
        }

        self.player = avPlayer

        if SettingsManager.shared.autoplayVideos {
            avPlayer.play()
        }
    }

    private func cleanupPlayer() {
        player?.pause()
        if let observer = loopObserver {
            NotificationCenter.default.removeObserver(observer)
            loopObserver = nil
        }
    }

    private func toggleMute() {
        isMuted.toggle()
        player?.isMuted = isMuted

        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}
