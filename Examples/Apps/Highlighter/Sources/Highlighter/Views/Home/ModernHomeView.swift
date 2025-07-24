import SwiftUI
import NDKSwift

struct ModernHomeView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var dataManager: HomeDataManager
    @Binding var tabBarVisible: Bool
    @State private var scrollOffset: CGFloat = 0
    
    init(tabBarVisible: Binding<Bool>) {
        self._tabBarVisible = tabBarVisible
        // Initialize with placeholder - will be set properly in .onAppear
        self._dataManager = StateObject(wrappedValue: HomeDataManager(appState: AppState()))
    }
    
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: .ds.sectionSpacing) {
                        // Minimal header
                        headerView
                            .padding(.top, .ds.small)
                            .padding(.horizontal, .ds.screenPadding)
                        
                        // Recently Highlighted Articles Section
                        RecentlyHighlightedArticlesSection(articles: dataManager.highlightedArticles)
                        
                        // Featured highlight - if user has recent highlights
                        if !dataManager.userHighlights.isEmpty {
                            FeaturedHighlightCard(highlight: dataManager.userHighlights.first!)
                                .padding(.horizontal, .ds.screenPadding)
                        }
                        
                        // Active discussions
                        ActiveDiscussionsSection(discussions: dataManager.discussions)
                        
                        // Community activity
                        TrendingSection(zappedArticles: dataManager.zappedArticles)
                    }
                    .padding(.bottom, 100) // Space for tab bar
                    .background(GeometryReader { geo in
                        Color.clear.preference(
                            key: ScrollOffsetPreferenceKey.self,
                            value: geo.frame(in: .named("scroll")).minY
                        )
                    })
                }
                .coordinateSpace(name: "scroll")
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                    scrollOffset = value
                    withAnimation(DesignSystem.Animation.quick) {
                        tabBarVisible = value > -50
                    }
                }
                .refreshable {
                    await dataManager.refresh()
                }
            }
            .background(DesignSystem.Colors.background)
            .navigationBarHidden(true)
        }
        .onAppear {
            // Properly initialize data manager with the current app state
            dataManager.appState = appState
        }
        .task {
            await dataManager.startStreaming()
        }
    }
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: .ds.micro) {
                Text(greetingText)
                    .font(.ds.largeTitle)
                    .foregroundColor(.ds.text)
                
                Text(formattedDate)
                    .font(.ds.footnote)
                    .foregroundColor(.ds.textSecondary)
            }
            
            Spacer()
            
            Button(action: {}) {
                Image(systemName: "bell")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.ds.text)
                    .frame(width: 40, height: 40)
                    .background(DesignSystem.Colors.surfaceSecondary)
                    .clipShape(Circle())
            }
        }
    }
    
    private var greetingText: String {
        GreetingFormatter.timeBasedGreeting()
    }
    
    private var formattedDate: String {
        GreetingFormatter.formattedDate()
    }
    
}

// MARK: - Components

struct FeaturedHighlightCard: View {
    let highlight: HighlightEvent
    
    var body: some View {
        VStack(alignment: .leading, spacing: .ds.base) {
            HStack {
                Label("Your Recent Highlight", systemImage: "sparkle")
                    .font(.ds.footnoteMedium)
                    .foregroundColor(.ds.primary)
                Spacer()
            }
            
            Text("\"\(highlight.content)\"")
                .font(.ds.title3)
                .foregroundColor(.ds.text)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
            
            if let context = highlight.context {
                Text(context)
                    .font(.ds.footnote)
                    .foregroundColor(.ds.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(.ds.medium)
        .background(DesignSystem.Colors.primaryLight.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: .ds.large, style: .continuous))
    }
}

struct CompactHighlightCard: View {
    let highlight: HighlightEvent
    @State private var isLiked = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: .ds.small) {
            Text("\"\(highlight.content)\"")
                .font(.ds.callout)
                .foregroundColor(.ds.text)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
            
            Spacer()
            
            HStack {
                Text(formatAuthor(highlight.author))
                    .font(.ds.caption)
                    .foregroundColor(.ds.textSecondary)
                
                Spacer()
                
                Button(action: {
                    isLiked.toggle()
                    HapticManager.shared.impact(HapticManager.ImpactStyle.light)
                }) {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                        .font(.system(size: 14))
                        .foregroundColor(isLiked ? .ds.error : .ds.textTertiary)
                }
            }
        }
        .frame(height: 100)
        .modernCard()
    }
    
