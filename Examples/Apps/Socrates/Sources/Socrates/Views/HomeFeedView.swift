import SwiftUI
import NDKSwift
import AVFoundation

struct HomeFeedView: View {
    @EnvironmentObject var nostrManager: NostrManager
    @EnvironmentObject var appState: AppState
    
    @State private var audioEvents: [AudioEvent] = []
    @State private var showRecordingHint = true
    @State private var recordingScale: CGFloat = 1
    @State private var recordingOpacity: Double = 1
    @State private var dragOffset = CGSize.zero
    @State private var isDragging = false
    @State private var dataSourceTask: Task<Void, Never>?
    
    // Recording states
    @State private var audioRecorder: AVAudioRecorder?
    @State private var recordingTimer: Timer?
    @State private var recordingDuration: TimeInterval = 0
    @State private var showingRecordingUI = false
    @State private var recordingWaveform: [CGFloat] = []
    
    var sortedEvents: [AudioEvent] {
        audioEvents.sorted { $0.sortScore > $1.sortScore }
    }
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Header
                HeaderView()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                
                // Feed - Always show UI immediately, no loading states
                if audioEvents.isEmpty {
                    EmptyFeedView()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(sortedEvents) { audioEvent in
                                AudioEventCard(audioEvent: audioEvent)
                                    .transition(.asymmetric(
                                        insertion: .slide.combined(with: .opacity),
                                        removal: .scale(scale: 0.8).combined(with: .opacity)
                                    ))
                                
                                Divider()
                                    .background(Color.white.opacity(0.1))
                            }
                        }
                    }
                    .refreshable {
                        await refreshAudioEvents()
                    }
                }
            }
            
            // Recording UI overlay
            if showingRecordingUI {
                RecordingOverlay(
                    duration: recordingDuration,
                    waveform: recordingWaveform,
                    onCancel: cancelRecording,
                    onComplete: completeRecording
                )
                .transition(.opacity.combined(with: .scale))
            }
            
            // Floating record button
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    
                    RecordButton(
                        isRecording: $appState.isRecording,
                        onStartRecording: startRecording,
                        onStopRecording: stopRecording
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
        }
        .onAppear {
            startStreamingAudioEvents()
        }
        .onDisappear {
            dataSourceTask?.cancel()
        }
    }
    
    private func startStreamingAudioEvents() {
        guard let ndk = nostrManager.ndk else { return }
        
        // Cancel any existing task
        dataSourceTask?.cancel()
        
        // Create filter for audio events
        let filter = NDKFilter(
            kinds: [1222, 1244]
        )
        
        // Stream audio events with cache-first approach
        // maxAge: 300 means show cached data up to 5 minutes old immediately
        let dataSource = ndk.observe(filter: filter, maxAge: 300, cachePolicy: .cacheWithNetwork)
        
        // Start streaming task
        dataSourceTask = Task {
            for await event in dataSource.events {
                // Check if task was cancelled
                if Task.isCancelled { break }
                
                // Skip muted users if session data is available
                if let sessionData = ndk.sessionData, sessionData.isMuted(event.pubkey) {
                    continue
                }
                
                let wotScore = await appState.webOfTrust[event.pubkey] ?? 0.1
                if let audioEvent = AudioEvent.from(event: event, webOfTrustScore: wotScore) {
                    await MainActor.run {
                        // Add new event if it doesn't already exist
                        if !self.audioEvents.contains(where: { $0.id == audioEvent.id }) {
                            withAnimation(.easeOut(duration: 0.3)) {
                                self.audioEvents.append(audioEvent)
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func refreshAudioEvents() async {
        guard let ndk = nostrManager.ndk else { return }
        
        // Clear existing events for a fresh feed
        await MainActor.run {
            audioEvents.removeAll()
        }
        
        // Re-start the streaming with fresh data
        // This will fetch from network due to maxAge: 0 in the main stream
        startStreamingAudioEvents()
    }
    
    private func startRecording() {
        // Request microphone permission
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
            try audioSession.setCategory(.playAndRecord, mode: .default)
            try audioSession.setActive(true)
            
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let audioFilename = documentsPath.appendingPathComponent("voice_\(Date().timeIntervalSince1970).m4a")
            
            let settings = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            
            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()
            
            appState.isRecording = true
            appState.recordingStartTime = Date()
            showingRecordingUI = true
            recordingDuration = 0
            
            // Start timer for duration and waveform
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                updateRecording()
            }
            
        } catch {
            print("Failed to start recording: \(error)")
        }
    }
    
    private func updateRecording() {
        guard let recorder = audioRecorder,
              let startTime = appState.recordingStartTime else { return }
        
        recorder.updateMeters()
        
        recordingDuration = Date().timeIntervalSince(startTime)
        
        // Update waveform
        let normalizedValue = pow(10, recorder.averagePower(forChannel: 0) / 20)
        recordingWaveform.append(CGFloat(normalizedValue))
        
        // Keep last 50 samples
        if recordingWaveform.count > 50 {
            recordingWaveform.removeFirst()
        }
        
        // Auto-stop at 60 seconds
        if recordingDuration >= 60 {
            stopRecording()
        }
    }
    
    private func stopRecording() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        audioRecorder?.stop()
        appState.isRecording = false
        
        // Show completion UI
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            // Transition to publish state
        }
    }
    
    private func cancelRecording() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        audioRecorder?.stop()
        audioRecorder?.deleteRecording()
        audioRecorder = nil
        
        appState.isRecording = false
        showingRecordingUI = false
        recordingWaveform = []
    }
    
    private func completeRecording() {
        guard let recorder = audioRecorder else { return }
        
        let _ = recorder.url
        
        // TODO: Upload to file hosting service
        // TODO: Create and publish NDKEvent with kind 1222
        
        showingRecordingUI = false
        recordingWaveform = []
        
        // Show success feedback
    }
}

// MARK: - Header View
struct HeaderView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var nostrManager: NostrManager
    
    var body: some View {
        HStack {
            Text("SOCRATES")
                .font(.system(size: 24, weight: .black))
                .foregroundStyle(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.white,
                            Color.white.opacity(0.8)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            
            Spacer()
            
            // Profile button
            if let user = appState.currentUser {
                AsyncImage(url: nil) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
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
                            Text(String(user.pubkey.prefix(2)))
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                        )
                }
                .frame(width: 36, height: 36)
                .clipShape(Circle())
            }
        }
    }
}

