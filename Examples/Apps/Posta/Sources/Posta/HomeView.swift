import SwiftUI
import NDKSwift

struct HomeView: View {
    @Environment(NDKAuthManager.self) var authManager
    @Environment(SubscriptionManager.self) var subscriptionManager
    @Environment(NDKManager.self) var ndkManager
    @State private var selectedProfile: String?
    @State private var selectedThread: NDKEvent?
    @State private var replyTracker: ReplyTracker?
    
    var body: some View {
        NavigationView {
            ZStack {
                // Sophisticated gradient background
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: Color(.systemBackground), location: 0),
                        .init(color: Color(.systemBackground).opacity(0.97), location: 0.1),
                        .init(color: Color(.secondarySystemBackground).opacity(0.4), location: 1)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Elegant header
                    headerView
                    
                    // Main content
                    if subscriptionManager.isLoadingFollows {
                        loadingFollowsView
                    } else if subscriptionManager.notes.isEmpty && !subscriptionManager.isLoadingNotes {
                        emptyStateView
                    } else {
                        chatListView
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
        .onAppear {
            // Initialize reply tracker when NDK is available
            if let ndk = ndkManager.ndk, replyTracker == nil {
                replyTracker = ReplyTracker(ndk: ndk, following: subscriptionManager.latestFollowList)
            }
        }
        .onChange(of: subscriptionManager.latestFollowList) { _, newFollows in
            // Update reply tracker when follows change
            replyTracker?.updateFollowing(newFollows)
        }
        .onDisappear {
            // Clean up all reply tracking when view disappears
            replyTracker?.stopAllTracking()
        }
    }
    
    private var headerView: some View {
        ZStack {
            // Subtle background blur effect
            VisualEffectBlur(blurStyle: .systemUltraThinMaterial)
                .opacity(0.8)
            
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text("Messages")
                        .font(.system(size: 28, weight: .semibold, design: .default))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    // Sync button
                    Button(action: {
                        Task {
                            await subscriptionManager.triggerSync()
                        }
                    }) {
                        ZStack {
                            Circle()
                                .fill(Color(.quaternarySystemFill))
                                .frame(width: 36, height: 36)
                            
                            if subscriptionManager.isSyncing {
                                ProgressView()
                                    .scaleEffect(0.65)
                                    .tint(.secondary)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .disabled(subscriptionManager.isSyncing)
                    .opacity(subscriptionManager.isSyncing ? 1 : 0.9)
                    .scaleEffect(subscriptionManager.isSyncing ? 1 : 1)
                    .animation(.easeInOut(duration: 0.15), value: subscriptionManager.isSyncing)
                    
                    // Profile button
                    Button(action: {
                        if let activeSession = authManager.activeSession {
                            selectedProfile = activeSession.pubkey
                        }
                    }) {
                        ZStack {
                            Circle()
                                .fill(Color(.quaternarySystemFill))
                                .frame(width: 36, height: 36)
                            
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 18, weight: .regular))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 10)
                
                // Connection status
                if let error = subscriptionManager.error {
                    ErrorBanner(error: error)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 6)
                }
                
                // Sync status
                if !subscriptionManager.syncStatus.isEmpty {
                    Text(subscriptionManager.syncStatus)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 6)
                }
            }
        }
        .frame(height: subscriptionManager.error != nil ? 90 : 70)
        .shadow(color: Color.black.opacity(0.03), radius: 3, x: 0, y: 1)
    }
    
    private var loadingFollowsView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.2)
            
            Text("Loading your follows...")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 60))
                .foregroundColor(.secondary.opacity(0.5))
            
            Text("No messages yet")
                .font(.title3)
                .fontWeight(.medium)
            
            Text("Messages from people you follow will appear here")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                                if subscriptionManager.newNotesCount > 0 {
                                    subscriptionManager.resetNewNotesCount()
                                }
                            }
                        
                        ForEach(subscriptionManager.notes, id: \.id) { event in
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
                            
                            if event.id != subscriptionManager.notes.last?.id {
                                Divider()
                                    .padding(.leading, 72)
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
                
                // New notes indicator
                if subscriptionManager.newNotesCount > 0 {
                    Button(action: {
                        // Scroll to top and reset counter
                        withAnimation {
                            proxy.scrollTo("top", anchor: .top)
                        }
                        subscriptionManager.resetNewNotesCount()
                    }) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .medium))
                        
                        Text("\(subscriptionManager.newNotesCount) new \(subscriptionManager.newNotesCount == 1 ? "message" : "messages")")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(Color.accentColor)
                            .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
                    )
                }
                .padding(.top, 8)
                .transition(.asymmetric(
                    insertion: .scale.combined(with: .opacity),
                    removal: .scale.combined(with: .opacity)
                ))
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: subscriptionManager.newNotesCount)
                }
            }
        }
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
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Avatar section
            Button(action: onAvatarTap) {
                ZStack {
                    if let avatarURL = profile?.picture, let url = URL(string: avatarURL) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Circle()
                                .fill(Color(.tertiarySystemFill))
                        }
                        .frame(width: 48, height: 48)
                        .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(Color(.tertiarySystemFill))
                            .frame(width: 48, height: 48)
                            .overlay(
                                Text(String(profile?.name?.prefix(1) ?? "?").uppercased())
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundColor(.secondary)
                            )
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.leading, 16)
            .padding(.trailing, 12)
            
            // Content section
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(profile?.displayName ?? profile?.name ?? "Unknown")
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                        .layoutPriority(1)
                    
                    Text(event.createdAt.formatted)
                        .font(.caption)
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
            .padding(.trailing, 16)
            .padding(.vertical, 12)
        }
        .background(
            Color.primary.opacity(isPressed ? 0.05 : 0)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .scaleEffect(isPressed ? 0.98 : 1)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        .onLongPressGesture(
            minimumDuration: 0,
            maximumDistance: .infinity,
            pressing: { pressing in
                isPressed = pressing
            },
            perform: { }
        )
        .onAppear {
            // Start observing profile if we don't have it yet
            if profile == nil, let ndk = ndkManager.ndk {
                profileTask = Task {
                    let profileStream = await ndk.profileManager.observe(for: event.pubkey)
                    
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

