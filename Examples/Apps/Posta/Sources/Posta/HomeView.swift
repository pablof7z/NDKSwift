import SwiftUI
import NDKSwift

struct HomeView: View {
    @Environment(NDKAuthManager.self) var authManager
    @Environment(NDKManager.self) var ndkManager
    @State private var selectedProfile: String?
    @State private var selectedThread: NDKEvent?
    @State private var replyTracker: ReplyTracker?
    @State private var showingCompose = false
    
    // Data source for notes
    @State private var notesDataSource: SessionNotesDataSource?
    @State private var newNotesCount: Int = 0
    @State private var showContent = false
    
    var body: some View {
        NavigationView {
            ZStack {
                // Animated gradient background
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(.systemBackground),
                        Color.purple.opacity(0.02),
                        Color(.systemBackground)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Elegant header
                    headerView
                    
                    // Main content - always show UI immediately
                    if notesDataSource?.notes.isEmpty == true {
                        emptyStateView
                    } else {
                        chatListView
                    }
                }
                
                // Floating compose button
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        FloatingActionButton(icon: "square.and.pencil") {
                            showingCompose = true
                        }
                        .padding(.trailing, 20)
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .sheet(item: $selectedProfile) { pubkey in
            ProfileView(pubkey: pubkey)
        }
        .sheet(item: $selectedThread) { event in
            ThreadView(rootEvent: event)
        }
        .sheet(isPresented: $showingCompose) {
            ComposeView()
        }
        .onAppear {
            print("📦 [HomeView] onAppear called")
            print("📦 [HomeView] ndkManager.ndk = \(ndkManager.ndk != nil ? "Available" : "NIL")")
            
            // Always show content immediately - no loading states
            showContent = true
            
            if let ndk = ndkManager.ndk {
                print("📦 [HomeView] ndk.signer = \(ndk.signer != nil ? "Available" : "NIL")")
                // Create data source if not already created
                if notesDataSource == nil {
                    notesDataSource = SessionNotesDataSource(ndk: ndk)
                }
            }
        }
        .task {
            // Wait for data source to be created
            while notesDataSource == nil {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
            
            guard let dataSource = notesDataSource else { return }
            
            // Monitor session data changes
            for await _ in dataSource.$sessionData.values {
                if let sessionData = dataSource.sessionData, replyTracker == nil {
                    replyTracker = ReplyTracker(ndk: dataSource.ndk, following: sessionData.followList)
                    print("📝 [HomeView] Reply tracker initialized")
                }
            }
        }
        .onDisappear {
            replyTracker?.stopAllTracking()
        }
    }
    
    private var headerView: some View {
        ZStack {
            // Animated header background
            AnimatedHeaderBackground()
            
            // Subtle background blur effect
            VisualEffectBlur(blurStyle: .systemUltraThinMaterial)
                .opacity(0.8)
            
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    HStack(spacing: 12) {
                        PostaLogoView(size: 32, color: .purple)
                        
                        Text("Messages")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.primary,
                                        Color.primary.opacity(0.8)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    
                    Spacer()
                    
                    // Sync button with animation
                    Button(action: {
                        Task {
                            await notesDataSource?.refresh()
                        }
                    }) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color.purple.opacity(0.1),
                                            Color.purple.opacity(0.05)
                                        ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 40, height: 40)
                            
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.purple)
                                .rotationEffect(.degrees(notesDataSource?.isLoading == true ? 360 : 0))
                                .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: notesDataSource?.isLoading == true)
                        }
                    }
                    .disabled(notesDataSource?.isLoading == true)
                    .scaleEffect(notesDataSource?.isLoading == true ? 0.95 : 1)
                    .animation(.easeInOut(duration: 0.2), value: notesDataSource?.isLoading == true)
                    
