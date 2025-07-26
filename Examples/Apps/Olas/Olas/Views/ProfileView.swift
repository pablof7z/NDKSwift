import SwiftUI
import NDKSwift

struct ProfileView: View {
    let pubkey: String
    @Environment(NostrManager.self) private var nostrManager
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = ProfileViewModel()
    @State private var selectedTab = 0
    @State private var headerHeight: CGFloat = 300
    @State private var scrollOffset: CGFloat = 0
    @State private var showFollowers = false
    @State private var showFollowing = false
    @State private var selectedFollowMode: FollowersListView.FollowMode = .followers
    
    var body: some View {
        ZStack {
            OlasDesign.Colors.background
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 0) {
                    // Profile Header with Parallax
                    ProfileHeaderView(
                        profile: viewModel.profile,
                        pubkey: pubkey,
                        scrollOffset: scrollOffset,
                        isFollowing: viewModel.isFollowing,
                        followersCount: viewModel.followersCount,
                        followingCount: viewModel.followingCount,
                        postsCount: viewModel.postsCount,
                        onFollowToggle: { viewModel.toggleFollow() }
                    )
                    .frame(height: headerHeight)
                    
                    // Content Tabs
                    ProfileTabBar(selectedTab: $selectedTab)
                        .padding(.top, OlasDesign.Spacing.md)
                    
                    // Content Grid
                    switch selectedTab {
                    case 0:
                        ProfileImageGrid(posts: viewModel.imagePosts)
                            .padding(.top, OlasDesign.Spacing.md)
                    case 1:
                        ProfileRepliesView(replies: viewModel.replies)
                            .padding(.top, OlasDesign.Spacing.md)
                    case 2:
                        ProfileZapsView(zaps: viewModel.zaps)
                            .padding(.top, OlasDesign.Spacing.md)
                    default:
                        EmptyView()
                    }
                }
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .preference(key: ScrollOffsetPreferenceKey.self, value: geo.frame(in: .named("scroll")).minY)
                    }
                )
            }
            .coordinateSpace(name: "scroll")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                scrollOffset = value
            }
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            if let ndk = nostrManager.ndk {
                viewModel.startObserving(pubkey: pubkey, ndk: ndk)
            }
        }
        .sheet(isPresented: $showFollowers) {
            FollowersListView(pubkey: pubkey, mode: .followers)
                .environment(nostrManager)
        }
        .sheet(isPresented: $showFollowing) {
            FollowersListView(pubkey: pubkey, mode: .following)
                .environment(nostrManager)
        }
    }
}

// MARK: - Profile Header
struct ProfileHeaderView: View {
    let profile: NDKUserProfile?
    let pubkey: String
    let scrollOffset: CGFloat
    let isFollowing: Bool
    let followersCount: Int
    let followingCount: Int
    let postsCount: Int
    let onFollowToggle: () -> Void
    
    private var parallaxOffset: CGFloat {
        scrollOffset > 0 ? -scrollOffset / 2 : 0
    }
    
    private var scale: CGFloat {
        scrollOffset > 0 ? 1 + (scrollOffset / 500) : 1
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Banner Image with Parallax
            if let banner = profile?.banner, let bannerURL = URL(string: banner) {
                AsyncImage(url: bannerURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 200)
                        .scaleEffect(scale)
                        .offset(y: parallaxOffset)
                        .clipped()
                } placeholder: {
                    OlasLoadingView()
                        .frame(height: 200)
                }
            } else {
                OlasDesign.currentGradient
                .frame(height: 200)
                .scaleEffect(scale)
                .offset(y: parallaxOffset)
            }
            