    private func formatAuthor(_ pubkey: String) -> String {
        PubkeyFormatter.formatShort(pubkey)
    }
}

struct DiscussionRow: View {
    let event: NDKEvent
    
    var body: some View {
        HStack(alignment: .top, spacing: .ds.base) {
            Circle()
                .fill(DesignSystem.Colors.surfaceSecondary)
                .frame(width: 36, height: 36)
                .overlay(
                    Text(PubkeyFormatter.formatForAvatar(event.pubkey))
                        .font(.ds.captionMedium)
                        .foregroundColor(.ds.textSecondary)
                )
            
            VStack(alignment: .leading, spacing: .ds.micro) {
                HStack {
                    Text(formatPubkey(event.pubkey))
                        .font(.ds.footnoteMedium)
                        .foregroundColor(.ds.text)
                    
                    Text("·")
                        .foregroundColor(.ds.textTertiary)
                    
                    Text(relativeTime(from: event.createdAt))
                        .font(.ds.caption)
                        .foregroundColor(.ds.textTertiary)
                }
                
                Text(event.content)
                    .font(.ds.body)
                    .foregroundColor(.ds.text)
                    .lineLimit(2)
            }
            
            Spacer(minLength: 0)
        }
    }
    
    private func formatPubkey(_ pubkey: String) -> String {
        PubkeyFormatter.formatCompact(pubkey)
    }
    
    private func relativeTime(from timestamp: Timestamp) -> String {
        RelativeTimeFormatter.relativeTime(from: timestamp)
    }
}

struct TrendingItemCard: View {
    let event: NDKEvent
    
    var body: some View {
        HStack(spacing: .ds.base) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 16))
                .foregroundColor(.ds.warning)
                .frame(width: 32, height: 32)
                .background(DesignSystem.Colors.warning.opacity(0.1))
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: .ds.micro) {
                Text("Article received zap")
                    .font(.ds.footnoteMedium)
                    .foregroundColor(.ds.text)
                
                Text("1,000 sats")
                    .font(.ds.caption)
                    .foregroundColor(.ds.textSecondary)
            }
            
            Spacer()
            
            Text(relativeTime(from: event.createdAt))
                .font(.ds.caption)
                .foregroundColor(.ds.textTertiary)
        }
        .modernCard()
    }
    
    private func relativeTime(from timestamp: Timestamp) -> String {
        RelativeTimeFormatter.shortRelativeTime(from: timestamp)
    }
}

// MARK: - Extracted Section Components

struct RecentlyHighlightedArticlesSection: View {
    let articles: [HomeDataManager.HighlightedArticle]
    
    var body: some View {
        if !articles.isEmpty {
            VStack(spacing: .ds.itemSpacing) {
                ModernSectionHeader(
                    title: "Recently Highlighted Articles",
                    action: {},
                    actionTitle: "See All"
                )
                
                VStack(spacing: .ds.base) {
                    ForEach(articles.prefix(10), id: \.article.id) { highlightedArticle in
                        HighlightedArticleCard(
                            article: highlightedArticle.article,
                            highlights: highlightedArticle.highlights
                        )
                    }
                }
                .padding(.horizontal, .ds.screenPadding)
            }
        } else {
            // Loading placeholders for articles
            VStack(spacing: .ds.itemSpacing) {
                ModernSectionHeader(title: "Recently Highlighted Articles")
                
                VStack(spacing: .ds.base) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: .ds.large)
                            .fill(DesignSystem.Colors.surfaceSecondary)
                            .frame(height: 200)
                            .modernPlaceholder()
                    }
                }
                .padding(.horizontal, .ds.screenPadding)
            }
        }
    }
}

struct ActiveDiscussionsSection: View {
    let discussions: [NDKEvent]
    
