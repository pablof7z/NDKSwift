import SwiftUI
import NDKSwift

struct HomeView: View {
    @Environment(NDKAuthManager.self) var authManager
    @Environment(SubscriptionManager.self) var subscriptionManager
    @Environment(NDKManager.self) var ndkManager
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
                        chatListView
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .sheet(item: $selectedProfile) { pubkey in
            ProfileView(pubkey: pubkey)
        }
    }
    
    private var headerView: some View {
        ZStack {
            // Subtle background blur effect
            VisualEffectBlur(blurStyle: .systemUltraThinMaterial)
                .opacity(0.9)
            
            VStack(spacing: 0) {
                HStack(spacing: 16) {
                    Text("Messages")
                        .font(.system(size: 34, weight: .bold, design: .default))
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
                                .fill(Color(.tertiarySystemFill))
                                .frame(width: 38, height: 38)
                            
                            if subscriptionManager.isSyncing {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .tint(.secondary)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .disabled(subscriptionManager.isSyncing)
                    
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
                .padding(.top, 56)
                .padding(.bottom, 12)
                
                // Connection status
                if let error = subscriptionManager.error {
                    ErrorBanner(error: error)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                }
                
                // Sync status
                if !subscriptionManager.syncStatus.isEmpty {
                    Text(subscriptionManager.syncStatus)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 8)
                }
            }
        }
        .frame(height: error != nil ? 140 : 120)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
        
        var error: Error? {
            subscriptionManager.error
        }
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
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(subscriptionManager.notes, id: \.id) { event in
                    ChatRowView(
                        event: event,
                        profile: subscriptionManager.profile(for: event.pubkey),
                        onTap: {
                            selectedProfile = event.pubkey
                        }
                    )
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    
                    if event.id != subscriptionManager.notes.last?.id {
                        Divider()
                            .padding(.leading, 76)
                    }
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: subscriptionManager.notes.count)
        }
        .scrollIndicators(.hidden)
    }
}

struct ChatRowView: View {
    let event: NDKEvent
    let profile: NDKUserProfile?
    let onTap: () -> Void
    
    @State private var isPressed = false
    
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
                    }
                    .frame(width: 52, height: 52)
                    .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color(.tertiarySystemFill))
                        .frame(width: 52, height: 52)
                        .overlay(
                            Text(String(profile?.name?.prefix(1) ?? "?").uppercased())
                                .font(.system(size: 22, weight: .medium))
                                .foregroundColor(.secondary)
                        )
                }
            }
            .padding(.leading, 20)
            .padding(.trailing, 12)
            
            // Content section
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(profile?.displayName ?? profile?.name ?? "Unknown")
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Text(event.createdAt.formatted)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text(event.content)
                    .font(.system(size: 15))
                    .lineLimit(2)
                    .foregroundColor(.primary.opacity(0.9))
            }
            .padding(.trailing, 20)
            .padding(.vertical, 16)
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
extension String: Identifiable {
    public var id: String { self }
}

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