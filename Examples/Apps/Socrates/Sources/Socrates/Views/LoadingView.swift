import SwiftUI
import NDKSwift

struct LoadingView: View {
    @EnvironmentObject var nostrManager: NostrManager
    @EnvironmentObject var appState: AppState
    
    @State private var logoScale: CGFloat = 0.8
    @State private var logoOpacity: Double = 0
    @State private var rippleScale: CGFloat = 0.5
    @State private var rippleOpacity: Double = 0.8
    @State private var particleOffset: CGFloat = 0
    @State private var progressBarWidth: CGFloat = 0
    @State private var messageOpacity: Double = 0
    @State private var showingStats = false
    
    // Stats
    @State private var followCount = 0
    @State private var syncedCount = 0
    
    var body: some View {
        ZStack {
            // Animated background particles
            ForEach(0..<20) { index in
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.purple.opacity(0.3),
                                Color.blue.opacity(0.1)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: CGFloat.random(in: 20...60))
                    .position(
                        x: CGFloat.random(in: 0...UIScreen.main.bounds.width),
                        y: CGFloat.random(in: 0...UIScreen.main.bounds.height)
                    )
                    .offset(y: particleOffset)
                    .blur(radius: 3)
                    .animation(
                        .easeInOut(duration: Double.random(in: 10...20))
                        .delay(Double(index) * 0.1)
                        .repeatForever(autoreverses: true),
                        value: particleOffset
                    )
            }
            
            VStack(spacing: 60) {
                Spacer()
                
                // Logo with ripple effect
                ZStack {
                    // Ripple circles
                    ForEach(0..<3) { index in
                        Circle()
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.purple.opacity(0.4),
                                        Color.purple.opacity(0)
                                    ]),
                                    startPoint: .center,
                                    endPoint: .trailing
                                ),
                                lineWidth: 2
                            )
                            .frame(width: 150 + CGFloat(index) * 50, height: 150 + CGFloat(index) * 50)
                            .scaleEffect(rippleScale)
                            .opacity(rippleOpacity - Double(index) * 0.3)
                            .animation(
                                .easeOut(duration: 2)
                                .delay(Double(index) * 0.3)
                                .repeatForever(autoreverses: false),
                                value: rippleScale
                            )
                    }
                    
                    // Main logo
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.purple,
                                        Color(red: 0.4, green: 0.1, blue: 0.8)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 120, height: 120)
                            .shadow(color: Color.purple.opacity(0.5), radius: 20, x: 0, y: 5)
                        
                        Image(systemName: "waveform.circle.fill")
                            .font(.system(size: 70))
                            .foregroundColor(.white)
                    }
                    .scaleEffect(logoScale)
                    .opacity(logoOpacity)
                }
                
                VStack(spacing: 30) {
                    // Loading message
                    VStack(spacing: 12) {
                        Text(appState.loadingMessage)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                            .opacity(messageOpacity)
                        
                        if showingStats {
                            HStack(spacing: 40) {
                                VStack(spacing: 4) {
                                    Text("\(followCount)")
                                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                                        .foregroundColor(.purple)
                                    Text("Following")
                                        .font(.system(size: 12))
                                        .foregroundColor(Color.white.opacity(0.6))
                                }
                                
                                VStack(spacing: 4) {
                                    Text("\(syncedCount)")
                                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                                        .foregroundColor(.blue)
                                    Text("Synced")
                                        .font(.system(size: 12))
                                        .foregroundColor(Color.white.opacity(0.6))
                                }
                            }
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    
                    // Progress bar
                    ZStack(alignment: .leading) {
                        // Background
                        Capsule()
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 250, height: 8)
                        
                        // Progress
                        Capsule()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.purple,
                                        Color.blue
                                    ]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: progressBarWidth, height: 8)
                            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: progressBarWidth)
                        
                        // Glow effect on progress
                        Capsule()
                            .fill(Color.purple.opacity(0.3))
                            .frame(width: progressBarWidth, height: 8)
                            .blur(radius: 4)
                    }
                    
                    // Progress percentage
                    Text("\(Int(appState.syncProgress * 100))%")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(Color.white.opacity(0.6))
                }
                
                Spacer()
            }
        }
        .onAppear {
            animateLoading()
            startSync()
        }
        .onChange(of: appState.syncProgress) { _, newValue in
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                progressBarWidth = 250 * newValue
            }
        }
    }
    
    private func animateLoading() {
        // Logo animation
        withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
            logoScale = 1
            logoOpacity = 1
        }
        
        // Message fade in
        withAnimation(.easeOut(duration: 0.8).delay(0.5)) {
            messageOpacity = 1
        }
        
        // Start ripple animation
        withAnimation(.easeOut(duration: 2).repeatForever(autoreverses: false)) {
            rippleScale = 1.5
            rippleOpacity = 0
        }
        
        // Particle animation
        withAnimation(.easeInOut(duration: 20).repeatForever(autoreverses: true)) {
            particleOffset = -100
        }
        
        // Show stats after delay
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(1)) {
            showingStats = true
        }
    }
    
    private func startSync() {
        Task {
            guard let ndk = nostrManager.ndk,
                  let session = nostrManager.session else { return }
            
            // Update current user
            await MainActor.run {
                appState.currentUser = ndk.getUser(session.pubkey)
            }
            
            // Fetch user's kind:3 (follow list)
            await MainActor.run {
                appState.loadingMessage = "Fetching your connections..."
            }
            
            let followFilter = NDKFilter(
                authors: [session.pubkey],
                kinds: [3],
                limit: 1
            )
            
            let dataSource = ndk.observe(filter: followFilter, maxAge: 300)
            if let followEvent = try? await dataSource.first() {
                let follows = extractFollows(from: followEvent)
                
                await MainActor.run {
                    appState.followLists[session.pubkey] = follows
                    followCount = follows.count
                    appState.loadingMessage = "Syncing \(follows.count) connections..."
                }
                
                // Start syncing follow lists with progress
                await syncFollowLists(for: Array(follows), ndk: ndk)
            }
            
            // Complete loading
            await MainActor.run {
                appState.isLoading = false
            }
        }
    }
    
    private func extractFollows(from event: NDKEvent) -> Set<String> {
        var follows = Set<String>()
        
        for tag in event.tags {
            if tag.count >= 2 && tag[0] == "p" {
                follows.insert(tag[1])
            }
        }
        
        return follows
    }
    
    private func syncFollowLists(for pubkeys: [String], ndk: NDK) async {
        let totalCount = pubkeys.count
        var processedCount = 0
        
        // Process in batches for efficiency
        let batchSize = 20
        
        for i in stride(from: 0, to: pubkeys.count, by: batchSize) {
            let end = min(i + batchSize, pubkeys.count)
            let batch = Array(pubkeys[i..<end])
            
            let filter = NDKFilter(
                authors: batch,
                kinds: [3],
                limit: batch.count
            )
            
            let events = await ndk.fetchEvents(filter)
            
            for event in events {
                let follows = extractFollows(from: event)
                await MainActor.run {
                    appState.followLists[event.pubkey] = follows
                    processedCount += 1
                    syncedCount = processedCount
                    appState.syncProgress = Double(processedCount) / Double(totalCount)
                    
                    // Calculate web of trust score
                    updateWebOfTrust(for: event.pubkey, follows: follows)
                }
            }
            
            // Check if we have enough data (50%)
            if Double(processedCount) / Double(totalCount) >= 0.5 {
                await MainActor.run {
                    appState.loadingMessage = "Almost ready..."
                }
                
                // Small delay for visual effect
                try? await Task.sleep(nanoseconds: 500_000_000)
                break
            }
        }
    }
    
    private func updateWebOfTrust(for pubkey: String, follows: Set<String>) {
        guard let userPubkey = nostrManager.session?.pubkey else { return }
        
        // Simple web of trust calculation
        // Direct follows = 1.0
        // Follows of follows = 0.5
        // Everyone else = 0.1
        
        if appState.followLists[userPubkey]?.contains(pubkey) == true {
            appState.webOfTrust[pubkey] = 1.0
        } else if !appState.followLists[userPubkey]?.intersection(follows).isEmpty {
            appState.webOfTrust[pubkey] = 0.5
        } else {
            appState.webOfTrust[pubkey] = 0.1
        }
    }
}