    var body: some View {
        if !discussions.isEmpty {
            VStack(spacing: .ds.itemSpacing) {
                ModernSectionHeader(title: "Active Discussions")
                
                VStack(spacing: 0) {
                    ForEach(discussions.prefix(5), id: \.id) { event in
                        DiscussionRow(event: event)
                            .modernListItem(showDivider: event.id != discussions.prefix(5).last?.id)
                    }
                }
                .modernCard(noPadding: true)
                .padding(.horizontal, .ds.screenPadding)
            }
        }
    }
}

struct TrendingSection: View {
    let zappedArticles: [NDKEvent]
    
    var body: some View {
        if !zappedArticles.isEmpty {
            VStack(spacing: .ds.itemSpacing) {
                ModernSectionHeader(title: "Trending")
                
                VStack(spacing: .ds.base) {
                    ForEach(zappedArticles.prefix(3), id: \.id) { event in
                        TrendingItemCard(event: event)
                    }
                }
                .padding(.horizontal, .ds.screenPadding)
            }
        }
    }
}

// ScrollOffsetPreferenceKey is already defined in HomeView.swift

struct HighlightedArticleCard: View {
    let article: Article
    let highlights: [HighlightEvent]
    @State private var isBookmarked = false
    
    var body: some View {
        NavigationLink(destination: ArticleView(article: article)) {
            VStack(alignment: .leading, spacing: .ds.base) {
                // Article header with image
                if let imageUrl = article.image {
                    AsyncImage(url: URL(string: imageUrl)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(height: 120)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: .ds.medium, style: .continuous))
                        case .empty, .failure:
                            RoundedRectangle(cornerRadius: .ds.medium, style: .continuous)
                                .fill(DesignSystem.Colors.surfaceSecondary)
                                .frame(height: 120)
                                .overlay(
                                    Image(systemName: "photo")
                                        .font(.system(size: 24))
                                        .foregroundColor(.ds.textTertiary)
                                )
                        @unknown default:
                            EmptyView()
                        }
                    }
                }
                
                // Article title and metadata
                VStack(alignment: .leading, spacing: .ds.small) {
                    Text(article.title)
                        .font(.ds.headline)
                        .foregroundColor(.ds.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    if let summary = article.summary {
                        Text(summary)
                            .font(.ds.callout)
                            .foregroundColor(.ds.textSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    
                    // Highlight count and recent highlight preview
                    VStack(alignment: .leading, spacing: .ds.micro) {
                        Label("\(highlights.count) highlight\(highlights.count == 1 ? "" : "s")", systemImage: "highlighter")
                            .font(.ds.footnoteMedium)
                            .foregroundColor(.ds.primary)
                        
                        if let recentHighlight = highlights.first {
                            Text("\"\(recentHighlight.content)\"")
                                .font(.ds.footnote)
                                .foregroundColor(.ds.textSecondary)
                                .italic()
                                .lineLimit(2)
                                .padding(.vertical, .ds.micro)
                                .padding(.horizontal, .ds.small)
                                .background(DesignSystem.Colors.highlightSubtle)
                                .clipShape(RoundedRectangle(cornerRadius: .ds.small, style: .continuous))
                        }
                    }
                    
                    // Footer with author and actions
                    HStack {
                        Text(formatAuthor(article.author))
                            .font(.ds.caption)
                            .foregroundColor(.ds.textTertiary)
                        
                        Text("·")
                            .foregroundColor(.ds.textTertiary)
                        
                        Text(relativeTime(from: Timestamp(article.createdAt.timeIntervalSince1970)))
                            .font(.ds.caption)
                            .foregroundColor(.ds.textTertiary)
                        
                        Spacer()
                        
                        Button(action: {
                            isBookmarked.toggle()
                            HapticManager.shared.impact(HapticManager.ImpactStyle.light)
                        }) {
                            Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                                .font(.system(size: 14))
                                .foregroundColor(isBookmarked ? .ds.primary : .ds.textTertiary)
                        }
                    }
                }
                .padding(.horizontal, .ds.base)
                .padding(.bottom, .ds.base)
            }
        }
        .modernCard(noPadding: true)
    }
    
    private func formatAuthor(_ pubkey: String) -> String {
        PubkeyFormatter.formatShort(pubkey)
    }
    
    private func relativeTime(from timestamp: Timestamp) -> String {
        RelativeTimeFormatter.relativeTime(from: timestamp)
    }
}
