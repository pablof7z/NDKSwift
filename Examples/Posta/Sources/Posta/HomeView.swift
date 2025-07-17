import SwiftUI
import NDKSwift

struct HomeView: View {
    @Environment(NDKAuthManager.self) var authManager
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @State private var profileCache: [String: NDKUserProfile] = [:]
    @State private var selectedProfile: String?
    
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
                        chatListView(manager: subscriptionManager)
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .sheet(item: $selectedProfile) { pubkey in
            ProfileView(pubkey: pubkey)
        }
        .onAppear {
            // SubscriptionManager is now passed via environment
        }
    }
    
    private var headerView: some View {
        ZStack {
            // Subtle background blur effect
            VisualEffectBlur(blurStyle: .systemUltraThinMaterial)
                .opacity(0.9)
            
            HStack(spacing: 16) {
                Text("Messages")
                    .font(.system(size: 34, weight: .bold, design: .default))
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Profile button
                Button(action: {
                    if let activeSession = authManager.activeSession {
                        selectedProfile = activeSession.pubkey
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(Color(.tertiarySystemFill))
                            .frame(width: 38, height: 38)
                        
                        Image(systemName: "person.circle")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .frame(height: 98)
        .overlay(
            Rectangle()
                .fill(Color(.separator).opacity(0.2))
                .frame(height: 0.5),
            alignment: .bottom
        )
    }
    
    private var loadingFollowsView: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(1.1)
                .tint(.accentColor)
            
            VStack(spacing: 8) {
                Text("Loading your network")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text("Fetching your follow list...")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.1)
                .tint(.accentColor)
            
            Text("Initializing...")
                .font(.system(size: 15))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color(.quaternarySystemFill))
                    .frame(width: 120, height: 120)
                
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 56))
                    .foregroundColor(.secondary.opacity(0.6))
                    .symbolRenderingMode(.hierarchical)
            }
            
            VStack(spacing: 8) {
                Text("No messages yet")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text("Messages from people you follow will appear here")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func chatListView(manager: SubscriptionManager) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(manager.notes, id: \.id) { event in
                    ChatRowView(
                        event: event,
                        profile: profileCache[event.pubkey],
                        onProfileLoad: { profile in
                            profileCache[event.pubkey] = profile
                        },
                        onTap: {
                            selectedProfile = event.pubkey
                        }
                    )
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    
                    if event.id != manager.notes.last?.id {
                        Divider()
                            .padding(.leading, 76)
                    }
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: manager.notes.count)
        }
        .scrollIndicators(.hidden)
    }
}

struct ChatRowView: View {
    let event: NDKEvent
    let profile: NDKUserProfile?
    let onProfileLoad: (NDKUserProfile) -> Void
    let onTap: () -> Void
    
    @State private var isPressed = false
    @State private var profileTask: Task<Void, Never>?
    @EnvironmentObject var ndkManager: NDKManager
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Avatar section
            ZStack {
                if let avatarURL = profile?.picture, let url = URL(string: avatarURL) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Circle()
                            .fill(Color(.tertiarySystemFill))
                            .overlay(
                                Text(avatarInitial)
                                    .font(.system(size: 22, weight: .medium))
                                    .foregroundColor(.secondary)
                            )
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color(.tertiarySystemFill))
                        .frame(width: 56, height: 56)
                        .overlay(
                            Text(avatarInitial)
                                .font(.system(size: 22, weight: .medium))
                                .foregroundColor(.secondary)
                        )
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 12)
            
            // Content section
            VStack(alignment: .leading, spacing: 3) {
                // Header row
                HStack(alignment: .firstTextBaseline) {
                    Text(displayName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    HStack(spacing: 4) {
                        Text(formatTimestamp(event.createdAt))
                            .font(.system(size: 15))
                            .foregroundColor(Color.secondary.opacity(0.6))
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color.secondary.opacity(0.3))
                    }
                }
                
                // Message preview
                Text(cleanContent(event.content))
                    .font(.system(size: 15))
                    .lineSpacing(2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(.trailing, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .background(
            Color(.systemBackground)
                .brightness(isPressed ? -0.02 : 0)
        )
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isPressed = false
                onTap()
            }
        }
        .task {
            if profile == nil, let ndk = ndkManager.ndk {
                profileTask = Task {
                    let profileStream = await ndk.observeProfile(for: event.pubkey)
                    
                    for await profileUpdate in profileStream {
                        if let profile = profileUpdate {
                            await MainActor.run {
                                onProfileLoad(profile)
                            }
                            // We only need the first valid profile for the list view
                            break
                        }
                    }
                }
            }
        }
        .onDisappear {
            profileTask?.cancel()
        }
    }
    
    private var displayName: String {
        if let name = profile?.displayName ?? profile?.name {
            return name
        }
        return shortenPubkey(event.pubkey)
    }
    
    private var avatarInitial: String {
        let name = displayName
        return String(name.prefix(1)).uppercased()
    }
    
    private func shortenPubkey(_ pubkey: String) -> String {
        if pubkey.count > 16 {
            return String(pubkey.prefix(8)) + "..." + String(pubkey.suffix(8))
        }
        return pubkey
    }
    
    private func cleanContent(_ content: String) -> String {
        // Remove extra whitespace and newlines for preview
        return content
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func formatTimestamp(_ timestamp: Timestamp) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let now = Date()
        let calendar = Calendar.current
        
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if let days = calendar.dateComponents([.day], from: date, to: now).day, days < 7 {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            return formatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            return formatter.string(from: date)
        }
    }
}


extension String: @retroactive Identifiable {
    public var id: String { self }
}

#Preview {
    HomeView()
        .environment(NDKAuthManager.shared)
        .environmentObject(SubscriptionManager())
}