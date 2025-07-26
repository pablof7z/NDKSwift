import SwiftUI
import NDKSwift

struct HashtagView: View {
    let hashtag: String
    @Environment(NostrManager.self) private var nostrManager
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    
    @State private var posts: [NDKEvent] = []
    @State private var profiles: [String: NDKUserProfile] = [:]
    @State private var isLoading = true
    @State private var isFollowing = false
    @State private var stats = HashtagStats()
    
    struct HashtagStats {
        var totalPosts: Int = 0
        var postsToday: Int = 0
        var uniqueAuthors: Int = 0
    }
    
    private let columns = [
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1)
    ]
    
    var body: some View {
        NavigationStack {
            ZStack {
                OlasDesign.Colors.background
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 0) {
                        // Header
                        hashtagHeader
                            .padding(OlasDesign.Spacing.lg)
                        
                        // Stats
                        statsView
                            .padding(.horizontal, OlasDesign.Spacing.lg)
                            .padding(.bottom, OlasDesign.Spacing.lg)
                        
                        // Content
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: OlasDesign.Colors.primary))
                                .scaleEffect(1.5)
                                .frame(minHeight: 300)
                        } else if posts.isEmpty {
                            emptyState
                        } else {
                            postsGrid
                        }
                    }
                }
            }
            .navigationTitle("#\(hashtag)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(OlasDesign.Colors.primary)
                }
            }
            #else
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(OlasDesign.Colors.primary)
                }
            }
            #endif
            .task {
                await loadHashtagPosts()
            }
        }
    }
    
    @ViewBuilder
    private var hashtagHeader: some View {
        VStack(spacing: OlasDesign.Spacing.md) {
            // Large hashtag display
            Text("#\(hashtag)")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [OlasDesign.Colors.primary, OlasDesign.Colors.secondary],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            // Follow button
            OlasButton(
                title: isFollowing ? "Following" : "Follow Hashtag",
                action: {
                    isFollowing.toggle()
                    OlasDesign.Haptic.success()
                },
                style: isFollowing ? .secondary : .primary
            )
            .frame(width: 200)
        }
    }
    
    @ViewBuilder
    private var statsView: some View {
        HStack(spacing: OlasDesign.Spacing.xl) {
            VStack(spacing: 4) {
                Text("\(stats.totalPosts)")
                    .font(OlasDesign.Typography.title)
                    .foregroundColor(OlasDesign.Colors.text)
                Text("Total Posts")
                    .font(OlasDesign.Typography.caption)
                    .foregroundColor(OlasDesign.Colors.textSecondary)
            }
            
            Divider()
                .frame(height: 40)
            
            VStack(spacing: 4) {
                Text("\(stats.postsToday)")
                    .font(OlasDesign.Typography.title)
                    .foregroundColor(OlasDesign.Colors.text)
                Text("Today")
                    .font(OlasDesign.Typography.caption)
                    .foregroundColor(OlasDesign.Colors.textSecondary)
            }
            
            Divider()
                .frame(height: 40)
            
            VStack(spacing: 4) {
                Text("\(stats.uniqueAuthors)")
                    .font(OlasDesign.Typography.title)
                    .foregroundColor(OlasDesign.Colors.text)
                Text("Authors")
                    .font(OlasDesign.Typography.caption)
                    .foregroundColor(OlasDesign.Colors.textSecondary)
            }
        }
        .padding(OlasDesign.Spacing.md)
        .background(OlasDesign.Colors.surface)
        .cornerRadius(12)
    }
    
    @ViewBuilder
    private var postsGrid: some View {
        LazyVGrid(columns: columns, spacing: 1) {
            ForEach(posts, id: \.id) { post in
                HashtagGridItem(
                    post: post,
                    profile: profiles[post.pubkey]
                )
                .onAppear {
                    loadProfileIfNeeded(for: post.pubkey)
                }
            }
        }
        .padding(.horizontal, 1)
    }
    
    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: OlasDesign.Spacing.lg) {
            Image(systemName: "number.square")
                .font(.system(size: 60))
                .foregroundColor(OlasDesign.Colors.textTertiary)
            
            Text("No posts yet")
                .font(OlasDesign.Typography.title)
                .foregroundColor(OlasDesign.Colors.text)
            
            Text("Be the first to post with #\(hashtag)")
                .font(OlasDesign.Typography.body)
                .foregroundColor(OlasDesign.Colors.textSecondary)
        }
        .frame(minHeight: 300)
        .padding(OlasDesign.Spacing.xl)
    }
    
    private func loadHashtagPosts() async {
        guard let ndk = nostrManager.ndk else { return }
        
        // Create filter for posts containing this hashtag
        let filter = NDKFilter(
            kinds: [EventKind.textNote],
            limit: 100
        )
        
        Task {
            let dataSource = ndk.observe(filter: filter)
            let events = await dataSource.collect(timeout: 5.0)
            
            // Filter posts with hashtag and images
            let loadedPosts = events.filter { event in
                event.content.lowercased().contains("#\(hashtag.lowercased())") &&
                extractImageUrls(from: event.content).count > 0
            }
            
            // Calculate stats
            var uniqueAuthors = Set<String>()
            let today = Calendar.current.startOfDay(for: Date())
            var postsToday = 0
            
            for post in loadedPosts {
                uniqueAuthors.insert(post.pubkey)
                let eventDate = Date(timeIntervalSince1970: TimeInterval(post.createdAt))
                if eventDate >= today {
                    postsToday += 1
                }
            }
            
            await MainActor.run {
                self.posts = Array(loadedPosts.prefix(50))
                self.stats = HashtagStats(
                    totalPosts: loadedPosts.count,
                    postsToday: postsToday,
                    uniqueAuthors: uniqueAuthors.count
                )
                isLoading = false
            }
        }
    }
    
    private func loadProfileIfNeeded(for pubkey: String) {
        guard profiles[pubkey] == nil,
              let ndk = nostrManager.ndk,
              let profileManager = ndk.profileManager else { return }
        
        Task {
            for await profile in await profileManager.observe(for: pubkey, maxAge: 3600) {
                await MainActor.run {
                    profiles[pubkey] = profile
                }
                break
            }
        }
    }
    
    private func extractImageUrls(from content: String) -> [String] {
        let pattern = "(https?://[^\\s]+\\.(jpg|jpeg|png|gif|webp)[^\\s]*)"
        let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        let matches = regex?.matches(in: content, options: [], range: NSRange(content.startIndex..., in: content)) ?? []
        
        return matches.compactMap { match in
            guard let range = Range(match.range, in: content) else { return nil }
            return String(content[range])
        }
    }
}

