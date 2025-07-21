import SwiftUI
import NDKSwift

// Helper views for accessing async user profile properties

struct UserDisplayName: View {
    let pubkey: String
    @Environment(NostrManager.self) private var nostrManager
    @State private var profile: NDKUserProfile?
    
    init(user: NDKUser) {
        self.pubkey = user.pubkey
    }
    
    init(pubkey: String) {
        self.pubkey = pubkey
    }
    
    var body: some View {
        Text(displayName)
            .task(id: pubkey) {
                await loadProfile()
            }
    }
    
    private var displayName: String {
        // First check if profile is in contacts metadata
        if let profileDataSource = nostrManager.contactsMetadataDataSource,
           let cachedProfile = profileDataSource.profile(for: pubkey) {
            return cachedProfile.displayName ?? cachedProfile.name ?? "Nostr User"
        }
        
        // Otherwise use loaded profile
        return profile?.displayName ?? profile?.name ?? "Nostr User"
    }
    
    private func loadProfile() async {
        guard let ndk = nostrManager.ndk else { return }
        
        // Check if already in contacts metadata
        if let profileDataSource = nostrManager.contactsMetadataDataSource,
           profileDataSource.profile(for: pubkey) != nil {
            return
        }
        
        // Load individual profile using declarative data source
        let profileDataSource = ndk.observe(
            filter: NDKFilter(
                authors: [pubkey],
                kinds: [0]
            ),
            maxAge: 3600,
            cachePolicy: .cacheWithNetwork
        )
        
        for await event in profileDataSource.events {
            if let profileData = event.content.data(using: .utf8),
               let fetchedProfile = try? JSONDecoder().decode(NDKUserProfile.self, from: profileData) {
                await MainActor.run {
                    self.profile = fetchedProfile
                }
                break
            }
        }
    }
}

struct UserProfilePicture: View {
    let pubkey: String
    let size: CGFloat
    @Environment(NostrManager.self) private var nostrManager
    @State private var profile: NDKUserProfile?
    
    init(user: NDKUser, size: CGFloat = 40) {
        self.pubkey = user.pubkey
        self.size = size
    }
    
    init(pubkey: String, size: CGFloat = 40) {
        self.pubkey = pubkey
        self.size = size
    }
    
    var body: some View {
        Group {
            if let pictureURL = pictureURL,
               let url = URL(string: pictureURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    placeholderCircle
                }
                .frame(width: size, height: size)
                .clipShape(Circle())
            } else {
                placeholderCircle
            }
        }
        .task(id: pubkey) {
            await loadProfile()
        }
    }
    
    private var placeholderCircle: some View {
        Circle()
            .fill(Color.secondary.opacity(0.3))
            .frame(width: size, height: size)
    }
    
    private var pictureURL: String? {
        // First check if profile is in contacts metadata
        if let profileDataSource = nostrManager.contactsMetadataDataSource,
           let cachedProfile = profileDataSource.profile(for: pubkey) {
            return cachedProfile.picture
        }
        
        // Otherwise use loaded profile
        return profile?.picture
    }
    
    private func loadProfile() async {
        guard let ndk = nostrManager.ndk else { return }
        
        // Check if already in contacts metadata
        if let profileDataSource = nostrManager.contactsMetadataDataSource,
           profileDataSource.profile(for: pubkey) != nil {
            return
        }
        
        // Load individual profile using declarative data source
        let profileDataSource = ndk.observe(
            filter: NDKFilter(
                authors: [pubkey],
                kinds: [0]
            ),
            maxAge: 3600,
            cachePolicy: .cacheWithNetwork
        )
        
        for await event in profileDataSource.events {
            if let profileData = event.content.data(using: .utf8),
               let fetchedProfile = try? JSONDecoder().decode(NDKUserProfile.self, from: profileData) {
                await MainActor.run {
                    self.profile = fetchedProfile
                }
                break
            }
        }
    }
}

struct UserNIP05: View {
    let pubkey: String
    let npub: String?
    @Environment(NostrManager.self) private var nostrManager
    @State private var profile: NDKUserProfile?
    
    init(user: NDKUser) {
        self.pubkey = user.pubkey
        self.npub = user.npub
    }
    
    init(pubkey: String) {
        self.pubkey = pubkey
        self.npub = NDKUser(pubkey: pubkey).npub
    }
    
    var body: some View {
        Text(displayText)
            .task(id: pubkey) {
                await loadProfile()
            }
    }
    
    private var displayText: String {
        // First check if profile is in contacts metadata
        if let profileDataSource = nostrManager.contactsMetadataDataSource,
           let cachedProfile = profileDataSource.profile(for: pubkey) {
            if let nip05 = cachedProfile.nip05 {
                return nip05
            }
        }
        
        // Otherwise use loaded profile
        if let nip05 = profile?.nip05 {
            return nip05
        }
        
        // Fallback to npub or pubkey
        return (npub ?? pubkey).prefix(16) + "..."
    }
    
    private func loadProfile() async {
        guard let ndk = nostrManager.ndk else { return }
        
        // Check if already in contacts metadata
        if let profileDataSource = nostrManager.contactsMetadataDataSource,
           profileDataSource.profile(for: pubkey) != nil {
            return
        }
        
        // Load individual profile using declarative data source
        let profileDataSource = ndk.observe(
            filter: NDKFilter(
                authors: [pubkey],
                kinds: [0]
            ),
            maxAge: 3600,
            cachePolicy: .cacheWithNetwork
        )
        
        for await event in profileDataSource.events {
            if let profileData = event.content.data(using: .utf8),
               let fetchedProfile = try? JSONDecoder().decode(NDKUserProfile.self, from: profileData) {
                await MainActor.run {
                    self.profile = fetchedProfile
                }
                break
            }
        }
    }
}