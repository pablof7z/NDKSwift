import SwiftUI
import NDKSwift
import NDKSwiftUI
import AVFoundation

struct AudioEventCard: View {
    let audioEvent: AudioEvent
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var nostrManager: NostrManager
    
    @State private var author: NDKUserProfile?
    @State private var isPlaying = false
    @State private var playbackProgress: Double = 0
    @State private var duration: TimeInterval = 0
    @State private var audioPlayer: AVPlayer?
    @State private var timeObserver: Any?
    @State private var showingReplyRecorder = false
    
    // Reaction states
    @State private var hasLiked: Bool = false
    @State private var reactionCount: Int = 0
    @State private var reactions: [NDKEvent] = []
    @State private var cardScale: CGFloat = 1
    
    var isCurrentlyPlaying: Bool {
        appState.currentlyPlayingId == audioEvent.id && isPlaying
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Author avatar using NDKSwiftUI component
            NDKProfilePicture(pubkey: audioEvent.author.pubkey, size: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                // Author info
                HStack(spacing: 4) {
                    Text(author?.displayName ?? author?.name ?? String(audioEvent.author.pubkey.prefix(8)))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    if audioEvent.webOfTrustScore >= 0.8 {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.purple)
                    }
                    
                    Text("•")
                        .font(.system(size: 11))
                        .foregroundColor(Color.white.opacity(0.4))
                    
                    Text(relativeTime(from: audioEvent.createdAt))
                        .font(.system(size: 12))
                        .foregroundColor(Color.white.opacity(0.6))
                    
                    Spacer()
                }
                
                // Reply indicator
                if audioEvent.isReply {
                    HStack(spacing: 4) {
                        Image(systemName: "arrowshape.turn.up.left.fill")
                            .font(.system(size: 10))
                        Text("Reply")
                            .font(.system(size: 12))
                    }
                    .foregroundColor(Color.white.opacity(0.5))
                }
                
                // Audio player
                AudioPlayerView(
                    isPlaying: $isPlaying,
                    progress: $playbackProgress,
                    duration: duration,
                    onPlayPause: togglePlayback,
                    onSeek: seek
                )
                
                // Reactions bar (minimal)
                HStack(spacing: 16) {
                    Button(action: handleLike) {
                        HStack(spacing: 4) {
                            Image(systemName: hasLiked ? "heart.fill" : "heart")
                                .font(.system(size: 16))
                                .foregroundColor(hasLiked ? .red : Color.white.opacity(0.5))
                            if reactionCount > 0 {
                                Text("\(reactionCount)")
                                    .font(.system(size: 14))
                                    .foregroundColor(Color.white.opacity(0.6))
                            }
                        }
                    }
                    
                    Button(action: { showingReplyRecorder = true }) {
                        Image(systemName: "bubble.left")
                            .font(.system(size: 16))
                            .foregroundColor(Color.white.opacity(0.5))
                    }
                    
                    Spacer()
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            isCurrentlyPlaying ? Color.white.opacity(0.03) : Color.clear
        )
        .onAppear {
            loadAuthorProfile()
            setupAudioPlayer()
            loadReactions()
        }
        .onDisappear {
            cleanup()
        }
        .onChange(of: appState.currentlyPlayingId) { _, newId in
            if newId != audioEvent.id && isPlaying {
                pausePlayback()
            }
        }
        .fullScreenCover(isPresented: $showingReplyRecorder) {
            ReplyRecordingView(replyingTo: audioEvent)
        }
    }
    
    private func loadAuthorProfile() {
        Task {
            guard let ndk = nostrManager.ndk else { return }
            
            for await profile in ndk.profileManager.observe(for: audioEvent.author.pubkey, maxAge: 3600) {
                await MainActor.run {
                    self.author = profile
                }
                break // Just get the first result
            }
        }
    }
    
