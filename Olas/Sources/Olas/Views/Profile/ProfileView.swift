import SwiftUI
import NDKSwift
import NDKSwiftUI

public struct ProfileView: View {
    let ndk: NDK
    let pubkey: String
    let currentUserPubkey: String?

    @EnvironmentObject private var muteListManager: MuteListManager
    @State private var profile: NDKUserMetadata?
    @State private var posts: [NDKEvent] = []
    @State private var followingCount = 0
    @State private var showEditProfile = false
    @State private var selectedTab: ProfileTab = .posts
    @State private var selectedPost: NDKEvent?

    private var isOwnProfile: Bool {
        guard let currentUserPubkey else { return false }
        return pubkey == currentUserPubkey
    }

    private var isMuted: Bool {
        muteListManager.isMuted(pubkey)
    }

    public init(ndk: NDK, pubkey: String, currentUserPubkey: String? = nil) {
        self.ndk = ndk
        self.pubkey = pubkey
        self.currentUserPubkey = currentUserPubkey
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Hero section with banner and profile info
                ProfileHeroSection(profile: profile)

                // Stats bar
                ProfileStatsBar(
                    postsCount: posts.count,
                    followingCount: followingCount
                )

                // Bio and actions
                ProfileBioSection(
                    ndk: ndk,
                    pubkey: pubkey,
                    profile: profile,
                    isOwnProfile: isOwnProfile,
                    isMuted: isMuted,
                    onEditProfile: { showEditProfile = true },
                    onToggleMute: { Task { await toggleMute() } }
                )

                // Collections
                ProfileCollectionsSection(isOwnProfile: isOwnProfile)

                // Tabs
                ProfileTabsBar(selectedTab: $selectedTab)

                // Content grid - shows posts as they stream in
                PostsGridView(posts: posts, ndk: ndk) { post in
                    selectedPost = post
                }
            }
        }
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
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
        .fullScreenCover(item: $selectedPost) { post in
            FullscreenPostViewer(
                event: post,
                ndk: ndk,
                isPresented: Binding(
                    get: { selectedPost != nil },
                    set: { if !$0 { selectedPost = nil } }
                )
            )
        }
        .toolbar {
            if isOwnProfile {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: SettingsView(ndk: ndk)) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(.black.opacity(0.4))
                            .clipShape(Circle())
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

    private var feedKinds: [Kind] {
        var kinds: [Kind] = [OlasConstants.EventKinds.image]
        if SettingsManager.shared.showVideos {
            kinds.append(OlasConstants.EventKinds.shortVideo)
        }
        return kinds
    }

    private func loadPosts() async {
        let filter = NDKFilter(
            authors: [pubkey],
            kinds: feedKinds,
            limit: 50
        )

        let subscription = ndk.subscribe(filter: filter)

        // Stream posts as they arrive - insert sorted to maintain order
        for await event in subscription.events {
            // Insert in sorted position (newest first)
            let insertIndex = posts.firstIndex { event.createdAt > $0.createdAt } ?? posts.endIndex
            posts.insert(event, at: insertIndex)
        }
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

    private func toggleMute() async {
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()

        do {
            if isMuted {
                try await muteListManager.unmute(pubkey)
            } else {
                try await muteListManager.mute(pubkey)
            }
        } catch {
            // Mute/unmute failed silently
        }
    }
}

// MARK: - Profile Tab Enum

enum ProfileTab: String, CaseIterable {
    case posts = "Posts"
    case liked = "Liked"
    case zaps = "Zaps"
}

// MARK: - Hero Section

struct ProfileHeroSection: View {
    let profile: NDKUserMetadata?

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Banner image
                if let bannerUrl = profile?.banner, let url = URL(string: bannerUrl) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        defaultBannerGradient
                    }
                    .frame(width: geometry.size.width, height: 300)
                    .clipped()
                } else {
                    defaultBannerGradient
                        .frame(height: 300)
                }

                // Gradient overlay
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.3), location: 0),
                        .init(color: .clear, location: 0.3),
                        .init(color: .clear, location: 0.5),
                        .init(color: .black.opacity(0.95), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 300)

                // Profile info at bottom of hero
                HStack(alignment: .bottom, spacing: 14) {
                    // Avatar
                    ProfileAvatar(pictureUrl: profile?.picture, size: 80)

                    // Name and username
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile?.bestDisplayName ?? "Anonymous")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.white)

                        if let name = profile?.name, !name.isEmpty {
                            Text("@\(name)")
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .frame(height: 300)
    }

    private var defaultBannerGradient: some View {
        LinearGradient(
            colors: [OlasTheme.Colors.deepTeal, OlasTheme.Colors.oceanBlue],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Profile Avatar

struct ProfileAvatar: View {
    let pictureUrl: String?
    let size: CGFloat

    var body: some View {
        if let pictureUrl, let url = URL(string: pictureUrl) {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                placeholderAvatar
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().stroke(.black, lineWidth: 3))
            .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
        } else {
            placeholderAvatar
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(Circle().stroke(.black, lineWidth: 3))
        }
    }

    private var placeholderAvatar: some View {
        Circle()
            .fill(.secondary.opacity(0.3))
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.4))
                    .foregroundStyle(.secondary)
            )
    }
}

