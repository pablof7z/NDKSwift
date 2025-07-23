import SwiftUI
import NDKSwift
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
    @State private var cardScale: CGFloat = 1
    @State private var showingReplyRecorder = false
    
    @GestureState private var dragOffset = CGSize.zero
    @State private var swipeOffset = CGSize.zero
    
    var isCurrentlyPlaying: Bool {
        appState.currentlyPlayingId == audioEvent.id && isPlaying
    }
    
    var body: some View {
        ZStack {
            // Background glow when playing
            if isCurrentlyPlaying {
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.purple.opacity(0.3),
                                Color.blue.opacity(0.2)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blur(radius: 20)
                    .scaleEffect(1.1)
            }
            
            VStack(spacing: 0) {
                // Main card content
                HStack(alignment: .top, spacing: 16) {
                    // Author avatar
                    AuthorAvatar(pubkey: audioEvent.author.pubkey, profile: author)
                        .frame(width: 48, height: 48)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        // Author info
                        HStack {
                            Text(author?.displayName ?? author?.name ?? String(audioEvent.author.pubkey.prefix(8)))
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                            
                            if audioEvent.webOfTrustScore >= 0.8 {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.purple)
                            }
                            
                            Spacer()
                            
                            Text(relativeTime(from: audioEvent.createdAt))
                                .font(.system(size: 12))
                                .foregroundColor(Color.white.opacity(0.6))
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
                    }
                }
                .padding()
                
                // Swipe hint
                if swipeOffset.width < -20 {
                    HStack {
                        Spacer()
                        Text("Swipe to reply")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.purple)
                            .padding(.trailing)
                            .padding(.bottom, 8)
                    }
                    .transition(.opacity)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.08),
                                Color.white.opacity(0.03)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(
                                isCurrentlyPlaying ? Color.purple.opacity(0.5) : Color.white.opacity(0.1),
                                lineWidth: 1
                            )
                    )
            )
            .scaleEffect(cardScale)
            .offset(x: swipeOffset.width + dragOffset.width)
            .gesture(
                DragGesture()
                    .updating($dragOffset) { value, state, _ in
                        if value.translation.width < 0 {
                            state = value.translation
                        }
                    }
                    .onEnded { value in
                        if value.translation.width < -100 {
                            // Trigger reply recording
                            withAnimation(.spring()) {
                                showingReplyRecorder = true
                            }
                        }
                        withAnimation(.spring()) {
                            swipeOffset = .zero
                        }
                    }
            )
        }
        .onAppear {
            loadAuthorProfile()
            setupAudioPlayer()
        }
        .onDisappear {
            cleanup()
        }
        .onChange(of: appState.currentlyPlayingId) { newId in
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
            
            if let profile = await ndk.fetchProfile(audioEvent.author.pubkey) {
                await MainActor.run {
                    self.author = profile
                }
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
        timeObserver = audioPlayer?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self,
                  let duration = self.audioPlayer?.currentItem?.duration else { return }
            
            let currentTime = time.seconds
            let totalTime = duration.seconds
            
            if totalTime > 0 {
                self.playbackProgress = currentTime / totalTime
            }
            
            // Check if playback ended
            if currentTime >= totalTime - 0.1 {
                self.pausePlayback()
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
}

// MARK: - Author Avatar
struct AuthorAvatar: View {
    let pubkey: String
    let profile: NDKUserProfile?
    
    var body: some View {
        if let picture = profile?.picture,
           let url = URL(string: picture) {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                DefaultAvatar(pubkey: pubkey)
            }
            .frame(width: 48, height: 48)
            .clipShape(Circle())
        } else {
            DefaultAvatar(pubkey: pubkey)
        }
    }
}

struct DefaultAvatar: View {
    let pubkey: String
    
    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.purple,
                        Color.blue
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Text(String(pubkey.prefix(2)))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
            )
            .frame(width: 48, height: 48)
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
    
    var formattedDuration: String {
        let totalSeconds = Int(duration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var formattedCurrentTime: String {
        let currentSeconds = Int(duration * displayProgress)
        let minutes = currentSeconds / 60
        let seconds = currentSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Waveform or progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    Capsule()
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 40)
                    
                    // Progress
                    Capsule()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.purple.opacity(0.8),
                                    Color.blue.opacity(0.6)
                                ]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * displayProgress, height: 40)
                    
                    // Waveform visualization (simplified)
                    HStack(spacing: 2) {
                        ForEach(0..<30) { index in
                            Capsule()
                                .fill(Color.white.opacity(0.3))
                                .frame(width: 2, height: CGFloat.random(in: 10...30))
                        }
                    }
                    .padding(.horizontal, 8)
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
            .frame(height: 40)
            
            // Controls
            HStack {
                // Play/Pause button
                Button(action: onPlayPause) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(
                            Circle()
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color.purple,
                                            Color.blue
                                        ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                }
                
                // Time labels
                Text(formattedCurrentTime)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Color.white.opacity(0.6))
                
                Spacer()
                
                Text(formattedDuration)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Color.white.opacity(0.6))
            }
        }
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
                        AuthorAvatar(pubkey: replyingTo.author.pubkey, profile: nil)
                            .frame(width: 32, height: 32)
                        
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