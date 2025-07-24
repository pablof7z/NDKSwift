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
    @State private var reactionsByEmoji: [String: [NDKEvent]] = [:]
    @State private var userReactions: Set<String> = []
    @State private var showingReactionPopover = false
    @State private var showingReactionsDrawer = false
    @State private var selectedReactionEmoji: String?
    @State private var cardScale: CGFloat = 1
    @State private var showingUserProfile = false
    
    var isCurrentlyPlaying: Bool {
        appState.currentlyPlayingId == audioEvent.id && isPlaying
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Author avatar using NDKSwiftUI component
            NDKProfilePicture(pubkey: audioEvent.author.pubkey, size: 40)
                .onTapGesture {
                    showingUserProfile = true
                }
            
            VStack(alignment: .leading, spacing: 4) {
                // Author info
                HStack(spacing: 4) {
                    Text(author?.displayName ?? author?.name ?? String(audioEvent.author.pubkey.prefix(8)))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .onTapGesture {
                            showingUserProfile = true
                        }
                    
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
                    waveform: audioEvent.waveform,
                    onPlayPause: togglePlayback,
                    onSeek: seek
                )
                
                // Hashtags
                if !audioEvent.hashtags.isEmpty {
                    HashtagsView(hashtags: audioEvent.hashtags)
                        .padding(.top, 8)
                }
                
                // Reactions bar
                HStack(spacing: 16) {
                    // Reaction button
                    Button(action: { showingReactionPopover = true }) {
                        Image(systemName: userReactions.isEmpty ? "face.smiling" : "face.smiling.fill")
                            .font(.system(size: 16))
                            .foregroundColor(userReactions.isEmpty ? Color.white.opacity(0.5) : .yellow)
                    }
                    .popover(isPresented: $showingReactionPopover) {
                        ReactionPopover(onReaction: handleReaction)
                    }
                    
                    // Reaction pills
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(reactionsByEmoji.keys.sorted(), id: \.self) { emoji in
                                ReactionPill(
                                    emoji: emoji,
                                    count: reactionsByEmoji[emoji]?.count ?? 0,
                                    isSelected: userReactions.contains(emoji),
                                    onTap: {
                                        selectedReactionEmoji = emoji
                                        showingReactionsDrawer = true
                                    }
                                )
                            }
                        }
                    }
                    .frame(maxWidth: 200)
                    
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
        .sheet(isPresented: $showingUserProfile) {
            NavigationView {
                UserProfileView(pubkey: audioEvent.author.pubkey)
            }
        }
        .sheet(isPresented: $showingReactionsDrawer) {
            if let emoji = selectedReactionEmoji {
                ReactionsDrawer(
                    emoji: emoji,
                    reactions: reactionsByEmoji[emoji] ?? [],
                    nostrManager: nostrManager
                )
            }
        }
    }
    
    private func loadAuthorProfile() {
        Task {
            guard let ndk = nostrManager.ndk else { return }
            
            for await profile in await ndk.profileManager.observe(for: audioEvent.author.pubkey, maxAge: TimeConstants.hour) {
                await MainActor.run {
                    self.author = profile
                }
                break // Just get the first result
            }
        }
    }
    
    private func setupAudioPlayer() {
        guard let url = URL(string: audioEvent.audioURL) else { return }
        
        // Configure audio session for proper Bluetooth support
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playback, mode: .default, options: [.allowBluetooth, .allowAirPlay])
            try audioSession.setActive(true)
        } catch {
            print("Failed to configure audio session: \(error)")
        }
        
        let playerItem = AVPlayerItem(url: url)
        audioPlayer = AVPlayer(playerItem: playerItem)
        
        // Use pre-loaded duration from imeta if available, otherwise load from asset
        if let metadataDuration = audioEvent.duration {
            self.duration = metadataDuration
        } else {
            // Get duration
            Task {
                let duration = try await playerItem.asset.load(.duration)
                await MainActor.run {
                    self.duration = duration.seconds
                }
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
                // Reset progress to 1 to indicate playback has completed
                playbackProgress = 1.0
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
        
        // Seek to beginning if playback has ended or progress is near the end
        if let duration = audioPlayer?.currentItem?.duration {
            let currentTime = audioPlayer?.currentTime() ?? CMTime.zero
            let totalTime = duration.seconds
            let currentSeconds = currentTime.seconds
            
            // If we're at the end (within last 0.5 seconds) or past the end, seek to beginning
            if currentSeconds >= totalTime - 0.5 || playbackProgress >= 0.99 {
                audioPlayer?.seek(to: CMTime.zero) { _ in
                    self.playbackProgress = 0
                }
            }
        }
        
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
        guard let duration = audioPlayer?.currentItem?.duration,
              duration.isValid,
              duration.isNumeric,
              !duration.isIndefinite else { return }
        
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
        
        if interval < TimeConstants.minute {
            return "now"
        } else if interval < TimeConstants.hour {
            let minutes = Int(interval / TimeConstants.minute)
            return "\(minutes)m"
        } else if interval < TimeConstants.day {
            let hours = Int(interval / TimeConstants.hour)
            return "\(hours)h"
        } else {
            let days = Int(interval / TimeConstants.day)
            return "\(days)d"
        }
    }
    
    private func formattedDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration)
        if totalSeconds < Int(TimeConstants.minute) {
            return "\(totalSeconds)s"
        } else {
            let minutes = totalSeconds / Int(TimeConstants.minute)
            let seconds = totalSeconds % Int(TimeConstants.minute)
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
                // Process all emoji reactions
                let emoji = normalizeReactionEmoji(event.content)
                if isValidReactionEmoji(emoji) {
                    await MainActor.run {
                        // Group reactions by emoji
                        if reactionsByEmoji[emoji] == nil {
                            reactionsByEmoji[emoji] = []
                        }
                        
                        // Add if not already present
                        if !reactionsByEmoji[emoji]!.contains(where: { $0.id == event.id }) {
                            reactionsByEmoji[emoji]!.append(event)
                            
                            // Check if current user has reacted with this emoji
                            if let currentUserPubkey = appState.currentUser?.pubkey,
                               event.pubkey == currentUserPubkey {
                                userReactions.insert(emoji)
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func normalizeReactionEmoji(_ content: String) -> String {
        // Map common variations to standard emojis
        switch content {
        case "+", "👍": return "👍"
        case "❤️", "♥️": return "❤️"
        case "🤙": return "🤙"
        default: return content
        }
    }
    
    private func isValidReactionEmoji(_ emoji: String) -> Bool {
        // Only allow single emoji characters or + symbol
        if emoji == "+" || emoji == "👍" { return true }
        
        // Check if it's a single emoji
        let scalars = emoji.unicodeScalars
        guard scalars.count >= 1 else { return false }
        
        // Simple emoji validation
        return emoji.count <= 4 && emoji.containsEmoji
    }
    
    private func handleReaction(_ emoji: String) {
        guard let ndk = nostrManager.ndk else { return }
        
        Task {
            if userReactions.contains(emoji) {
                // Already reacted with this emoji
                return
            }
            
            do {
                // Use NDKEventBuilder to create and publish reaction
                let (_, _) = try await ndk.publish { builder in
                    builder
                        .kind(7)  // Reaction event
                        .content(emoji)
                        .tag(["e", audioEvent.id])
                        .tag(["p", audioEvent.author.pubkey])
                }
                
                await MainActor.run {
                    userReactions.insert(emoji)
                    showingReactionPopover = false
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
    let waveform: [Double]?
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
                // Background with waveform or simple capsule
                if let waveform = waveform, !waveform.isEmpty {
                    // Waveform visualization
                    HStack(spacing: 1) {
                        ForEach(0..<waveform.count, id: \.self) { index in
                            let barHeight = 8 + (waveform[index] * 20) // Min 8, max 28
                            let progressPosition = Double(index) / Double(waveform.count - 1)
                            let isPassed = progressPosition <= displayProgress
                            
                            Capsule()
                                .fill(
                                    isPassed ?
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color.purple.opacity(0.7),
                                            Color.blue.opacity(0.5)
                                        ]),
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ) :
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color.white.opacity(0.15),
                                            Color.white.opacity(0.08)
                                        ]),
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(width: max(1, geometry.size.width / CGFloat(waveform.count) - 1), 
                                       height: barHeight)
                        }
                    }
                    .frame(height: 36)
                } else {
                    // Fallback to simple progress bar
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
                }
                
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
                        // Only allow dragging if duration is valid
                        if duration > 0 {
                            isDragging = true
                            dragProgress = min(max(0, value.location.x / geometry.size.width), 1)
                        }
                    }
                    .onEnded { _ in
                        // Only seek if duration is valid
                        if duration > 0 {
                            isDragging = false
                            onSeek(dragProgress)
                        }
                    }
            )
        }
        .frame(height: 36)
    }
}