struct HashtagGridItem: View {
    let post: NDKEvent
    let profile: NDKUserProfile?
    
    @State private var imageUrls: [String] = []
    
    var body: some View {
        NavigationLink(destination: PostDetailView(event: post)) {
            GeometryReader { geometry in
                if let firstImageUrl = imageUrls.first,
                   let url = URL(string: firstImageUrl) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            Rectangle()
                                .fill(OlasDesign.Colors.surface)
                                .overlay(ShimmerView())
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: geometry.size.width, height: geometry.size.width)
                                .clipped()
                        case .failure:
                            ZStack {
                                OlasDesign.Colors.surface
                                Image(systemName: "photo")
                                    .foregroundColor(OlasDesign.Colors.textTertiary)
                            }
                        @unknown default:
                            Rectangle()
                                .fill(OlasDesign.Colors.surface)
                        }
                    }
                } else {
                    ZStack {
                        OlasDesign.Colors.surface
                        Image(systemName: "photo")
                            .foregroundColor(OlasDesign.Colors.textTertiary)
                    }
                }
            }
            .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            imageUrls = extractImageUrls(from: post.content)
        }
    }
    
    private func extractImageUrls(from content: String) -> [String] {
        let pattern = "(https?://[^\\s]+\\.(jpg|jpeg|png|gif|webp)[^\\s]*)"
        let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        let matches = regex?.matches(in: content, options: [], range: NSRange(content.startIndex..., in: content)) ?? []
        
        return matches.compactMap { match in
            guard let range = Range(match.range, in: content) else { return nil }
            return String(content[range])
        }
    }
}