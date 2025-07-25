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
    
    private var displayPubkey: String {
        pubkey ?? authManager.activeSession?.pubkey ?? ""
    }
    
    init(pubkey: String?) {
        self.pubkey = pubkey
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Sophisticated gradient background
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: Color(.systemBackground), location: 0),
                        .init(color: Color(.systemBackground).opacity(0.97), location: 0.3),
                        .init(color: Color(.secondarySystemBackground).opacity(0.3), location: 1)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                if isLoadingProfile && profile == nil {
                    ProgressView("Loading profile...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
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
                            
                            // Notes section
                            notesSection
                                .padding(.top, 32)
                        }
                    }
                    .ignoresSafeArea(edges: .top)
                }
                
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
    }
    
    private var profileHeaderView: some View {
        ZStack(alignment: .bottom) {
            // Banner
            if let banner = profile?.banner, let url = URL(string: banner) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(LinearGradient(
                            colors: [Color(.systemGray5), Color(.systemGray6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                }
                .frame(height: 200)
                .clipped()
                .overlay(
                    LinearGradient(
                        colors: [Color.black.opacity(0), Color.black.opacity(0.3)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                )
            } else {
                Rectangle()
                    .fill(LinearGradient(
                        colors: [Color(.systemGray5), Color(.systemGray6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(height: 200)
            }
            
            // Avatar
            HStack {
                avatarView
                    .padding(.leading, 20)
                    .padding(.bottom, -50)
                Spacer()
            }
        }
        .frame(height: 200)
    }
    
    private var avatarView: some View {
        Group {
            if let picture = profile?.picture, let url = URL(string: picture) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle()
                        .fill(Color(.tertiarySystemFill))
                        .overlay(
                            Text(avatarInitial)
                                .font(.system(size: 48, weight: .medium))
                                .foregroundColor(.secondary)
                        )
                }
                .frame(width: 120, height: 120)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color(.systemBackground), lineWidth: 4)
                )
                .shadow(radius: 8)
            } else {
                Circle()
                    .fill(Color(.tertiarySystemFill))
                    .frame(width: 120, height: 120)
                    .overlay(
                        Text(avatarInitial)
                            .font(.system(size: 48, weight: .medium))
                            .foregroundColor(.secondary)
                    )
                    .overlay(
                        Circle()
                            .stroke(Color(.systemBackground), lineWidth: 4)
                    )
                    .shadow(radius: 8)
            }
        }
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
                        // Toggle follow
                    }) {
                        HStack {
                            Image(systemName: isFollowing ? "person.badge.minus" : "person.badge.plus")
                            Text(isFollowing ? "Unfollow" : "Follow")
                        }
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(isFollowing ? .primary : .white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(isFollowing ? Color(.tertiarySystemFill) : Color.accentColor)
                        .cornerRadius(10)
                    }
                }
                
                Button(action: {
                    showingQRCode = true
                }) {
                    Image(systemName: "qrcode")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)
                        .frame(width: 44, height: 44)
                        .background(Color(.tertiarySystemFill))
                        .cornerRadius(10)
                }
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
            dismiss()
        }) {
            Image(systemName: "xmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.secondary, Color(.tertiarySystemFill))
        }
        .padding()
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