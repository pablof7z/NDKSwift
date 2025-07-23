import SwiftUI
import NDKSwift

struct ExploreView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    @State private var selectedCategory: ExploreCategory = .trending
    @State private var posts: [NDKEvent] = []
    @State private var profiles: [String: NDKUserProfile] = [:]
    @State private var trendingHashtags: [TrendingHashtag] = []
    @State private var showingHashtagView = false
    @State private var selectedHashtag = ""
    @State private var isLoading = true
    
    private let columns = [
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1)
    ]
    
    enum ExploreCategory: String, CaseIterable {
        case trending = "Trending"
        case art = "Art"
        case photography = "Photography"
        case nature = "Nature"
        case portrait = "Portrait"
        case street = "Street"
        case landscape = "Landscape"
        case food = "Food"
        case architecture = "Architecture"
        
        var hashtag: String {
            switch self {
            case .trending: return ""
            case .art: return "art"
            case .photography: return "photography"
            case .nature: return "nature"
            case .portrait: return "portrait"
            case .street: return "streetphotography"
            case .landscape: return "landscape"
            case .food: return "foodphotography"
            case .architecture: return "architecture"
            }
        }
        
        var icon: String {
            switch self {
            case .trending: return "flame.fill"
            case .art: return "paintbrush.fill"
            case .photography: return "camera.fill"
            case .nature: return "leaf.fill"
            case .portrait: return "person.fill"
            case .street: return "building.2.fill"
            case .landscape: return "photo.fill"
            case .food: return "fork.knife"
            case .architecture: return "building.columns.fill"
            }
        }
    }
    
    struct TrendingHashtag: Identifiable {
        let id = UUID()
        let tag: String
        let count: Int
        let velocity: Double // posts per hour
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                OlasDesign.Colors.background
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 0) {
                        // Search bar
                        searchBar
                            .padding(.horizontal, OlasDesign.Spacing.md)
                            .padding(.top, OlasDesign.Spacing.sm)
                            .padding(.bottom, OlasDesign.Spacing.md)
                        
                        // Category pills
                        categoryPills
                            .padding(.bottom, OlasDesign.Spacing.md)
                        
                        // Trending hashtags (only show for trending category)
                        if selectedCategory == .trending && !trendingHashtags.isEmpty {
                            trendingHashtagsView
                                .padding(.bottom, OlasDesign.Spacing.md)
                        }
                        
                        // Content
                        if isLoading {
                            loadingView
                        } else if filteredPosts.isEmpty {
                            emptyStateView
                        } else {
                            masonryGrid
                        }
                    }
                }
            }
            .navigationTitle("Explore")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .task {
                await loadExploreContent()
            }
            .onChange(of: selectedCategory) { _, _ in
                Task {
                    await loadExploreContent()
                }
            }
            .sheet(isPresented: $showingHashtagView) {
                HashtagView(hashtag: selectedHashtag)
                    .environmentObject(appState)
            }
        }
    }
    
    // MARK: - Views
    
    @ViewBuilder
    private var searchBar: some View {
        HStack(spacing: OlasDesign.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(OlasDesign.Colors.textSecondary)
                .font(.body)
            
            TextField("Search posts, hashtags, or users", text: $searchText)
                .font(OlasDesign.Typography.body)
                .foregroundColor(OlasDesign.Colors.text)
                .submitLabel(.search)
                .onSubmit {
                    OlasDesign.Haptic.selection()
                }
        }
        .padding(OlasDesign.Spacing.md)
        .background(OlasDesign.Colors.surface)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(OlasDesign.Colors.border, lineWidth: 1)
        )
    }
    
    @ViewBuilder
    private var categoryPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: OlasDesign.Spacing.sm) {
                ForEach(ExploreCategory.allCases, id: \.self) { category in
                    CategoryPill(
                        category: category,
                        isSelected: selectedCategory == category,
                        action: {
                            withAnimation(.spring()) {
                                selectedCategory = category
                            }
                            OlasDesign.Haptic.selection()
                        }
                    )
                }
            }
            .padding(.horizontal, OlasDesign.Spacing.md)
        }
    }
    
    @ViewBuilder
    private var trendingHashtagsView: some View {
        VStack(alignment: .leading, spacing: OlasDesign.Spacing.sm) {
            Text("Trending Hashtags")
                .font(OlasDesign.Typography.bodyMedium)
                .foregroundColor(OlasDesign.Colors.text)
                .padding(.horizontal, OlasDesign.Spacing.md)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: OlasDesign.Spacing.sm) {
                    ForEach(trendingHashtags) { hashtag in
                        TrendingHashtagPill(
                            hashtag: hashtag,
                            action: {
                                selectedHashtag = hashtag.tag
                                showingHashtagView = true
                                OlasDesign.Haptic.selection()
                            }
                        )
                    }
                }
                .padding(.horizontal, OlasDesign.Spacing.md)
            }
        }
    }
    
    @ViewBuilder
    private var masonryGrid: some View {
        LazyVGrid(columns: columns, spacing: 1) {
            ForEach(Array(filteredPosts.enumerated()), id: \.element.id) { index, post in
                ExploreGridItem(
                    post: post,
                    profile: profiles[post.pubkey],
                    height: gridHeights[index % gridHeights.count]
                )
                .onAppear {
                    loadProfileIfNeeded(for: post.pubkey)
                }
            }
        }
        .padding(.horizontal, 1)
    }
    
    @ViewBuilder
    private var loadingView: some View {
        VStack(spacing: OlasDesign.Spacing.lg) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: OlasDesign.Colors.primary))
                .scaleEffect(1.5)
            
            Text("Discovering amazing content...")
                .font(OlasDesign.Typography.body)
                .foregroundColor(OlasDesign.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 400)
        .padding(OlasDesign.Spacing.xl)
    }
    
    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: OlasDesign.Spacing.lg) {
            Image(systemName: "photo.stack")
                .font(.system(size: 60))
                .foregroundStyle(
                    LinearGradient(
                        colors: [OlasDesign.Colors.primary, OlasDesign.Colors.secondary],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Text("No posts found")
                .font(OlasDesign.Typography.title)
                .foregroundColor(OlasDesign.Colors.text)
            
            Text("Try a different category or search term")
                .font(OlasDesign.Typography.body)
                .foregroundColor(OlasDesign.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 400)
        .padding(OlasDesign.Spacing.xl)
    }
    
    // MARK: - Data
    
    private var filteredPosts: [NDKEvent] {
        posts.filter { post in
            // Filter by search text
            if !searchText.isEmpty {
                let searchLower = searchText.lowercased()
                return post.content.lowercased().contains(searchLower)
            }
            return true
        }
    }
    
    // Random heights for masonry effect
    private let gridHeights: [CGFloat] = [
        180, 220, 200, 240, 190, 210, 230, 195, 215, 225
    ]
    
    // MARK: - Methods
    
    private func loadExploreContent() async {
        guard let ndk = appState.ndk else { return }
        
        await MainActor.run {
            isLoading = true
        }
        
        // Create filter based on category
        var filter = NDKFilter(kinds: [EventKind.textNote])
        
        if selectedCategory != .trending && !selectedCategory.hashtag.isEmpty {
            // For specific categories, we'd need to filter by hashtag
            // This would require parsing content for hashtags
        }
        
        filter.limit = 100
        
        // Fetch events
        Task {
            let dataSource = ndk.observe(filter: filter)
            let events = await dataSource.collect(timeout: 5.0)
            
            // Filter posts with images
            let loadedPosts = events.filter { event in
                extractImageUrls(from: event.content).count > 0
            }
            
            await MainActor.run {
                self.posts = Array(loadedPosts.prefix(50))
                isLoading = false
            }
            
            // Load trending hashtags for trending category
            if selectedCategory == .trending {
                await loadTrendingHashtags()
            }
        }
    }
    
    private func loadTrendingHashtags() async {
        // For now, use mock data
        // In a real implementation, this would analyze recent posts
        await MainActor.run {
            trendingHashtags = [
                TrendingHashtag(tag: "photography", count: 1234, velocity: 45.2),
                TrendingHashtag(tag: "nostr", count: 892, velocity: 38.7),
                TrendingHashtag(tag: "art", count: 756, velocity: 28.3),
                TrendingHashtag(tag: "bitcoin", count: 623, velocity: 22.1),
                TrendingHashtag(tag: "nature", count: 489, velocity: 18.5)
            ]
        }
    }
    
    private func loadProfileIfNeeded(for pubkey: String) {
        guard profiles[pubkey] == nil,
              let profileManager = appState.profileManager else { return }
        
        Task {
            for await profile in await profileManager.observe(for: pubkey) {
                await MainActor.run {
                    profiles[pubkey] = profile
                }
                break // Only need the first profile
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