                    // Profile button with gradient
                    Button(action: {
                        if let activeSession = authManager.activeSession {
                            selectedProfile = activeSession.pubkey
                        }
                    }) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color.purple.opacity(0.1),
                                            Color.purple.opacity(0.05)
                                        ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 40, height: 40)
                            
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 20, weight: .regular))
                                .foregroundColor(.purple)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 10)
                
                // Connection status - show inline without blocking
                if let error = notesDataSource?.error {
                    ErrorBanner(error: error)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 6)
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .move(edge: .top).combined(with: .opacity)
                        ))
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: error.localizedDescription)
                }
                
                // Sync status
                if notesDataSource?.hasEOSE == true {
                    Text("Synced")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 6)
                }
            }
        }
        .frame(height: notesDataSource?.error != nil ? 90 : 70)
        .shadow(color: Color.black.opacity(0.03), radius: 3, x: 0, y: 1)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.purple.opacity(0.1),
                                Color.purple.opacity(0.05)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                    .blur(radius: 20)
                
                Image(systemName: "envelope.open")
                    .font(.system(size: 56))
                    .foregroundStyle(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.purple,
                                Color.purple.opacity(0.7)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .symbolEffect(.bounce, value: true)
            }
            
            VStack(spacing: 12) {
                Text("No messages yet")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text("Messages from people you follow\nwill appear here")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(y: -40)
    }
    
    private var chatListView: some View {
        ZStack(alignment: .top) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // Invisible anchor for scrolling to top
                        Color.clear
                            .frame(height: 0)
                            .id("top")
                            .onAppear {
                                // User is viewing the top of the list
                                if newNotesCount > 0 {
                                    resetNewNotesCount()
                                }
                            }
                        
                        ForEach(Array((notesDataSource?.notes ?? []).enumerated()), id: \.element.id) { index, event in
                            ChatRowView(
                                event: event,
                                replyTracker: replyTracker,
                                onTap: {
                                    selectedThread = event
                                },
                                onAvatarTap: {
                                    selectedProfile = event.pubkey
                                }
                            )
                            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(Double(index) * 0.05), value: showContent)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                
                // New notes indicator
                if newNotesCount > 0 {
                    Button(action: {
                        // Scroll to top and reset counter
                        withAnimation {
                            proxy.scrollTo("top", anchor: .top)
                        }
                        resetNewNotesCount()
                    }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 12, weight: .semibold))
                        
                        Text("\(newNotesCount) new")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color.accentColor)
                            .shadow(color: Color.accentColor.opacity(0.3), radius: 6, x: 0, y: 3)
                    )
                }
                .padding(.top, 8)
                .transition(.asymmetric(
                    insertion: .scale.combined(with: .opacity),
                    removal: .scale.combined(with: .opacity)
                ))
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: newNotesCount)
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func resetNewNotesCount() {
        newNotesCount = 0
    }
}

struct ChatRowView: View {
    let event: NDKEvent
    let replyTracker: ReplyTracker?
    let onTap: () -> Void
    let onAvatarTap: () -> Void
    
    @Environment(NDKManager.self) var ndkManager
    @State private var profile: NDKUserProfile?
    @State private var isPressed = false
    @State private var profileTask: Task<Void, Never>?
    @State private var replyInfo: ReplyTracker.ReplyInfo?
    @State private var pollingTask: Task<Void, Never>?
    @State private var showContent = false
    
