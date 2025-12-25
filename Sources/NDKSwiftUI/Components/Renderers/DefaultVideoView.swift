import AVKit
import SwiftUI

/// Default implementation of VideoRenderer that displays video with native AVPlayer
public struct DefaultVideoView: VideoRenderer {
    public let url: URL
    public let onTap: VideoTapHandler?

    @Environment(\.onVideoTap) private var envOnTap
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var showControls = true
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var showFullscreen = false

    public init(url: URL, onTap: VideoTapHandler? = nil) {
        self.url = url
        self.onTap = onTap
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let player {
                    VideoPlayer(player: player)
                        .disabled(true) // Disable default controls, we use custom overlay
                } else {
                    placeholder
                }

                controlsOverlay
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(Color.black)
            .cornerRadius(12)
            .onTapGesture {
                handleTap()
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            cleanupPlayer()
        }
        .fullScreenCover(isPresented: $showFullscreen) {
            FullscreenVideoPlayer(url: url)
        }
    }

    private var placeholder: some View {
        ZStack {
            Color.black.opacity(0.3)
            ProgressView()
                .tint(.white)
        }
    }

    @ViewBuilder
    private var controlsOverlay: some View {
        if showControls {
            ZStack {
                // Gradient overlay for better button visibility
                LinearGradient(
                    colors: [.black.opacity(0.4), .clear, .black.opacity(0.4)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Play/Pause button
                Button(action: togglePlayPause) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.white)
                        .shadow(radius: 4)
                }
                .buttonStyle(.plain)

                // Expand button in corner
                VStack {
                    HStack {
                        Spacer()
                        Button(action: handleExpandTap) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(8)
                                .background(Color.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .padding(12)
                    }
                    Spacer()
                }
            }
            .transition(.opacity)
        }
    }

    private func setupPlayer() {
        let player = AVPlayer(url: url)
        player.isMuted = true // Start muted for inline playback
        self.player = player

        // Add observer for when video ends
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            self.isPlaying = false
            player.seek(to: .zero)
        }
    }

    private func cleanupPlayer() {
        hideControlsTask?.cancel()
        player?.pause()
        player = nil
    }

    private func handleTap() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showControls = true
        }
        scheduleHideControls()
    }

    private func togglePlayPause() {
        guard let player else { return }

        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
        scheduleHideControls()
    }

    private func handleExpandTap() {
        // Pause inline player before going fullscreen
        player?.pause()
        isPlaying = false

        if let onTap {
            onTap(url)
        } else if let envOnTap {
            envOnTap(url)
        } else {
            // Default behavior: open native fullscreen player
            showFullscreen = true
        }
    }

    private func scheduleHideControls() {
        hideControlsTask?.cancel()
        hideControlsTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
            if !Task.isCancelled && isPlaying {
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showControls = false
                    }
                }
            }
        }
    }
}

// MARK: - Fullscreen Video Player

private struct FullscreenVideoPlayer: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            }

            // Close button
            VStack {
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.white, .black.opacity(0.5))
                    }
                    .padding()
                    Spacer()
                }
                Spacer()
            }
        }
        .onAppear {
            let newPlayer = AVPlayer(url: url)
            newPlayer.play()
            player = newPlayer
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}

#if DEBUG
    struct DefaultVideoView_Previews: PreviewProvider {
        static var previews: some View {
            VStack {
                DefaultVideoView(
                    url: URL(string: "https://example.com/video.mp4")!
                )
                .frame(height: 250)
                .padding()
            }
        }
    }
#endif
