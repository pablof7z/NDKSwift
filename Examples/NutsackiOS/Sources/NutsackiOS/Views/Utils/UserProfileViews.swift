import SwiftUI
import NDKSwift

// Helper views for accessing async user profile properties

struct UserDisplayName: View {
    let user: NDKUser
    @State private var displayName = "Nostr User"
    
    var body: some View {
        Text(displayName)
            .task {
                if let profile = await user.profile {
                    displayName = profile.displayName ?? profile.name ?? "Nostr User"
                }
            }
    }
}

struct UserProfilePicture: View {
    let user: NDKUser
    let size: CGFloat
    @State private var pictureURL: String?
    
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
            if let profile = await user.profile {
                pictureURL = profile.picture
            }
        }
    }
}

struct UserNIP05: View {
    let user: NDKUser
    @State private var nip05: String?
    @State private var npub: String?
    
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
            if let profile = await user.profile {
                nip05 = profile.nip05
            }
            npub = user.npub
        }
    }
}