import SwiftUI
import NDKSwift

public struct ProfileView: View {
    let ndk: NDK
    let pubkey: String

    @State private var profile: NDKUserMetadata?
    @State private var posts: [NDKEvent] = []
    @State private var followingCount = 0
    @State private var isLoading = true
    @State private var showEditProfile = false

    @EnvironmentObject private var authViewModel: AuthViewModel

    private var isOwnProfile: Bool {
        pubkey == authViewModel.currentUser?.pubkey
    }

    public init(ndk: NDK, pubkey: String) {
        self.ndk = ndk
        self.pubkey = pubkey
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ProfileHeaderView(
                    profile: profile,
                    postsCount: posts.count,
                    followingCount: followingCount,
                    isOwnProfile: isOwnProfile,
                    onEditProfile: { showEditProfile = true }
                )

                Divider()
                    .padding(.vertical, 8)

                if isLoading {
                    ProgressView()
                        .padding(.top, 40)
                } else if posts.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "camera")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("No posts yet")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 60)
                } else {
                    PostsGridView(posts: posts, ndk: ndk)
                }
            }
        }
        .navigationTitle(profile?.bestDisplayName ?? "Profile")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadProfile()
            await loadPosts()
            await loadFollowing()
        }
        .sheet(isPresented: $showEditProfile) {
            EditProfileView(ndk: ndk, currentProfile: profile) {
                Task { await loadProfile() }
            }
        }
        .toolbar {
            if isOwnProfile {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: SettingsView(ndk: ndk)) {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
    }

    private func loadProfile() async {
        for await metadata in await ndk.profileManager.subscribe(for: pubkey, maxAge: 60) {
            if let metadata {
                self.profile = metadata
            }
            break
        }
    }

    private func loadPosts() async {
        isLoading = true
        defer { isLoading = false }

        let filter = NDKFilter(
            authors: [pubkey],
            kinds: [OlasConstants.EventKinds.image],
            limit: 50
        )

        let subscription = ndk.subscribe(filter: filter)
        var fetchedPosts: [NDKEvent] = []

        for await event in subscription.events {
            fetchedPosts.append(event)
            if fetchedPosts.count >= 50 { break }
        }

        posts = fetchedPosts.sorted { $0.createdAt > $1.createdAt }
    }

    private func loadFollowing() async {
        let user = NDKUser(pubkey: pubkey)
        user.ndk = ndk

        do {
            let follows = try await user.follows()
            followingCount = follows.count
        } catch {
            followingCount = 0
        }
    }
}

struct ProfileHeaderView: View {
    let profile: NDKUserMetadata?
    let postsCount: Int
    let followingCount: Int
    let isOwnProfile: Bool
    let onEditProfile: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            // Banner
            if let bannerUrl = profile?.banner, let url = URL(string: bannerUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [OlasTheme.Colors.deepTeal, OlasTheme.Colors.oceanBlue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
                .frame(height: 120)
                .clipped()
            } else {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [OlasTheme.Colors.deepTeal, OlasTheme.Colors.oceanBlue],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 120)
            }

            VStack(spacing: 12) {
                // Avatar
                if let pictureUrl = profile?.picture, let url = URL(string: pictureUrl) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Circle()
                            .fill(.secondary.opacity(0.3))
                    }
                    .frame(width: 90, height: 90)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(.background, lineWidth: 4))
                    .offset(y: -60)
                } else {
                    Circle()
                        .fill(.secondary.opacity(0.3))
                        .frame(width: 90, height: 90)
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary)
                        )
                        .overlay(Circle().stroke(.background, lineWidth: 4))
                        .offset(y: -60)
                }

                VStack(spacing: 4) {
                    Text(profile?.bestDisplayName ?? "Anonymous")
                        .font(.title2.bold())

                    if let nip05 = profile?.nip05 {
                        Text(nip05)
                            .font(.subheadline)
                            .foregroundStyle(OlasTheme.Colors.deepTeal)
                    }

                    if let about = profile?.about, !about.isEmpty {
                        Text(about)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .padding(.horizontal)
                    }
                }
                .offset(y: -50)

                // Stats
                HStack(spacing: 40) {
                    StatView(value: postsCount, label: "Posts")
                    StatView(value: followingCount, label: "Following")
                }
                .offset(y: -40)

                // Edit button for own profile
                if isOwnProfile {
                    Button(action: onEditProfile) {
                        Text("Edit Profile")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial)
                            .cornerRadius(8)
                    }
                    .padding(.horizontal)
                    .offset(y: -30)
                }
            }
        }
        .padding(.bottom, isOwnProfile ? -20 : -40)
    }
}

struct StatView: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.headline.bold())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct PostsGridView: View {
    let posts: [NDKEvent]
    let ndk: NDK

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(posts, id: \.id) { post in
                PostGridCell(event: post)
            }
        }
    }
}

struct PostGridCell: View {
    let event: NDKEvent

    private var imageUrl: String? {
        // Extract image URL from imeta tag or content
        for tag in event.tags {
            if tag.first == "imeta" {
                for part in tag {
                    if part.hasPrefix("url ") {
                        return String(part.dropFirst(4))
                    }
                }
            }
        }
        // Fallback: look for URL in content
        let urlPattern = #"https?://[^\s]+"#
        if let match = event.content.range(of: urlPattern, options: .regularExpression) {
            return String(event.content[match])
        }
        return nil
    }

    var body: some View {
        GeometryReader { geo in
            if let urlString = imageUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Rectangle()
                        .fill(.secondary.opacity(0.2))
                }
                .frame(width: geo.size.width, height: geo.size.width)
                .clipped()
            } else {
                Rectangle()
                    .fill(.secondary.opacity(0.2))
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    )
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
