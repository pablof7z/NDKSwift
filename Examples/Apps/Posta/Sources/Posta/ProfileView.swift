import SwiftUI
import NDKSwift

struct ProfileView: View {
    let pubkey: String?
    @Environment(NDKAuthManager.self) var authManager
    @Environment(NDKManager.self) var ndkManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var profile: NDKUserProfile?
    @State private var notes: [NDKEvent] = []
    @State private var isLoadingProfile = false
    @State private var isLoadingNotes = false
    @State private var profileError: Error?
    @State private var notesError: Error?
    @State private var followCount: Int?
    @State private var followerCount: Int?
    @State private var isFollowing = false
    @State private var showingQRCode = false
    @State private var selectedTab = 0
    @State private var showContent = false
    @State private var showingLogoutConfirmation = false
    @State private var isLoggingOut = false
    
    private var displayPubkey: String {
        pubkey ?? authManager.activeSession?.pubkey ?? ""
    }
    
    private var isOwnProfile: Bool {
        displayPubkey == authManager.activeSession?.pubkey
    }
    
    init(pubkey: String?) {
        self.pubkey = pubkey
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Animated gradient background
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(.systemBackground),
                        Color.purple.opacity(0.03),
                        Color(.systemBackground)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                ScrollView {
                        VStack(spacing: 0) {
                            // Header with banner and avatar
                            profileHeaderView
                            
                            // Profile info section
                            profileInfoView
                                .padding(.horizontal, 20)
                                .padding(.top, -30)
                            
                            // Stats and action buttons
                            statsAndActionsView
                                .padding(.horizontal, 20)
                                .padding(.top, 20)
                            
                            // Tab selector
                            tabSelector
                                .padding(.top, 24)
                            
                            // Content based on selected tab
                            switch selectedTab {
                            case 0:
                                notesSection
                                    .padding(.top, 8)
                            case 1:
                                repliesSection
                                    .padding(.top, 8)
                            case 2:
                                mediaSection
                                    .padding(.top, 8)
                            default:
                                EmptyView()
                            }
                        }
                    }
                    .ignoresSafeArea(edges: .top)
                
                // Error overlay
                if let error = profileError ?? notesError {
                    VStack {
                        Spacer()
                        ErrorBanner(error: error)
                            .padding()
                    }
                }
            }
            .navigationBarHidden(true)
            .overlay(alignment: .topTrailing) {
                closeButton
            }
        }
        .task {
            await loadProfile()
            await loadNotes()
            await loadStats()
        }
        .sheet(isPresented: $showingQRCode) {
            if let pubkey = displayPubkey.isEmpty ? nil : displayPubkey {
                QRCodeView(pubkey: pubkey, profile: profile)
            }
        }
        .alert("Log Out", isPresented: $showingLogoutConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Log Out", role: .destructive) {
                Task {
                    await performLogout()
                }
            }
        } message: {
            Text("Are you sure you want to log out? This will remove your session from this device.")
        }
    }
    
    private var profileHeaderView: some View {
        ZStack(alignment: .bottom) {
            // Banner with parallax effect
            GeometryReader { geometry in
                if let banner = profile?.banner, let url = URL(string: banner) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        shimmeringBannerPlaceholder
                    }
                    .frame(width: geometry.size.width, height: 250)
                    .clipped()
                    .overlay(bannerOverlay)
                } else {
                    defaultBanner
                        .frame(height: 250)
                }
            }
            .frame(height: 200)
            .clipped()
            
            // Avatar with animation
            HStack {
                avatarView
                    .padding(.leading, 20)
                    .padding(.bottom, -50)
                    .scaleEffect(showContent ? 1 : 0.8)
                    .opacity(showContent ? 1 : 0)
                Spacer()
            }
        }
        .frame(height: 200)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.2)) {
                showContent = true
            }
        }
    }
    
    private var shimmeringBannerPlaceholder: some View {
        Rectangle()
            .fill(Color(.systemGray5))
            .postaShimmer()
    }
    
    private var defaultBanner: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.purple.opacity(0.3),
                    Color.purple.opacity(0.1)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // Animated pattern
            WaveShape(phase: 0)
                .fill(Color.purple.opacity(0.1))
                .offset(y: 50)
        }
    }
    
    private var bannerOverlay: some View {
        LinearGradient(
            colors: [
                Color.black.opacity(0),
                Color.black.opacity(0.2),
                Color.black.opacity(0.4)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    private var avatarView: some View {
        EnhancedAvatarView(
            url: profile?.picture.flatMap { URL(string: $0) },
            size: 120,
            fallbackText: avatarInitial,
            showOnlineIndicator: false
        )
        .overlay(
            Circle()
                .stroke(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.purple.opacity(0.5),
                            Color.purple.opacity(0.2)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 3
                )
        )
        .shadow(color: Color.purple.opacity(0.2), radius: 12, x: 0, y: 4)
    }
    
    private var avatarInitial: String {
        let name = profile?.displayName ?? profile?.name ?? "?"
        return String(name.prefix(1)).uppercased()
    }
    
    private var profileInfoView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile?.displayName ?? profile?.name ?? "Unknown")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    if let nip05 = profile?.nip05 {
                        Label(nip05, systemImage: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            .padding(.top, 60)
            
            if let about = profile?.about, !about.isEmpty {
                Text(about)
                    .font(.body)
                    .foregroundColor(.primary.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
        }
    }
    
    private var statsAndActionsView: some View {
        VStack(spacing: 16) {
            HStack(spacing: 40) {
                StatView(count: notes.count, label: "Posts")
                StatView(count: followCount ?? 0, label: "Following")
                StatView(count: followerCount ?? 0, label: "Followers")
                Spacer()
            }
            
            HStack(spacing: 12) {
                if displayPubkey != authManager.activeSession?.pubkey {
                    Button(action: {
                        HapticFeedback.notification(.success)
                        // Toggle follow
                    }) {
                        HStack {
                            Image(systemName: isFollowing ? "person.badge.minus" : "person.badge.plus")
                            Text(isFollowing ? "Unfollow" : "Follow")
                        }
                    }
                    .buttonStyle(PostaPrimaryButtonStyle(isEnabled: !isFollowing))
                } else {
                    // Show settings and logout for own profile
                    NavigationLink(destination: SettingsView()) {
                        HStack {
                            Image(systemName: "gearshape")
                            Text("Settings")
                        }
                    }
                    .buttonStyle(PostaPrimaryButtonStyle(isEnabled: true))
                    
                    Button(action: {
                        showingLogoutConfirmation = true
                        HapticFeedback.impact(.light)
                    }) {
                        HStack {
                            if isLoggingOut {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                                    .scaleEffect(0.8)
                                    .tint(.white)
                            } else {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                            }
                            Text(isLoggingOut ? "Logging out..." : "Log Out")
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.red, Color.red.opacity(0.8)]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(
                        color: Color.red.opacity(0.3),
                        radius: 10,
                        x: 0,
                        y: 4
                    )
                    .disabled(isLoggingOut)
                }
                
                Button(action: {
                    showingQRCode = true
                    HapticFeedback.impact(.light)
                }) {
                    Image(systemName: "qrcode")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)
                        .frame(width: 44, height: 44)
                        .background(Color(.tertiarySystemFill))
                        .cornerRadius(10)
                }
                .buttonStyle(HapticButtonStyle())
            }
        }
    }
    
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Posts")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.horizontal, 20)
                
                Spacer()
                
                if isLoadingNotes {
                    ProgressView()
                        .scaleEffect(0.8)
                        .padding(.trailing, 20)
                }
            }
            .padding(.bottom, 16)
            
            if notes.isEmpty && !isLoadingNotes {
                VStack(spacing: 12) {
                    Image(systemName: "note.text")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No posts yet")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(notes, id: \.id) { note in
                        NoteRowView(note: note, profile: profile)
                        
                        if note.id != notes.last?.id {
                            Divider()
                                .padding(.leading, 20)
                        }
                    }
                }
            }
        }
    }
    
    private var closeButton: some View {
        Button(action: {
            HapticFeedback.impact(.light)
            dismiss()
        }) {
            ZStack {
                VisualEffectBlur(blurStyle: .systemThinMaterial)
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())
                
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
            }
        }
        .padding()
    }
    
    private var tabSelector: some View {
        HStack(spacing: 0) {
            TabButton(title: "Posts", icon: "note.text", isSelected: selectedTab == 0) {
                selectedTab = 0
                HapticFeedback.selection()
            }
            
            TabButton(title: "Replies", icon: "bubble.left", isSelected: selectedTab == 1) {
                selectedTab = 1
                HapticFeedback.selection()
            }
            
            TabButton(title: "Media", icon: "photo", isSelected: selectedTab == 2) {
                selectedTab = 2
                HapticFeedback.selection()
            }
        }
        .padding(.horizontal, 20)
    }
    
    private var repliesSection: some View {
        VStack {
            Text("Replies")
                .font(.title3)
                .padding()
            // TODO: Implement replies
        }
    }
    
    private var mediaSection: some View {
        VStack {
            Text("Media")
                .font(.title3)
                .padding()
            // TODO: Implement media grid
        }
    }
    
    private func loadStats() async {
        guard let ndk = ndkManager.ndk else { return }
        
        // Load follow count
        let followFilter = NDKFilter(
            authors: [displayPubkey],
            kinds: [EventKind.contacts],
            limit: 1
        )
        
        let dataSource = ndk.observe(filter: followFilter, maxAge: 3600)
        
        for await event in dataSource.events {
            let follows = event.tags.filter { $0.count >= 1 && $0[0] == "p" }.count
            await MainActor.run {
                followCount = follows
            }
            break // Only need the first/latest contact list
        }
        
        // Note: Follower count would require scanning all contact lists
        // which is expensive. This is typically done with a specialized relay.
    }
    
    private func loadProfile() async {
        guard let ndk = ndkManager.ndk else { return }
        
        isLoadingProfile = true
        profileError = nil
        
        let filter = NDKFilter(
            authors: [displayPubkey],
            kinds: [0],
            limit: 1
        )
        
        let dataSource = ndk.observe(filter: filter, maxAge: 3600) // Cache for 1 hour
        
        // Wait for first event
        for await event in dataSource.events {
            if let profileData = event.content.data(using: .utf8) {
                profile = JSONCoding.safeDecode(NDKUserProfile.self, from: profileData)
                isLoadingProfile = false
                break // Only need the first/latest profile
            }
        }
        
        isLoadingProfile = false
    }
    
    private func loadNotes() async {
        guard let ndk = ndkManager.ndk else { return }
        
        isLoadingNotes = true
        notesError = nil
        
        let filter = NDKFilter(
            authors: [displayPubkey],
            kinds: [EventKind.textNote],
            limit: 50
        )
        
        let dataSource = ndk.observe(filter: filter, maxAge: 300) // Cache for 5 minutes
        
        // Collect initial batch of notes
        var collectedNotes: [NDKEvent] = []
        for await event in dataSource.events {
            collectedNotes.append(event)
            // Wait for a moment to collect initial batch
            if collectedNotes.count >= 20 {
                break
            }
        }
        
        notes = collectedNotes.sorted(by: { $0.createdAt > $1.createdAt })
        isLoadingNotes = false
    }
    
    private func performLogout() async {
        isLoggingOut = true
        
        // Clear cache if available
        if let cache = ndkManager.ndk?.cache {
            try? await cache.clear()
        }
        
        // CRITICAL: Delete all sessions from keychain to prevent resurrection on app restart
        // This follows section 2.1 of NDKSWIFT-EXPERT-PROMPT.md
        for session in authManager.availableSessions {
            try? await authManager.deleteSession(session)
        }
        
        // Clear memory state
        await MainActor.run {
            authManager.logout()
            isLoggingOut = false
            dismiss()
        }
    }
}

struct StatView: View {
    let count: Int
    let label: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.system(size: 20, weight: .semibold))
            
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct NoteRowView: View {
    let note: NDKEvent
    let profile: NDKUserProfile?
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Small avatar
            if let picture = profile?.picture, let url = URL(string: picture) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle()
                        .fill(Color(.tertiarySystemFill))
                }
                .frame(width: 40, height: 40)
                .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color(.tertiarySystemFill))
                    .frame(width: 40, height: 40)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(profile?.displayName ?? profile?.name ?? "Unknown")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Text(note.createdAt.formatted)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text(note.content)
                    .font(.body)
                    .foregroundColor(.primary.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

struct QRCodeView: View {
    let pubkey: String
    let profile: NDKUserProfile?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text(profile?.displayName ?? profile?.name ?? "User")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                // QR Code would go here
                Image(systemName: "qrcode")
                    .font(.system(size: 200))
                    .foregroundColor(.primary)
                    .padding(40)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(20)
                
                Text("npub: \(String(pubkey.prefix(16)))...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospaced()
            }
            .padding()
            .navigationTitle("QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}