import SwiftUI
import NDKSwift

struct ExploreView: View {
    @Environment(NostrManager.self) private var nostrManager
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = ExploreViewModel()
    @State private var selectedCategory: ExploreCategory = .trending
    @State private var showingHashtagView = false
    @State private var selectedHashtag = ""
    
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
                        // Search bar - navigates to dedicated search view
                        NavigationLink(destination: SearchView()) {
                            searchBarButton
                        }
                        .padding(.horizontal, OlasDesign.Spacing.md)
                        .padding(.top, OlasDesign.Spacing.sm)
                        .padding(.bottom, OlasDesign.Spacing.md)
                        
                        // Category pills
                        categoryPills
                            .padding(.bottom, OlasDesign.Spacing.md)
                        
                        // Trending hashtags (only show for trending category)
                        if selectedCategory == .trending && !viewModel.trendingHashtags.isEmpty {
                            trendingHashtagsView
                                .padding(.bottom, OlasDesign.Spacing.md)
                        }
                        
                        // Content
                        if viewModel.isLoading {
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
                if let ndk = nostrManager.ndk {
                    viewModel.startObserving(ndk: ndk, category: selectedCategory)
                }
            }
            .onChange(of: selectedCategory) { _, newCategory in
                if let ndk = nostrManager.ndk {
                    viewModel.changeCategory(to: newCategory, ndk: ndk)
                }
            }
            .sheet(isPresented: $showingHashtagView) {
                HashtagView(hashtag: selectedHashtag)
                    .environmentObject(appState)
                    .environment(nostrManager)
            }
        }
    }
    
    // MARK: - Views
    
    @ViewBuilder
    private var searchBarButton: some View {
        HStack(spacing: OlasDesign.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(OlasDesign.Colors.textSecondary)
                .font(.body)
            
            Text("Search posts, hashtags, or users")
                .font(OlasDesign.Typography.body)
                .foregroundColor(OlasDesign.Colors.textSecondary)
            
            Spacer()
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
                    ForEach(viewModel.trendingHashtags) { hashtag in
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
            ForEach(Array(filteredPosts.enumerated()), id: \.element.id) { index, item in
                ExploreGridItem(
                    post: item.event,
                    profile: item.profile,
                    height: gridHeights[index % gridHeights.count]
                )
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
    
    private var filteredPosts: [ExploreItem] {
        viewModel.items
    }
    
    // Random heights for masonry effect
    private let gridHeights: [CGFloat] = [
        180, 220, 200, 240, 190, 210, 230, 195, 215, 225
    ]
}

// MARK: - View Model

@MainActor
class ExploreViewModel: ObservableObject {
    @Published var items: [ExploreItem] = []
    @Published var trendingHashtags: [ExploreView.TrendingHashtag] = []
    @Published var isLoading = false
    
    private var exploreTask: Task<Void, Never>?
    private var profileTasks: [String: Task<Void, Never>] = [:]
    
    func startObserving(ndk: NDK, category: ExploreView.ExploreCategory) {
        // Cancel existing task
        exploreTask?.cancel()
        
        isLoading = true
        
        exploreTask = Task {
            // Create filter based on category
            var filter: NDKFilter
            
            if category == .trending {
                // For trending, get both kind 20 (picture posts) and kind 1 with images
                filter = NDKFilter(kinds: [20, 1], limit: 200)
            } else {
                // For specific categories, filter by hashtag
                filter = NDKFilter(
                    kinds: [20, 1],
                    limit: 100,
                    tags: ["t": Set([category.hashtag])]
                )
            }
            
            // Create data source with reactive pattern
            let dataSource = ndk.observe(
                filter: filter,
                maxAge: 0,  // Real-time updates
                cachePolicy: .cacheWithNetwork
            )
            
            for await event in dataSource.events {
                // Check if has images
                let imageUrls: [String]
                if event.kind == 20 {
                    imageUrls = ExploreItem.extractImagesFromTags(event.tags)
                } else {
                    imageUrls = ExploreItem.extractImageURLs(from: event.content)
                }
                
                if !imageUrls.isEmpty {
                    let item = ExploreItem(event: event, imageUrls: imageUrls)
                    
                    await MainActor.run {
                        // Insert sorted by timestamp
                        if let insertIndex = items.firstIndex(where: { $0.event.createdAt < event.createdAt }) {
                            items.insert(item, at: insertIndex)
                        } else {
                            items.append(item)
                        }
                        
                        // Limit items for performance
                        if items.count > 100 {
                            items.removeLast(items.count - 100)
                        }
                        
                        isLoading = false
                    }
                    
                    // Load profile reactively
                    loadProfileReactively(for: event.pubkey, ndk: ndk)
                }
            }
        }
        
        // Load trending hashtags for trending category
        if category == .trending {
            loadTrendingHashtags()
        }
    }
    
    func changeCategory(to category: ExploreView.ExploreCategory, ndk: NDK) {
        // Clear existing items
        items.removeAll()
        trendingHashtags.removeAll()
        
        // Cancel existing tasks
        exploreTask?.cancel()
        profileTasks.values.forEach { $0.cancel() }
        profileTasks.removeAll()
        
        // Start new observation
        startObserving(ndk: ndk, category: category)
    }
    
    private func loadProfileReactively(for pubkey: String, ndk: NDK) {
        // Cancel existing task if any
        profileTasks[pubkey]?.cancel()
        
        profileTasks[pubkey] = Task {
            guard let profileManager = ndk.profileManager else { return }
            
            for await profile in await profileManager.observe(for: pubkey, maxAge: 3600) {
                if let profile = profile {
                    await MainActor.run {
                        updateItemsWithProfile(pubkey: pubkey, profile: profile)
                    }
                }
            }
        }
    }
    
    private func updateItemsWithProfile(pubkey: String, profile: NDKUserProfile) {
        for index in items.indices {
            if items[index].event.pubkey == pubkey {
                items[index].profile = profile
            }
        }
    }
    
    private func loadTrendingHashtags() {
        // For now, use mock data
        // In a real implementation, this would analyze recent posts
        trendingHashtags = [
            ExploreView.TrendingHashtag(tag: "photography", count: 1234, velocity: 45.2),
            ExploreView.TrendingHashtag(tag: "nostr", count: 892, velocity: 38.7),
            ExploreView.TrendingHashtag(tag: "art", count: 756, velocity: 28.3),
            ExploreView.TrendingHashtag(tag: "bitcoin", count: 623, velocity: 22.1),
            ExploreView.TrendingHashtag(tag: "nature", count: 489, velocity: 18.5)
        ]
    }
}

// MARK: - Data Models

struct ExploreItem: Identifiable {
    let id: String
    let event: NDKEvent
    let imageUrls: [String]
    var profile: NDKUserProfile?
    
    init(event: NDKEvent, imageUrls: [String]) {
        self.id = event.id
        self.event = event
        self.imageUrls = imageUrls
    }
    
    static func extractImageURLs(from content: String) -> [String] {
        let pattern = "(https?://[^\\s]+\\.(jpg|jpeg|png|gif|webp)[^\\s]*)"
        let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        let matches = regex?.matches(in: content, options: [], range: NSRange(content.startIndex..., in: content)) ?? []
        
        return matches.compactMap { match in
            guard let range = Range(match.range, in: content) else { return nil }
            return String(content[range])
        }
    }
    
    static func extractImagesFromTags(_ tags: [[String]]) -> [String] {
        var imageURLs: [String] = []
        
        // Look for imeta tags (NIP-92)
        for tag in tags {
            if tag.count >= 2 && tag[0] == "imeta" {
                // Parse imeta tag values
                for i in 1..<tag.count {
                    let parts = tag[i].components(separatedBy: " ")
                    for part in parts {
                        if part.hasPrefix("url=") {
                            let url = String(part.dropFirst(4))
                            imageURLs.append(url)
                        }
                    }
                }
            }
        }
        
        // Fallback: look for regular URL tags
        if imageURLs.isEmpty {
            for tag in tags {
                if tag.count >= 2 && tag[0] == "r" && isImageURL(tag[1]) {
                    imageURLs.append(tag[1])
                }
            }
        }
        
        return imageURLs
    }
    
    private static func isImageURL(_ url: String) -> Bool {
        let imageExtensions = [".jpg", ".jpeg", ".png", ".gif", ".webp", ".heic"]
        let lowercasedURL = url.lowercased()
        
        // Check for direct image extensions
        if imageExtensions.contains(where: { lowercasedURL.contains($0) }) {
            return true
        }
        
        // Check for image hosting services
        let imageHosts = ["imgur.com", "i.imgur.com", "nostr.build", "void.cat", "imgprxy.stacker.news"]
        return imageHosts.contains(where: { lowercasedURL.contains($0) })
    }
}