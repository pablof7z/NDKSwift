import SwiftUI
import NDKSwift

// Helper views for accessing async user profile properties

struct UserDisplayName: View {
    let user: NDKUser
    @State private var displayName = "Nostr User"
    @State private var profileTask: Task<Void, Never>?
    @Environment(NostrManager.self) private var nostrManager
    
    var body: some View {
        Text(displayName)
            .task {
                guard let ndk = nostrManager.ndk else { return }
                
                profileTask = Task {
                    let profileStream = await ndk.observeProfile(for: user.pubkey, closeOnEose: true)
                    
                    for await profile in profileStream {
                        if let profile = profile {
                            await MainActor.run {
                                displayName = profile.displayName ?? profile.name ?? "Nostr User"
                            }
                            break // We only need the first profile for display
                        }
                    }
                }
            }
            .onDisappear {
                profileTask?.cancel()
            }
    }
}

struct UserProfilePicture: View {
    let user: NDKUser
    let size: CGFloat
    @State private var pictureURL: String?
    @State private var profileTask: Task<Void, Never>?
    @Environment(NostrManager.self) private var nostrManager
    
    init(user: NDKUser, size: CGFloat = 40) {
        self.user = user
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
                    Circle()
                        .fill(Color.secondary.opacity(0.3))
                }
                .frame(width: size, height: size)
                .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: size, height: size)
            }
        }
        .task {
            guard let ndk = nostrManager.ndk else { return }
            
            profileTask = Task {
                let profileStream = await ndk.observeProfile(for: user.pubkey, closeOnEose: true)
                
                for await profile in profileStream {
                    if let profile = profile {
                        await MainActor.run {
                            pictureURL = profile.picture
                        }
                        break // We only need the first profile for display
                    }
                }
            }
        }
        .onDisappear {
            profileTask?.cancel()
        }
    }
}

struct UserNIP05: View {
    let user: NDKUser
    @State private var nip05: String?
    @State private var npub: String?
    @State private var profileTask: Task<Void, Never>?
    @Environment(NostrManager.self) private var nostrManager
    
    var body: some View {
        Group {
            if let nip05 = nip05 {
                Text(nip05)
            } else if let npub = npub {
                Text(String(npub.prefix(16)) + "...")
            } else {
                Text("")
            }
        }
        .task {
            npub = user.npub
            
            guard let ndk = nostrManager.ndk else { return }
            
            profileTask = Task {
                let profileStream = await ndk.observeProfile(for: user.pubkey, closeOnEose: true)
                
                for await profile in profileStream {
                    if let profile = profile {
                        await MainActor.run {
                            nip05 = profile.nip05
                        }
                        break // We only need the first profile for display
                    }
                }
            }
        }
        .onDisappear {
            profileTask?.cancel()
        }
    }
}