// MARK: - Reaction Components
struct ReactionPopover: View {
    let onReaction: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    
    let reactionEmojis = ["👍", "❤️", "😂", "🔥", "🤙", "⚡️", "💜", "🤔", "😍", "💯"]
    
    var body: some View {
        VStack(spacing: 0) {
            Text("React")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                .padding(.top, 12)
                .padding(.bottom, 8)
            
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 8) {
                ForEach(reactionEmojis, id: \.self) { emoji in
                    Button(action: {
                        onReaction(emoji)
                        dismiss()
                    }) {
                        Text(emoji)
                            .font(.system(size: 28))
                            .frame(width: 44, height: 44)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(0.08))
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .frame(width: 240)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(UIColor.systemGray6))
        )
        .preferredColorScheme(.dark)
    }
}

struct ReactionPill: View {
    let emoji: String
    let count: Int
    let isSelected: Bool
    let onTap: () -> Void
    
    private var pillBackground: LinearGradient {
        if isSelected {
            return LinearGradient(
                gradient: Gradient(colors: [Color.purple.opacity(0.6), Color.blue.opacity(0.4)]),
                startPoint: .leading,
                endPoint: .trailing
            )
        } else {
            return LinearGradient(
                gradient: Gradient(colors: [Color.white.opacity(0.08), Color.white.opacity(0.05)]),
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Text(emoji)
                    .font(.system(size: 14))
                Text("\(count)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.7))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(pillBackground)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ReactionsDrawer: View {
    let emoji: String
    let reactions: [NDKEvent]
    let nostrManager: NostrManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var profiles: [String: NDKUserProfile] = [:]
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 0) {
                        headerSection
                        
                        Divider()
                            .background(Color.white.opacity(0.1))
                        
                        reactionsList
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .onAppear {
            loadProfiles()
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Text(emoji)
                .font(.system(size: 60))
                .padding(.top, 20)
            
            Text("\(reactions.count) reaction\(reactions.count == 1 ? "" : "s")")
                .font(.system(size: 16))
                .foregroundColor(.white.opacity(0.6))
                .padding(.bottom, 12)
        }
    }
    
    private var reactionsList: some View {
        LazyVStack(spacing: 0) {
            ForEach(reactions, id: \.id) { reaction in
                reactionRow(for: reaction)
                
                Divider()
                    .background(Color.white.opacity(0.1))
            }
        }
    }
    
    private func reactionRow(for reaction: NDKEvent) -> some View {
        HStack(spacing: 12) {
            NDKProfilePicture(pubkey: reaction.pubkey, size: 40)
            
            profileInfo(for: reaction.pubkey)
            
            Spacer()
            
            Text(relativeTime(from: Date(timeIntervalSince1970: TimeInterval(reaction.createdAt))))
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.4))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    private func profileInfo(for pubkey: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let profile = profiles[pubkey] {
                Text(profile.displayName ?? profile.name ?? String(pubkey.prefix(8)))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                if let name = profile.name, profile.displayName != nil {
                    Text("@\(name)")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                }
            } else {
                Text(String(pubkey.prefix(8)) + "...")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
    }
    
    private func loadProfiles() {
        Task {
            guard let ndk = nostrManager.ndk else { return }
            
            for reaction in reactions {
                for await profile in await ndk.profileManager.observe(for: reaction.pubkey, maxAge: TimeConstants.hour) {
                    await MainActor.run {
                        profiles[reaction.pubkey] = profile
                    }
                    break
                }
            }
        }
    }
    
    private func relativeTime(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        
        if interval < TimeConstants.minute {
            return "now"
        } else if interval < TimeConstants.hour {
            let minutes = Int(interval / TimeConstants.minute)
            return "\(minutes)m"
        } else if interval < TimeConstants.day {
            let hours = Int(interval / TimeConstants.hour)
            return "\(hours)h"
        } else {
            let days = Int(interval / TimeConstants.day)
            return "\(days)d"
        }
    }
}

// MARK: - Hashtags View
struct HashtagsView: View {
    let hashtags: [String]
    
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 60), spacing: 8)], alignment: .leading, spacing: 6) {
            ForEach(hashtags, id: \.self) { hashtag in
                HashtagPill(hashtag: hashtag)
            }
        }
    }
}