// MARK: - Stats Bar

struct ProfileStatsBar: View {
    let postsCount: Int
    let followingCount: Int

    var body: some View {
        HStack(spacing: 32) {
            StatItem(value: formatCount(postsCount), label: "posts")
            StatItem(value: formatCount(followingCount), label: "following")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.3)
        }
    }

    private func formatCount(_ count: Int) -> String {
        if count >= 1000000 {
            return String(format: "%.1fM", Double(count) / 1000000)
        } else if count >= 1000 {
            return String(format: "%.1fK", Double(count) / 1000)
        }
        return "\(count)"
    }
}

struct StatItem: View {
    let value: String
    let label: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(.system(size: 17, weight: .bold))
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Bio Section

struct ProfileBioSection: View {
    let ndk: NDK
    let pubkey: String
    let profile: NDKUserMetadata?
    let isOwnProfile: Bool
    let isMuted: Bool
    let onEditProfile: () -> Void
    let onToggleMute: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Muted indicator
            if isMuted && !isOwnProfile {
                HStack(spacing: 8) {
                    Image(systemName: "speaker.slash.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    Text("You have muted this user")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.secondary.opacity(0.1))
                .cornerRadius(8)
            }

            // Bio text
            if let about = profile?.about, !about.isEmpty {
                Text(about)
                    .font(.system(size: 15))
                    .lineSpacing(2)
            }

            // NIP-05
            if let nip05 = profile?.nip05, !nip05.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 16, height: 16)
                        .background(OlasTheme.Colors.oceanBlue)
                        .clipShape(Circle())

                    Text(nip05)
                        .font(.system(size: 14))
                        .foregroundStyle(OlasTheme.Colors.oceanBlue)
                }
            }

            // Action buttons
            HStack(spacing: 10) {
                if isOwnProfile {
                    Button(action: onEditProfile) {
                        Text("Edit Profile")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(OlasTheme.Colors.oceanBlue)
                            .foregroundStyle(.white)
                            .cornerRadius(12)
                    }
                } else {
                    NDKUIFollowButton(ndk: ndk, pubkey: pubkey)
                }

                Button(action: {}) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(.secondary.opacity(0.3), lineWidth: 1.5)
                        )
                }

                if !isOwnProfile {
                    Button(action: {}) {
                        Text("⚡")
                            .font(.system(size: 18))
                            .frame(width: 44, height: 44)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(.secondary.opacity(0.3), lineWidth: 1.5)
                            )
                    }

                    // Mute/Unmute button
                    Button(action: onToggleMute) {
                        Image(systemName: isMuted ? "speaker.wave.2" : "speaker.slash")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(isMuted ? OlasTheme.Colors.oceanBlue : .secondary.opacity(0.3), lineWidth: 1.5)
                            )
                            .foregroundStyle(isMuted ? OlasTheme.Colors.oceanBlue : .primary)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.3)
        }
    }
}

// MARK: - Collections Section

struct ProfileCollectionsSection: View {
    let isOwnProfile: Bool

    // Placeholder collections - these would come from actual data
    private let collections = [
        ("Surf", "🏄"),
        ("Travel", "✈️"),
        ("Sunsets", "🌅"),
        ("Food", "🍜"),
        ("Code", "💻")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Section header
            HStack {
                Text("COLLECTIONS")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)

                Spacer()

                Button(action: {}) {
                    Text("See All")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(OlasTheme.Colors.oceanBlue)
                }
            }
            .padding(.horizontal, 20)

            // Horizontal scroll of collections
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    // Add new collection (only for own profile)
                    if isOwnProfile {
                        CollectionItem(name: "New", isAddButton: true)
                    }

                    // Collection items
                    ForEach(collections, id: \.0) { name, emoji in
                        CollectionItem(name: name, emoji: emoji)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.vertical, 20)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.3)
        }
    }
}

struct CollectionItem: View {
    let name: String
    var emoji: String? = nil
    var isAddButton: Bool = false

