import SwiftUI
import NDKSwift

struct ProfileView: View {
    let pubkey: String?
    @Environment(NDKAuthManager.self) var authManager
    @EnvironmentObject var ndkManager: NDKManager
    @Environment(\.dismiss) private var dismiss
    
    private var displayPubkey: String {
        pubkey ?? authManager.activeSession?.pubkey ?? ""
    }
    
    @State private var profile: NDKUserProfile?
    @State private var isLoading = true
    @State private var notes: [NDKEvent] = []
    @State private var followCount: Int?
    @State private var followerCount: Int?
    @State private var isFollowing = false
    @State private var showingQRCode = false
    @State private var notesDataSource: NDKDataSource<NDKEvent>?
    @State private var notesTask: Task<Void, Never>?
    @State private var profileTask: Task<Void, Never>?
    
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
            .navigationBarHidden(true)
            .overlay(alignment: .topTrailing) {
                closeButton
            }
        }
        .task {
            await loadProfile()
        }
        .onDisappear {
            Task {
                notesTask?.cancel()
            }
            profileTask?.cancel()
        }
        .sheet(isPresented: $showingQRCode) {
            if let pubkey = pubkey {
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
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
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
                    .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
            }
        }
    }
    
    private var profileInfoView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Name and verification
            HStack(alignment: .center, spacing: 8) {
                Text(displayName)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.primary)
                    .onAppear {
                        print("[ProfileView] Displaying name: \(displayName), profile: \(profile?.displayName ?? "nil")")
                    }
                
                if profile?.nip05 != nil {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.blue)
                }
            }
            
            // Username/NIP-05
            if let nip05 = profile?.nip05 {
                Text(nip05)
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            } else if let pubkey = pubkey {
                Text(shortenPubkey(pubkey))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
            
            // Bio
            if let about = profile?.about, !about.isEmpty {
                Text(about)
                    .font(.system(size: 16))
                    .foregroundColor(.primary)
                    .lineSpacing(4)
                    .padding(.top, 8)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            // Website
            if let website = profile?.website, let url = URL(string: website) {
                Link(destination: url) {
                    HStack(spacing: 6) {
                        Image(systemName: "link")
                            .font(.system(size: 14))
                        Text(cleanWebsiteURL(website))
                            .font(.system(size: 15))
                    }
                    .foregroundColor(.blue)
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 60)
    }
    
    private var statsAndActionsView: some View {
        VStack(spacing: 16) {
            // Stats
            HStack(spacing: 24) {
                statView(count: followCount, label: "Following")
                statView(count: followerCount, label: "Followers")
                statView(count: notes.count, label: "Notes")
                Spacer()
            }
            
            // Action buttons
            HStack(spacing: 12) {
                // Follow/Unfollow button
                Button(action: toggleFollow) {
                    HStack(spacing: 6) {
                        Image(systemName: isFollowing ? "person.badge.minus" : "person.badge.plus")
                            .font(.system(size: 16, weight: .medium))
                        Text(isFollowing ? "Unfollow" : "Follow")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(isFollowing ? .primary : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        isFollowing ? 
                        LinearGradient(
                            colors: [Color(.tertiarySystemFill)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ) : 
                        LinearGradient(
                            colors: [Color.blue, Color.blue.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(12)
                }
                
                // Message button
                Button(action: sendMessage) {
                    Image(systemName: "paperplane")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.primary)
                        .frame(width: 48, height: 48)
                        .background(Color(.tertiarySystemFill))
                        .cornerRadius(12)
                }
                
                // QR Code button
                Button(action: { showingQRCode = true }) {
                    Image(systemName: "qrcode")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.primary)
                        .frame(width: 48, height: 48)
                        .background(Color(.tertiarySystemFill))
                        .cornerRadius(12)
                }
            }
        }
    }
    
    private func statView(count: Int?, label: String) -> some View {
        VStack(spacing: 4) {
            Text(count.map { formatCount($0) } ?? "—")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.primary)
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
    }
    
    private var notesSection: some View {
        VStack(spacing: 0) {
            // Section header
            HStack {
                Text("Notes")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            
            if notes.isEmpty && !isLoading {
                emptyNotesView
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(notes, id: \.id) { event in
                        NoteRowView(event: event)
                        
                        if event.id != notes.last?.id {
                            Divider()
                                .padding(.leading, 20)
                        }
                    }
                }
            }
        }
    }
    
    private var emptyNotesView: some View {
        VStack(spacing: 12) {
            Image(systemName: "note.text")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))
            Text("No notes yet")
                .font(.system(size: 18))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
    
    private var closeButton: some View {
        Button(action: { dismiss() }) {
            ZStack {
                VisualEffectBlur(blurStyle: .systemThinMaterial)
                    .clipShape(Circle())
                
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .frame(width: 36, height: 36)
        }
        .padding(.top, 60)
        .padding(.trailing, 20)
    }
    
    // MARK: - Helper Methods
    
    private var displayName: String {
        if let displayName = profile?.displayName {
            return displayName
        } else if let name = profile?.name {
            return name
        } else if let pubkey = pubkey {
            return shortenPubkey(pubkey)
        } else {
            return "Unknown"
        }
    }
    
    private var avatarInitial: String {
        String(displayName.prefix(1)).uppercased()
    }
    
    private func shortenPubkey(_ pubkey: String) -> String {
        if pubkey.count > 16 {
            return String(pubkey.prefix(8)) + "..." + String(pubkey.suffix(8))
        }
        return pubkey
    }
    
    private func cleanWebsiteURL(_ url: String) -> String {
        url.replacingOccurrences(of: "https://", with: "")
           .replacingOccurrences(of: "http://", with: "")
           .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
    
    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
    
    // MARK: - Actions
    
    private func toggleFollow() {
        // Implementation for follow/unfollow
    }
    
    private func sendMessage() {
        // Implementation for sending message
    }
    
    private func loadProfile() async {
        guard let ndk = ndkManager.ndk else { return }
        
        // Use the observeProfile API for reactive profile updates
        profileTask = Task {
            let profileStream = await ndk.profileManager.observe(for: displayPubkey)
            
            for await profileUpdate in profileStream {
                await MainActor.run {
                    self.profile = profileUpdate
                    if let profile = profileUpdate {
                        print("[ProfileView] Profile updated for \(displayPubkey): \(profile.displayName ?? "unknown")")
                    } else {
                        print("[ProfileView] No profile available for \(displayPubkey)")
                    }
                }
            }
        }
        
        // Subscribe to notes
        let filter = NDKFilter(
            authors: [displayPubkey],
            kinds: [1],
            limit: 50
        )
        
        notesDataSource = ndk.observe(
            filter: filter,
            cachePolicy: .cacheWithNetwork
        )
        
        if let dataSource = notesDataSource {
            notesTask = Task {
                for await event in dataSource.events {
                    // Insert new note in sorted order
                    if !notes.contains(where: { $0.id == event.id }) {
                        notes.append(event)
                        notes.sort { $0.createdAt > $1.createdAt }
                    }
                }
            }
        }
        
        await MainActor.run {
            isLoading = false
        }
    }
}

struct NoteRowView: View {
    let event: NDKEvent
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(event.content)
                .font(.system(size: 16))
                .foregroundColor(.primary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            
            HStack(spacing: 16) {
                Text(formatTimestamp(event.createdAt))
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Engagement buttons
                HStack(spacing: 20) {
                    Button(action: {}) {
                        Image(systemName: "bubble.right")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    }
                    
                    Button(action: {}) {
                        Image(systemName: "arrow.2.squarepath")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    }
                    
                    Button(action: {}) {
                        Image(systemName: "heart")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .contentShape(Rectangle())
    }
    
    private func formatTimestamp(_ timestamp: Timestamp) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct QRCodeView: View {
    let pubkey: String
    let profile: NDKUserProfile?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Text(profile?.displayName ?? "Nostr Profile")
                    .font(.system(size: 24, weight: .bold))
                
                // QR Code would go here
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.systemGray6))
                    .frame(width: 280, height: 280)
                    .overlay(
                        Text("QR Code")
                            .foregroundColor(.secondary)
                    )
                
                Text("npub1...")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            .padding(.top, 40)
            .navigationTitle("Share Profile")
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

#Preview {
    ProfileView(pubkey: "test_pubkey")
        .environment(NDKAuthManager.shared)
        .environmentObject(NDKManager.shared)
}