struct HashtagPill: View {
    let hashtag: String
    
    var body: some View {
        Text("#\(hashtag)")
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.purple)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.purple.opacity(0.1))
                    .overlay(
                        Capsule()
                            .stroke(Color.purple.opacity(0.3), lineWidth: 0.5)
                    )
            )
    }
}

// MARK: - String Extension
extension String {
    var containsEmoji: Bool {
        for scalar in unicodeScalars {
            switch scalar.value {
            case 0x1F600...0x1F64F, // Emoticons
                 0x1F300...0x1F5FF, // Misc Symbols and Pictographs
                 0x1F680...0x1F6FF, // Transport and Map
                 0x1F700...0x1F77F, // Alchemical Symbols
                 0x1F780...0x1F7FF, // Geometric Shapes Extended
                 0x1F800...0x1F8FF, // Supplemental Arrows-C
                 0x2600...0x26FF,   // Misc symbols
                 0x2700...0x27BF,   // Dingbats
                 0xFE00...0xFE0F,   // Variation Selectors
                 0x1F900...0x1F9FF, // Supplemental Symbols and Pictographs
                 0x1FA00...0x1FA6F, // Chess Symbols
                 0x1FA70...0x1FAFF: // Symbols and Pictographs Extended-A
                return true
            default:
                continue
            }
        }
        return false
    }
}