            // Profile Info
            VStack(spacing: OlasDesign.Spacing.md) {
                // Avatar with 3D rotation
                OlasAvatar(
                    url: profile?.picture,
                    size: 120,
                    pubkey: pubkey
                )
                .overlay(
                    Circle()
                        .stroke(OlasDesign.Colors.background, lineWidth: 4)
                )
                .rotation3DEffect(
                    .degrees(Double(scrollOffset / 10)),
                    axis: (x: 0, y: 1, z: 0)
                )
                .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                .offset(y: 60) // Overlap with banner
                
                // Name and username
                VStack(spacing: 4) {
                    Text(profile?.displayName ?? profile?.name ?? "Loading...")
                        .font(OlasDesign.Typography.title)
                        .foregroundColor(OlasDesign.Colors.text)
                        .olasTextShadow()
                    
                    Text("@\(profile?.name ?? String(pubkey.prefix(8)))")
                        .font(OlasDesign.Typography.body)
                        .foregroundColor(OlasDesign.Colors.textSecondary)
                }
                .padding(.top, 70)
                
                // Bio
                if let about = profile?.about {
                    Text(about)
                        .font(OlasDesign.Typography.body)
                        .foregroundColor(OlasDesign.Colors.text)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, OlasDesign.Spacing.lg)
                }
                
                // Stats with animated counting
                HStack(spacing: OlasDesign.Spacing.xl) {
                    ProfileStatView(value: postsCount, label: "Posts")
                    
                    ProfileStatView(value: followersCount, label: "Followers")
                    
                    ProfileStatView(value: followingCount, label: "Following")
                }
                
                // Follow/Edit Button
                OlasButton(
                    title: isFollowing ? "Following" : "Follow",
                    action: {
                        #if os(iOS)
                        OlasDesign.Haptic.impact(.medium)
                        #else
                        OlasDesign.Haptic.impact(0)
                        #endif
                        onFollowToggle()
                    },
                    style: isFollowing ? .secondary : .primary
                )
                .padding(.horizontal, OlasDesign.Spacing.lg)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFollowing)
            }
            .padding(.bottom, OlasDesign.Spacing.lg)
            .background(
                OlasDesign.Colors.background
                    .opacity(0.95)
                    .blur(radius: 20)
                    .padding(.top, -50) // Extend behind avatar
            )
        }
    }
}

// MARK: - Profile Stats
struct ProfileStatView: View {
    let value: Int
    let label: String
    @State private var displayValue = 0
    
    var body: some View {
        VStack(spacing: 4) {
            Text(displayValue < 0 ? "N/A" : "\(displayValue)")
                .font(OlasDesign.Typography.title)
                .foregroundColor(OlasDesign.Colors.text)
                .contentTransition(.numericText())
                .olasTextShadow()
            
            Text(label)
                .font(OlasDesign.Typography.caption)
                .foregroundColor(OlasDesign.Colors.textSecondary)
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                displayValue = value
            }
        }
        .onChange(of: value) { _, newValue in
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                displayValue = newValue
            }
        }
    }
}

// MARK: - Tab Bar
struct ProfileTabBar: View {
    @Binding var selectedTab: Int
    
    var body: some View {
        HStack(spacing: 0) {
            ProfileTabButton(
                icon: "square.grid.3x3",
                isSelected: selectedTab == 0,
                action: { selectedTab = 0 }
            )
            
            ProfileTabButton(
                icon: "bubble.left",
                isSelected: selectedTab == 1,
                action: { selectedTab = 1 }
            )
            
            ProfileTabButton(
                icon: "bolt",
                isSelected: selectedTab == 2,
                action: { selectedTab = 2 }
            )
        }
        .background(OlasDesign.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.md))
        .padding(.horizontal, OlasDesign.Spacing.lg)
    }
}

struct ProfileTabButton: View {
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            OlasDesign.Haptic.selection()
            action()
        }) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(isSelected ? OlasDesign.Colors.primary : OlasDesign.Colors.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: 44)
                .background(
                    isSelected ? OlasDesign.Colors.primary.opacity(0.1) : Color.clear
                )
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        }
    }
}

// MARK: - Image Grid
struct ProfileImageGrid: View {
    let posts: [ProfilePost]
    let columns = Array(repeating: GridItem(.flexible(), spacing: 1), count: 3)
    @State private var selectedPost: ProfilePost?
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: 1) {
            ForEach(posts) { post in
                ProfileImageCell(post: post) {
                    selectedPost = post
                }
            }
        }
        .padding(.horizontal, 1)
        #if os(iOS)
        .fullScreenCover(item: $selectedPost) { post in
            FullScreenPostViewer(post: post)
        }
        #else
        .sheet(item: $selectedPost) { post in
            FullScreenPostViewer(post: post)
        }
        #endif
    }
}