    private func setupAudioPlayer() {
        guard let url = URL(string: audioEvent.audioURL) else { return }
        
        let playerItem = AVPlayerItem(url: url)
        audioPlayer = AVPlayer(playerItem: playerItem)
        
        // Get duration
        Task {
            let duration = try await playerItem.asset.load(.duration)
            await MainActor.run {
                self.duration = duration.seconds
            }
        }
        
        // Observe playback progress
        let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = audioPlayer?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            guard let duration = audioPlayer?.currentItem?.duration else { return }
            
            let currentTime = time.seconds
            let totalTime = duration.seconds
            
            if totalTime > 0 {
                playbackProgress = currentTime / totalTime
            }
            
            // Check if playback ended
            if currentTime >= totalTime - 0.1 {
                pausePlayback()
            }
        }
    }
    
    private func togglePlayback() {
        if isPlaying {
            pausePlayback()
        } else {
            startPlayback()
        }
    }
    
    private func startPlayback() {
        // Stop any other playing audio
        appState.currentlyPlayingId = audioEvent.id
        
        audioPlayer?.play()
        isPlaying = true
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            cardScale = 1.02
        }
    }
    
    private func pausePlayback() {
        audioPlayer?.pause()
        isPlaying = false
        
        if appState.currentlyPlayingId == audioEvent.id {
            appState.currentlyPlayingId = nil
        }
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            cardScale = 1
        }
    }
    
    private func seek(to progress: Double) {
        guard let duration = audioPlayer?.currentItem?.duration else { return }
        
        let targetTime = CMTime(seconds: progress * duration.seconds, preferredTimescale: duration.timescale)
        audioPlayer?.seek(to: targetTime)
    }
    
    private func cleanup() {
        if let observer = timeObserver {
            audioPlayer?.removeTimeObserver(observer)
        }
        audioPlayer = nil
    }
    
    private func relativeTime(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        
        if interval < 60 {
            return "now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d"
        }
    }
    
    private func formattedDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration)
        if totalSeconds < 60 {
            return "\(totalSeconds)s"
        } else {
            let minutes = totalSeconds / 60
            let seconds = totalSeconds % 60
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    private func loadReactions() {
        Task {
            guard let ndk = nostrManager.ndk else { return }
            
            // Load reactions specifically for this event using #e tag
            let filter = NDKFilter(
                kinds: [7],
                tags: ["e": [audioEvent.id]]
            )
            
            let dataSource = ndk.observe(filter: filter, maxAge: 0)
            
            for await event in dataSource.events {
                // Only count positive reactions
                if event.content == "+" || event.content == "🤙" || event.content == "❤️" || event.content == "♥️" {
                    await MainActor.run {
                        // Add to reactions list if not already present
                        if !self.reactions.contains(where: { $0.id == event.id }) {
                            self.reactions.append(event)
                            self.reactionCount = self.reactions.count
                            
                            // Check if current user has reacted
                            if let currentUserPubkey = appState.currentUser?.pubkey,
                               event.pubkey == currentUserPubkey {
                                self.hasLiked = true
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func handleLike() {
        guard let ndk = nostrManager.ndk else { return }
        
        Task {
            if hasLiked {
                // Already liked, don't unlike for now
                return
            }
            
            do {
                // Use NDKEventBuilder to create and publish reaction
                let (event, _) = try await ndk.publish { builder in
                    builder
                        .kind(7)  // Reaction event
                        .content("+")
                        .tag(["e", audioEvent.id])
                        .tag(["p", audioEvent.author.pubkey])
                }
                
                await MainActor.run {
                    hasLiked = true
                }
            } catch {
                print("Failed to publish reaction: \(error)")
            }
        }
    }
    
}

// MARK: - Audio Player View
struct AudioPlayerView: View {
    @Binding var isPlaying: Bool
    @Binding var progress: Double
    let duration: TimeInterval
    let onPlayPause: () -> Void
    let onSeek: (Double) -> Void
    
    @State private var isDragging = false
    @State private var dragProgress: Double = 0
    
    var displayProgress: Double {
        isDragging ? dragProgress : progress
    }
    
    var remainingTime: String {
        let remainingSeconds = Int(duration * (1 - displayProgress))
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                Capsule()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 36)
                
                // Progress
                Capsule()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.purple.opacity(0.7),
                                Color.blue.opacity(0.5)
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * displayProgress, height: 36)
                
                // Content overlay
                HStack {
                    // Play/Pause button integrated
                    Button(action: onPlayPause) {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                            .frame(width: 28, height: 28)
                            .background(
                                Circle()
                                    .fill(Color.black.opacity(0.3))
                            )
                    }
                    .padding(.leading, 4)
                    
                    Spacer()
                    
                    // Remaining time
                    if duration > 0 {
                        Text(remainingTime)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.trailing, 12)
                    }
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        dragProgress = min(max(0, value.location.x / geometry.size.width), 1)
                    }
                    .onEnded { _ in
                        isDragging = false
                        onSeek(dragProgress)
                    }
            )
        }
        .frame(height: 36)
    }
}


// MARK: - Reply Recording View
struct ReplyRecordingView: View {
    let replyingTo: AudioEvent
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.95)
                .ignoresSafeArea()
            
            VStack(spacing: 30) {
                // Header
                HStack {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                    
                    Spacer()
                    
                    Text("Reply")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Button("Cancel") {
                        dismiss()
                    }
                    .opacity(0)
                }
                .padding()
                
                // Original message preview
                VStack(alignment: .leading, spacing: 8) {
                    Text("Replying to")
                        .font(.system(size: 14))
                        .foregroundColor(Color.white.opacity(0.6))
                    
                    // Mini version of the original card
                    HStack {
                        NDKProfilePicture(pubkey: replyingTo.author.pubkey, size: 32)
                        
                        VStack(alignment: .leading) {
                            Text(String(replyingTo.author.pubkey.prefix(8)))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                            
                            Text("Voice message")
                                .font(.system(size: 12))
                                .foregroundColor(Color.white.opacity(0.5))
                        }
                        
                        Spacer()
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.05))
                    )
                }
                .padding(.horizontal)
                
                Spacer()
                
                // TODO: Add recording UI here
                Text("Recording UI Coming Soon")
                    .foregroundColor(.white)
                
                Spacer()
            }
        }
    }
}