// MARK: - Reply Recording View
struct ReplyRecordingView: View {
    let replyingTo: AudioEvent
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var nostrManager: NostrManager
    
    // Recording states
    @State private var audioRecorder: AVAudioRecorder?
    @State private var recordingTimer: Timer?
    @State private var recordingDuration: TimeInterval = 0
    @State private var isRecording = false
    @State private var recordingWaveform: [CGFloat] = []
    @State private var fullWaveform: [Double] = []
    @State private var showingRecordingUI = false
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.95)
                .ignoresSafeArea()
            
            if !showingRecordingUI {
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
                    
                    // Record button
                    RecordButton(
                        isRecording: $isRecording,
                        onStartRecording: startRecording,
                        onStopRecording: stopRecording
                    )
                    
                    Spacer()
                }
            } else {
                // Recording UI overlay
                RecordingOverlay(
                    duration: recordingDuration,
                    waveform: recordingWaveform,
                    onCancel: cancelRecording,
                    onComplete: completeRecording,
                    isUploading: false,
                    uploadedURL: nil,
                    onPreview: {},
                    onPublish: {},
                    isPlaying: false,
                    playbackProgress: 0,
                    playbackWaveformProgress: 0
                )
            }
        }
    }
    
    private func startRecording() {
        Task {
            let granted = await AVAudioApplication.requestRecordPermission()
            if granted {
                await MainActor.run {
                    setupRecording()
                }
            }
        }
    }
    
    private func setupRecording() {
        let audioSession = AVAudioSession.sharedInstance()
        
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.allowBluetooth, .defaultToSpeaker])
            try audioSession.setActive(true)
            
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let audioFilename = documentsPath.appendingPathComponent("reply_\(Date().timeIntervalSince1970).m4a")
            
            let settings = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            
            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()
            
            isRecording = true
            showingRecordingUI = true
            recordingDuration = 0
            fullWaveform = []
            
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                updateRecording()
            }
            
        } catch {
            print("Failed to start recording: \(error)")
        }
    }
    
    private func updateRecording() {
        guard let recorder = audioRecorder else { return }
        
        recorder.updateMeters()
        
        recordingDuration += 0.1
        
        // Use peak power for more responsive visualization
        let peakPower = recorder.peakPower(forChannel: 0)
        let clampedPower = max(-50, peakPower) // Clamp to -50 dB minimum
        let normalizedValue = pow(10, clampedPower / 20)
        
        recordingWaveform.append(CGFloat(normalizedValue))
        fullWaveform.append(Double(normalizedValue))
        
        if recordingWaveform.count > 50 {
            recordingWaveform.removeFirst()
        }
        
        if recordingDuration >= 60 {
            stopRecording()
        }
    }
    
    private func stopRecording() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        audioRecorder?.stop()
        isRecording = false
    }
    
    private func cancelRecording() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        audioRecorder?.stop()
        audioRecorder?.deleteRecording()
        audioRecorder = nil
        
        isRecording = false
        showingRecordingUI = false
        recordingWaveform = []
        fullWaveform = []
    }
    
    private func completeRecording() {
        guard let recorder = audioRecorder,
              let ndk = nostrManager.ndk else { return }
        
        let _ = recorder.url
        let finalDuration = recordingDuration
        
        let compressedWaveform = compressWaveform(fullWaveform, targetSamples: 50)
        
        Task {
            do {
                let uploadedURL = "https://example.com/audio/reply_\(Date().timeIntervalSince1970).webm"
                
                var imetaComponents = ["imeta"]
                imetaComponents.append("url \(uploadedURL)")
                imetaComponents.append("m audio/webm")
                imetaComponents.append("duration \(Int(finalDuration))")
                
                let waveformString = compressedWaveform
                    .map { String(format: "%.2f", $0) }
                    .joined(separator: " ")
                imetaComponents.append("waveform \(waveformString)")
                
                // Publish reply audio event
                _ = try await ndk.publish { builder in
                    builder
                        .kind(1222) // Audio event kind
                        .content(uploadedURL)
                        .tag(imetaComponents)
                        .tag(["e", replyingTo.id, "", "reply"]) // Reply to original event
                        .tag(["p", replyingTo.author.pubkey]) // Mention original author
                }
                
                await MainActor.run {
                    dismiss()
                }
                
            } catch {
                print("Failed to publish reply: \(error)")
                await MainActor.run {
                    showingRecordingUI = false
                }
            }
        }
    }
    
    private func compressWaveform(_ waveform: [Double], targetSamples: Int) -> [Double] {
        guard waveform.count > targetSamples else { return waveform }
        
        var compressed: [Double] = []
        let bucketSize = Double(waveform.count) / Double(targetSamples)
        
        for i in 0..<targetSamples {
            let startIndex = Int(Double(i) * bucketSize)
            let endIndex = min(Int(Double(i + 1) * bucketSize), waveform.count)
            
            if startIndex < endIndex {
                let bucketValues = waveform[startIndex..<endIndex]
                let average = bucketValues.reduce(0.0, +) / Double(bucketValues.count)
                compressed.append(average)
            }
        }
        
        return compressed
    }
}