    var body: some View {
        ZStack {
            // Card background
            MessageCard(
                isPressed: isPressed,
                hasUnread: false
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            
            HStack(alignment: .top, spacing: 0) {
                // Avatar section
                Button(action: onAvatarTap) {
                    EnhancedAvatarView(
                        url: profile?.picture.flatMap { URL(string: $0) },
                        size: 52,
                        fallbackText: String(profile?.name?.prefix(1) ?? "?").uppercased(),
                        showOnlineIndicator: false
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.leading, 20)
                .padding(.trailing, 12)
            
                // Content section
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(profile?.displayName ?? profile?.name ?? "Unknown")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .layoutPriority(1)
                        
                        Text("·")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                        
                        Text(event.createdAt.formatted)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                        
                        Spacer(minLength: 0)
                    }
                    
                    RichTextInline(
                        content: event.content,
                        tags: event.tags,
                        currentUser: nil
                    )
                    .font(.system(size: 15))
                    .lineLimit(2)
                    .foregroundColor(.primary.opacity(0.9))
                
                // Reply info section
                if let info = replyInfo, (info.totalCount > 0 || !info.followingRepliers.isEmpty) {
                    HStack(spacing: 4) {
                        // Following repliers avatars
                        if !info.followingRepliers.isEmpty {
                            HStack(spacing: -8) {
                                ForEach(Array(info.followingRepliers.prefix(3).enumerated()), id: \.offset) { index, replierProfile in
                                    if let avatarURL = replierProfile.picture, let url = URL(string: avatarURL) {
                                        AsyncImage(url: url) { image in
                                            image
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                        } placeholder: {
                                            Circle()
                                                .fill(Color(.tertiarySystemFill))
                                        }
                                        .frame(width: 16, height: 16)
                                        .clipShape(Circle())
                                        .overlay(
                                            Circle()
                                                .stroke(Color(.systemBackground), lineWidth: 1)
                                        )
                                    }
                                }
                            }
                            
                            if info.followingRepliers.count > 3 {
                                Text("+\(info.followingRepliers.count - 3)")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        // Reply count badge
                        if info.totalCount > 0 {
                            HStack(spacing: 2) {
                                Image(systemName: "bubble.left")
                                    .font(.system(size: 10))
                                Text("\(info.totalCount)")
                                    .font(.system(size: 11))
                            }
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(.tertiarySystemFill))
                            .cornerRadius(10)
                        }
                    }
                    .padding(.top, 4)
                }
                }
                .padding(.trailing, 20)
                .padding(.vertical, 14)
            }
        }
        .contentShape(Rectangle())
        .opacity(showContent ? 1 : 0)
        .scaleEffect(showContent ? 1 : 0.95)
        .onTapGesture {
            onTap()
        }
        .scaleEffect(isPressed ? 0.97 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
        .onLongPressGesture(
            minimumDuration: 0,
            maximumDistance: .infinity,
            pressing: { pressing in
                isPressed = pressing
            },
            perform: { }
        )
        .onAppear {
            // Animate content appearance
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.05)) {
                showContent = true
            }
            
            // Start observing profile if we don't have it yet
            if profile == nil, let ndk = ndkManager.ndk {
                profileTask = Task {
                    let profileStream = await ndk.profileManager.observe(for: event.pubkey, maxAge: TimeConstants.hour)
                    
                    for await profileUpdate in profileStream {
                        if let profile = profileUpdate {
                            await MainActor.run {
                                self.profile = profile
                            }
                            // We only need the first valid profile for the list view
                            break
                        }
                    }
                }
            }
            
            // Start tracking replies
            replyTracker?.startTrackingReplies(for: event.id)
            
            // Check for cached reply info
            if let cachedInfo = replyTracker?.getReplyInfo(for: event.id) {
                replyInfo = cachedInfo
            }
            
            // Observe for updates
            if replyTracker != nil {
                pollingTask = Task { @MainActor in
                    // Poll for updates periodically
                    while !Task.isCancelled {
                        if let info = replyTracker?.getReplyInfo(for: event.id) {
                            replyInfo = info
                        }
                        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                    }
                }
            }
        }
        .onDisappear {
            profileTask?.cancel()
            pollingTask?.cancel()
            // Don't stop tracking immediately - let it persist for scrolling
        }
    }
}

struct ErrorBanner: View {
    let error: Error
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.caption)
            
            Text(error.localizedDescription)
                .font(.caption)
                .lineLimit(1)
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }
}

// Extension to make String identifiable for sheet
extension String: @retroactive Identifiable {
    public var id: String { self }
}

// Extension to make NDKEvent identifiable for sheet
extension NDKEvent: @retroactive Identifiable {}

// Extension for formatted timestamps
extension Timestamp {
    var formatted: String {
        let date = Date(timeIntervalSince1970: TimeInterval(self))
        let now = Date()
        let interval = now.timeIntervalSince(date)
        
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