struct ProfileImageCell: View {
    let post: ProfilePost
    let onTap: () -> Void
    @State private var isLoaded = false
    @State private var scale: CGFloat = 0.8
    
    var body: some View {
        GeometryReader { geometry in
            if let firstImage = post.imageURLs.first, let url = URL(string: firstImage) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.width)
                        .clipped()
                        .scaleEffect(scale)
                        .onAppear {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                                isLoaded = true
                                scale = 1.0
                            }
                        }
                } placeholder: {
                    OlasLoadingView()
                        .frame(height: 200)
                }
                .onTapGesture {
                    OlasDesign.Haptic.selection()
                    onTap()
                }
                
                // Multiple images indicator
                if post.imageURLs.count > 1 {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "square.stack")
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(4)
                                .background(Color.black.opacity(0.6))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .padding(4)
                        }
                        Spacer()
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - Other Views
struct ProfileRepliesView: View {
    let replies: [NDKEvent]
    
    var body: some View {
        LazyVStack(spacing: 1) {
            ForEach(replies, id: \.id) { reply in
                ReplyCell(event: reply)
            }
        }
        .padding(.horizontal, OlasDesign.Spacing.md)
    }
}

struct ProfileZapsView: View {
    let zaps: [ZapInfo]
    
    var body: some View {
        LazyVStack(spacing: OlasDesign.Spacing.md) {
            ForEach(zaps) { zap in
                ZapCell(zap: zap)
            }
        }
        .padding(.horizontal, OlasDesign.Spacing.md)
    }
}

// MARK: - View Model
@MainActor
class ProfileViewModel: ObservableObject {
    @Published var profile: NDKUserProfile?
    @Published var imagePosts: [ProfilePost] = []
    @Published var replies: [NDKEvent] = []
    @Published var zaps: [ZapInfo] = []
    @Published var isFollowing = false
    @Published var followersCount = 0
    @Published var followingCount = 0
    @Published var postsCount = 0
    
    private var pubkey: String = ""
    private var ndk: NDK?
    
    func startObserving(pubkey: String, ndk: NDK) {
        self.pubkey = pubkey
        self.ndk = ndk
        
        // Observe profile updates
        Task {
            guard let profileManager = ndk.profileManager else { return }
            
            for await profile in await profileManager.observe(for: pubkey, maxAge: 3600) {
                if let profile = profile {
                    await MainActor.run {
                        self.profile = profile
                    }
                }
            }
        }
        
        // Observe picture posts (NIP-68)
        Task {
            let filter = NDKFilter(
                authors: [pubkey],
                kinds: [EventKind.image]
            )
            
            let dataSource = ndk.observe(filter: filter, cachePolicy: .cacheWithNetwork)
            
            for await event in dataSource.events {
                // Extract image URLs using NDKEvent's built-in imeta support
                let imageURLs = event.imageURLs
                
                if !imageURLs.isEmpty {
                    let post = ProfilePost(event: event, imageURLs: imageURLs)
                    await MainActor.run {
                        imagePosts.insert(post, at: 0)
                        postsCount = imagePosts.count
                    }
                }
            }
        }
        
        // Check following status
        checkFollowingStatus()
        
        // Load follower counts
        loadFollowerCounts()
        
        // Load replies (NIP-22 comments)
        loadReplies()
    }
    
    func toggleFollow() {
        guard let ndk = ndk else { return }
        
        Task {
            do {
                if isFollowing {
                    // Unfollow
                    let user = NDKUser(pubkey: pubkey)
                    try await ndk.unfollow(user)
                } else {
                    // Follow
                    let user = NDKUser(pubkey: pubkey)
                    try await ndk.follow(user)
                }
                
                await MainActor.run {
                    isFollowing.toggle()
                    if isFollowing {
                        followersCount += 1
                    } else {
                        followersCount = max(0, followersCount - 1)
                    }
                }
            } catch {
                print("Failed to toggle follow: \(error)")
            }
        }
    }
    