// MARK: - Empty Feed View
struct EmptyFeedView: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "waveform.circle")
                .font(.system(size: 80))
                .foregroundStyle(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.purple.opacity(0.6),
                            Color.blue.opacity(0.4)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            VStack(spacing: 12) {
                Text("No voices yet")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white)
                
                Text("Be the first to share your wisdom")
                    .font(.system(size: 16))
                    .foregroundColor(Color.white.opacity(0.6))
            }
            
            Spacer()
        }
    }
}

// MARK: - Record Button
struct RecordButton: View {
    @Binding var isRecording: Bool
    let onStartRecording: () -> Void
    let onStopRecording: () -> Void
    
    @State private var pulseScale: CGFloat = 1
    @State private var pulseOpacity: Double = 0.5
    
    var body: some View {
        ZStack {
            // Pulse effect when recording
            if isRecording {
                Circle()
                    .fill(Color.red.opacity(0.3))
                    .frame(width: 80, height: 80)
                    .scaleEffect(pulseScale)
                    .opacity(pulseOpacity)
                    .animation(
                        .easeInOut(duration: 1)
                        .repeatForever(autoreverses: true),
                        value: pulseScale
                    )
            }
            
            // Main button
            Button(action: {
                if isRecording {
                    onStopRecording()
                } else {
                    onStartRecording()
                }
            }) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    isRecording ? Color.red : Color.purple,
                                    isRecording ? Color.red.opacity(0.8) : Color(red: 0.5, green: 0.1, blue: 0.9)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)
                        .shadow(color: isRecording ? Color.red.opacity(0.5) : Color.purple.opacity(0.5), 
                               radius: 15, x: 0, y: 5)
                    
                    Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                }
            }
            .scaleEffect(isRecording ? 1.1 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isRecording)
        }
        .onAppear {
            if isRecording {
                withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                    pulseScale = 1.3
                    pulseOpacity = 0
                }
            }
        }
        .onChange(of: isRecording) { _, newValue in
            if newValue {
                withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                    pulseScale = 1.3
                    pulseOpacity = 0
                }
            } else {
                pulseScale = 1
                pulseOpacity = 0.5
            }
        }
    }
}

// MARK: - Recording Overlay
struct RecordingOverlay: View {
    let duration: TimeInterval
    let waveform: [CGFloat]
    let onCancel: () -> Void
    let onComplete: () -> Void
    
    @State private var showingControls = false
    
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var body: some View {
        ZStack {
            // Background blur
            Color.black.opacity(0.8)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showingControls.toggle()
                    }
                }
            
            VStack(spacing: 40) {
                // Waveform visualization
                HStack(spacing: 2) {
                    ForEach(0..<waveform.count, id: \.self) { index in
                        Capsule()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.purple,
                                        Color.blue
                                    ]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 4, height: 20 + waveform[index] * 80)
                            .animation(.easeOut(duration: 0.1), value: waveform[index])
                    }
                }
                .frame(height: 100)
                
                // Duration
                Text(formattedDuration)
                    .font(.system(size: 48, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                
                // Controls
                if showingControls {
                    HStack(spacing: 40) {
                        Button(action: onCancel) {
                            VStack(spacing: 8) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 50))
                                    .foregroundColor(.red)
                                Text("Cancel")
                                    .font(.caption)
                                    .foregroundColor(.white)
                            }
                        }
                        
                        Button(action: onComplete) {
                            VStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 50))
                                    .foregroundColor(.green)
                                Text("Publish")
                                    .font(.caption)
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
    }
}
