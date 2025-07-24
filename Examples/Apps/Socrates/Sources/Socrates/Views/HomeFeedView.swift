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
    @State private var selectedRelay: String? = nil
    @State private var showRelaySelector = false
    
    // Recording states
    @State private var audioRecorder: AVAudioRecorder?
    @State private var recordingTimer: Timer?
    @State private var recordingDuration: TimeInterval = 0
    @State private var showingRecordingUI = false
    @State private var recordingWaveform: [CGFloat] = []
    @State private var fullWaveform: [Double] = [] // Store full waveform for imeta
    
    var sortedEvents: [AudioEvent] {
        audioEvents.sorted { $0.sortScore > $1.sortScore }
    }
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Header
                HeaderView(selectedRelay: $selectedRelay, showRelaySelector: $showRelaySelector)
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
            
            // Relay selector modal
            if showRelaySelector {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        showRelaySelector = false
                    }
                
                RelaySelectorView(
                    selectedRelay: $selectedRelay,
                    isPresented: $showRelaySelector
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showRelaySelector)
        .onAppear {
            startStreamingAudioEvents()
        }
        .onChange(of: selectedRelay) { _, _ in
            // Restart streaming with new relay filter
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
        
        // Clear events when switching relays
        audioEvents.removeAll()
        
        // Create filter for audio events
        let filter = NDKFilter(
            kinds: [1222, 1244]
        )
        
        // If a specific relay is selected, use it; otherwise use all relays
        let relayUrls: Set<String>? = selectedRelay != nil ? [selectedRelay!] : nil
        
        // Stream audio events with cache-first approach
        // maxAge: 300 means show cached data up to 5 minutes old immediately
        let dataSource: NDKDataSource<NDKEvent>
        if let relayUrls = relayUrls {
            dataSource = ndk.observe(filter: filter, maxAge: 300, cachePolicy: .cacheWithNetwork, relays: relayUrls)
        } else {
            dataSource = ndk.observe(filter: filter, maxAge: 300, cachePolicy: .cacheWithNetwork)
        }
        
        // Start streaming task
        dataSourceTask = Task {
            for await event in dataSource.events {
                // Check if task was cancelled
                if Task.isCancelled { break }
                
                // Skip muted users if session data is available
                if let sessionData = ndk.sessionData, sessionData.isMuted(event.pubkey) {
                    continue
                }
                
                // Get WOT score from session data
                let wotScore: Double
                if let sessionData = ndk.sessionData {
                    let score = sessionData.webOfTrust[event.pubkey] ?? 0
                    // Normalize score (direct follows have Int.max)
                    wotScore = score == Int.max ? 1.0 : min(Double(score) / 10.0, 1.0)
                } else {
                    wotScore = 0.1
                }
                
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
        guard nostrManager.ndk != nil else { return }
        
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
            fullWaveform = [] // Reset waveform data
            
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
        
        // Store normalized amplitude value for imeta (0-1 range)
        fullWaveform.append(Double(normalizedValue))
        
        // Keep last 50 samples for UI display
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
        fullWaveform = []
    }
    
    private func completeRecording() {
        guard let recorder = audioRecorder,
              let ndk = nostrManager.ndk else { return }
        
        let _ = recorder.url
        let finalDuration = recordingDuration
        
        // Compress waveform to less than 100 values as recommended
        let compressedWaveform = compressWaveform(fullWaveform, targetSamples: 50)
        
        Task {
            do {
                // Generate placeholder URL for demo purposes
                // In production, this would upload to a file hosting service
                let uploadedURL = "https://example.com/audio/\(Date().timeIntervalSince1970).webm"
                
                // Create imeta tag with waveform and duration
                var imetaComponents = ["imeta"]
                imetaComponents.append("url \(uploadedURL)")
                imetaComponents.append("m audio/webm")
                imetaComponents.append("duration \(Int(finalDuration))")
                
                // Add waveform data as space-separated values
                let waveformString = compressedWaveform
                    .map { String(format: "%.2f", $0) }
                    .joined(separator: " ")
                imetaComponents.append("waveform \(waveformString)")
                
                // Publish audio event
                _ = try await ndk.publish { builder in
                    builder
                        .kind(1222) // Audio event kind
                        .content(uploadedURL)
                        .tag(imetaComponents)
                }
                
                await MainActor.run {
                    showingRecordingUI = false
                    recordingWaveform = []
                    fullWaveform = []
                    audioRecorder = nil
                }
                
            } catch {
                print("Failed to publish audio event: \(error)")
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
                // Take the average of values in this bucket
                let bucketValues = waveform[startIndex..<endIndex]
                let average = bucketValues.reduce(0.0, +) / Double(bucketValues.count)
                compressed.append(average)
            }
        }
        
        return compressed
    }
}

// MARK: - Header View
struct HeaderView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var nostrManager: NostrManager
    @Binding var selectedRelay: String?
    @Binding var showRelaySelector: Bool
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
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
                
                // Relay indicator
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    
                    Text(selectedRelay != nil ? formatRelayForDisplay(selectedRelay!) : "All relays")
                        .font(.system(size: 11))
                        .foregroundColor(Color.white.opacity(0.7))
                    
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9))
                        .foregroundColor(Color.white.opacity(0.5))
                }
            }
            .onTapGesture {
                showRelaySelector = true
            }
            
            Spacer()
            
            // Settings button
            NavigationLink(destination: SettingsView()) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 20))
                    .foregroundColor(Color.white.opacity(0.8))
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.1))
                    )
            }
        }
    }
    
    private func formatRelayForDisplay(_ url: String) -> String {
        var formatted = url
        if formatted.hasPrefix("wss://") {
            formatted = String(formatted.dropFirst(6))
        } else if formatted.hasPrefix("ws://") {
            formatted = String(formatted.dropFirst(5))
        }
        if formatted.hasSuffix("/") {
            formatted = String(formatted.dropLast())
        }
        // Truncate long URLs
        if formatted.count > 20 {
            return String(formatted.prefix(17)) + "..."
        }
        return formatted
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