    var body: some View {
        VStack(spacing: 8) {
            if isAddButton {
                // Add button style
                Circle()
                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [5]))
                    .foregroundStyle(.secondary.opacity(0.3))
                    .frame(width: 66, height: 66)
                    .overlay(
                        Image(systemName: "plus")
                            .font(.system(size: 24, weight: .light))
                            .foregroundStyle(.secondary.opacity(0.6))
                    )
            } else {
                // Collection thumbnail with gradient ring
                ZStack {
                    // Gradient ring
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [OlasTheme.Colors.oceanBlue, OlasTheme.Colors.seafoam],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 3
                        )
                        .frame(width: 72, height: 72)

                    // Inner circle with emoji placeholder
                    Circle()
                        .fill(Color(white: 0.15))
                        .frame(width: 64, height: 64)
                        .overlay(
                            Text(emoji ?? "📷")
                                .font(.system(size: 28))
                        )
                }
            }

            Text(name)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Tabs Bar

struct ProfileTabsBar: View {
    @Binding var selectedTab: ProfileTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ProfileTab.allCases, id: \.self) { tab in
                Button(action: { selectedTab = tab }) {
                    VStack(spacing: 0) {
                        Text(tab.rawValue)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(selectedTab == tab ? Color.primary : Color.secondary.opacity(0.6))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)

                        // Underline indicator
                        Rectangle()
                            .fill(selectedTab == tab ? OlasTheme.Colors.oceanBlue : .clear)
                            .frame(height: 2)
                            .padding(.horizontal, 20)
                    }
                }
            }
        }
        .overlay(alignment: .bottom) {
            Divider().opacity(0.3)
        }
    }
}

// MARK: - Posts Grid

struct PostsGridView: View {
    let posts: [NDKEvent]
    let ndk: NDK
    let onPostTap: (NDKEvent) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 1) {
            ForEach(posts, id: \.id) { post in
                PostGridCell(event: post) {
                    onPostTap(post)
                }
            }
        }
        .background(Color(white: 0.15))
    }
}

struct PostGridCell: View {
    let event: NDKEvent
    let onTap: () -> Void

    private var isVideo: Bool {
        event.kind == OlasConstants.EventKinds.shortVideo
    }

    private var video: NDKVideo {
        NDKVideo(event: event)
    }

    private var thumbnailUrl: URL? {
        if isVideo {
            if let thumb = video.thumbnailURL {
                return URL(string: thumb)
            }
            return nil
        } else {
            // Extract image URL from imeta tag or content
            for tag in event.tags {
                if tag.first == "imeta" {
                    for part in tag {
                        if part.hasPrefix("url ") {
                            return URL(string: String(part.dropFirst(4)))
                        }
                    }
                }
            }
            // Fallback: look for URL in content
            let urlPattern = #"https?://[^\s]+"#
            if let match = event.content.range(of: urlPattern, options: .regularExpression) {
                return URL(string: String(event.content[match]))
            }
            return nil
        }
    }

    private var blurhash: String? {
        if isVideo {
            return video.primaryBlurhash
        }
        return NDKImage(event: event).primaryBlurhash
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let url = thumbnailUrl {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        // Show blurhash placeholder if available
                        if let hash = blurhash {
                            BlurhashPlaceholder(blurhash: hash)
                        } else {
                            Rectangle()
                                .fill(Color(white: 0.1))
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.width)
                    .clipped()
                } else if isVideo {
                    // Video without thumbnail - show gradient with play icon
                    LinearGradient(
                        colors: [OlasTheme.Colors.deepTeal.opacity(0.8), OlasTheme.Colors.oceanBlue.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .overlay(
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.white.opacity(0.9))
                    )
                } else {
                    Rectangle()
                        .fill(Color(white: 0.1))
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                        )
                }

                // Video indicator overlay (bottom right)
                if isVideo && thumbnailUrl != nil {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Image(systemName: "play.fill")
                                .font(.caption)
                                .foregroundStyle(.white)
                                .padding(4)
                                .background(.black.opacity(0.5))
                                .clipShape(Circle())
                                .padding(6)
                        }
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }
}

// MARK: - Blurhash Placeholder

private struct BlurhashPlaceholder: View {
    let blurhash: String

    var body: some View {
        if let image = decodeBlurHash(blurhash) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Rectangle()
                .fill(Color(white: 0.1))
        }
    }

    private func decodeBlurHash(_ hash: String) -> UIImage? {
        return BlurhashDecoder.decode(hash, size: CGSize(width: 32, height: 32))
    }
}