    private func checkFollowingStatus() {
        guard let ndk = ndk else { return }
        
        Task {
            do {
                let contactList = try await ndk.fetchContactList()
                await MainActor.run {
                    isFollowing = contactList?.tags.contains(where: { tag in
                        tag.count >= 2 && tag[0] == "p" && tag[1] == pubkey
                    }) ?? false
                }
            } catch {
                print("Failed to fetch contact list: \(error)")
            }
        }
    }
    
    private func loadFollowerCounts() {
        guard let ndk = ndk else { return }
        
        Task {
            // Load following count from contact list (kind 3)
            let contactFilter = NDKFilter(
                authors: [pubkey],
                kinds: [3],  // Contact list
                limit: 1
            )
            
            let dataSource = ndk.observe(filter: contactFilter, cachePolicy: .cacheWithNetwork)
            let events = await dataSource.collect(timeout: 3.0)
            if let contactList = events.first {
                // Count 'p' tags in contact list
                let followingCount = contactList.tags.filter { $0.count >= 2 && $0[0] == "p" }.count
                await MainActor.run {
                    self.followingCount = followingCount
                }
            } else {
                await MainActor.run {
                    self.followingCount = 0
                }
            }
            
            // Follower count is complex and resource-intensive to calculate
            // Set to -1 to indicate N/A in the UI
            await MainActor.run {
                followersCount = -1  // Will display as N/A
            }
        }
    }
    
    private func loadReplies() {
        guard let ndk = ndk else { return }
        
        // This section would need proper implementation:
        // - First load all posts by this user
        // - Then for each post, load comments with proper NIP-22 tags
        // - The current implementation that loads ALL comments by the user is conceptually wrong
        
        // For now, we'll just clear the replies to avoid the incorrect behavior
        Task {
            await MainActor.run {
                replies.removeAll()
            }
        }
    }
}

// MARK: - Models
struct ProfilePost: Identifiable {
    let id: String
    let event: NDKEvent
    let imageURLs: [String]
    
    init(event: NDKEvent, imageURLs: [String]) {
        self.id = event.id
        self.event = event
        self.imageURLs = imageURLs
    }
}

struct ZapInfo: Identifiable {
    let id = UUID()
    let amount: Int
    let from: String
    let message: String?
    let timestamp: Date
}

struct ReplyCell: View {
    let event: NDKEvent
    
    var body: some View {
        VStack(alignment: .leading, spacing: OlasDesign.Spacing.sm) {
            OlasRichText(content: event.content, tags: event.tags)
            
            Text(Date(timeIntervalSince1970: Double(event.createdAt)).formatted(.relative(presentation: .named)))
                .font(OlasDesign.Typography.caption)
                .foregroundColor(OlasDesign.Colors.textTertiary)
        }
        .padding(OlasDesign.Spacing.md)
        .background(OlasDesign.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.md))
    }
}

struct ZapCell: View {
    let zap: ZapInfo
    
    var body: some View {
        HStack(spacing: OlasDesign.Spacing.md) {
            Image(systemName: "bolt.fill")
                .font(.title2)
                .foregroundColor(.orange)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("\(zap.amount) sats")
                    .font(OlasDesign.Typography.bodyMedium)
                    .foregroundColor(OlasDesign.Colors.text)
                
                if let message = zap.message {
                    Text(message)
                        .font(OlasDesign.Typography.caption)
                        .foregroundColor(OlasDesign.Colors.textSecondary)
                        .lineLimit(2)
                }
            }
            
            Spacer()
            
            Text(zap.timestamp.formatted(.relative(presentation: .named)))
                .font(OlasDesign.Typography.caption)
                .foregroundColor(OlasDesign.Colors.textTertiary)
        }
        .padding(OlasDesign.Spacing.md)
        .background(OlasDesign.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.md))
    }
}

struct FullScreenPostViewer: View {
    let post: ProfilePost
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            OlasMultiImageView(imageURLs: post.imageURLs)
            
            VStack {
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    Spacer()
                }
                .padding()
                
                Spacer()
            }
        }
    }
}

// MARK: - Preference Key
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}