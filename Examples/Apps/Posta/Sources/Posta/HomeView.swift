import SwiftUI
import NDKSwift

struct HomeView: View {
    @Environment(NDKAuthManager.self) var authManager
    @Environment(NDKManager.self) var ndkManager
    @State private var selectedProfile: String?
    @State private var selectedThread: NDKEvent?
    @State private var replyTracker: ReplyTracker?
    
    // Simplified state management
    @State private var notes: [NDKEvent] = []
    @State private var isSyncing: Bool = false
    @State private var syncStatus: String = ""
    @State private var error: Error?
    @State private var newNotesCount: Int = 0
    @State private var notesTask: Task<Void, Never>?
    
    var body: some View {
        NavigationView {
            ZStack {
                // Subtle gradient background
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: Color(.systemBackground), location: 0),
                        .init(color: Color(.systemBackground).opacity(0.98), location: 0.2),
                        .init(color: Color(.secondarySystemBackground).opacity(0.2), location: 1)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Elegant header
                    headerView
                    
                    // Main content
                    if notes.isEmpty {
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
            startNotesStream()
        }
        .onDisappear {
            notesTask?.cancel()
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
                        triggerSync()
                    }) {
                        ZStack {
                            Circle()
                                .fill(Color(.quaternarySystemFill))
                                .frame(width: 36, height: 36)
                            
                            if isSyncing {
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
                    .disabled(isSyncing)
                    .opacity(isSyncing ? 1 : 0.9)
                    .scaleEffect(isSyncing ? 1 : 1)
                    .animation(.easeInOut(duration: 0.15), value: isSyncing)
                    
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
                if let error = error {
                    ErrorBanner(error: error)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 6)
                }
                
                // Sync status
                if !syncStatus.isEmpty {
                    Text(syncStatus)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 6)
                }
            }
        }
        .frame(height: error != nil ? 90 : 70)
        .shadow(color: Color.black.opacity(0.03), radius: 3, x: 0, y: 1)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.4))
            
            Text("No messages yet")
                .font(.headline)
                .fontWeight(.medium)
            
            Text("Messages from people you follow will appear here")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
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
                                if newNotesCount > 0 {
                                    resetNewNotesCount()
                                }
                            }
                        
                        ForEach(notes, id: \.id) { event in
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
                            
                            if event.id != notes.last?.id {
                                Divider()
                                    .padding(.leading, 76)
                            }
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
    
    private func startNotesStream() {
        guard let ndk = ndkManager.ndk,
              let signer = ndk.signer else { return }
        
        notesTask?.cancel()
        notesTask = Task {
            do {
                // Start session with explicit configuration
                let config = NDKSessionConfiguration(
                    dataRequirements: [.followList, .muteList],
                    preloadStrategy: .progressive
                )
                let sessionData = try await ndk.startSession(signer: signer, config: config)
                
                // Initialize reply tracker
                await MainActor.run {
                    if replyTracker == nil {
                        replyTracker = ReplyTracker(ndk: ndk, following: sessionData.followList)
                    }
                }
                
                // Create reactive filter for notes from followed users
                let filter = ReactiveFilter(
                    dependencies: [.followList],
                    builder: { sessionData in
                        NDKFilter(
                            authors: Array(sessionData.followList),
                            kinds: [1],
                            limit: 100  // Add limit to prevent overwhelming the UI
                        )
                    }
                )
                
                // Use observe to get a stream of notes - this handles all the complexity
                let stream = ndk.observe(filter)
                
                var seenIds = Set<String>()
                var notesList: [NDKEvent] = []
                
                for await event in stream {
                    guard !Task.isCancelled else { break }
                    
                    if !seenIds.contains(event.id) {
                        seenIds.insert(event.id)
                        notesList.append(event)
                        
                        // Sort by timestamp descending
                        notesList.sort { $0.createdAt > $1.createdAt }
                        
                        await MainActor.run {
                            // Update new notes count if we have existing notes
                            if !notes.isEmpty && event.createdAt > (notes.first?.createdAt ?? 0) {
                                newNotesCount += 1
                            }
                            
                            notes = notesList
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.error = error
                }
            }
        }
    }
    
    private func triggerSync() {
        // Restart the notes stream to get fresh data
        isSyncing = true
        syncStatus = "Syncing..."
        
        startNotesStream()
        
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            await MainActor.run {
                isSyncing = false
                syncStatus = ""
            }
        }
    }
    
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
                                .fill(Color(.quaternarySystemFill))
                        }
                        .frame(width: 48, height: 48)
                        .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(Color(.quaternarySystemFill))
                            .frame(width: 48, height: 48)
                            .overlay(
                                Text(String(profile?.name?.prefix(1) ?? "?").uppercased())
                                    .font(.system(size: 18, weight: .medium))
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
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(profile?.displayName ?? profile?.name ?? "Unknown")
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                        .layoutPriority(1)
                    
                    Text(event.createdAt.formatted)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    
                    Spacer(minLength: 0)
                }
                
                RichTextInline(
                    content: event.content,
                    tags: event.tags,
                    currentUser: nil
                )
                .font(.system(size: 14))
                .lineLimit(2)
                .foregroundColor(.primary.opacity(0.85))
                
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
            .padding(.vertical, 10)
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

