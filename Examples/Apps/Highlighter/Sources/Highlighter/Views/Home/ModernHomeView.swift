import SwiftUI
import NDKSwift

struct ModernHomeView: View {
    @EnvironmentObject var appState: AppState
    @State private var highlights: [HighlightEvent] = []
    @State private var highlightedArticles: [HighlightedArticle] = []
    @State private var discussions: [NDKEvent] = []
    @State private var zappedArticles: [NDKEvent] = []
    @State private var userHighlights: [HighlightEvent] = []
    @State private var refreshing = false
    @Binding var tabBarVisible: Bool
    @State private var scrollOffset: CGFloat = 0
    
    struct HighlightedArticle {
        let article: Article
        let highlights: [HighlightEvent]
        let lastHighlightTime: Date
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
                        if !highlightedArticles.isEmpty {
                            VStack(spacing: .ds.itemSpacing) {
                                ModernSectionHeader(
                                    title: "Recently Highlighted Articles",
                                    action: {},
                                    actionTitle: "See All"
                                )
                                
                                VStack(spacing: .ds.base) {
                                    ForEach(highlightedArticles.prefix(10), id: \.article.id) { highlightedArticle in
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
                        
                        // Featured highlight - if user has recent highlights
                        if !userHighlights.isEmpty {
                            FeaturedHighlightCard(highlight: userHighlights.first!)
                                .padding(.horizontal, .ds.screenPadding)
                        }
                        
                        // Active discussions
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
                        
                        // Community activity
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
                    await refreshContent()
                }
            }
            .background(DesignSystem.Colors.background)
            .navigationBarHidden(true)
        }
        .task {
            await streamContent()
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
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }
    
    private var formattedDate: String {
        Date().formatted(.dateTime.weekday(.wide).month(.wide).day())
    }
    
    private func refreshContent() async {
        refreshing = true
        HapticManager.shared.impact(.light)
        
        highlights.removeAll()
        discussions.removeAll()
        zappedArticles.removeAll()
        
        await streamContent()
        
        HapticManager.shared.notification(.success)
        refreshing = false
    }
    
    private func streamContent() async {
        guard let ndk = appState.ndk else { return }
        
        // Stream highlights and build article relationships
        Task {
            let highlightSource = ndk.observe(
                filter: NDKFilter(kinds: [9802], limit: 50),
                maxAge: 300,
                cachePolicy: .cacheWithNetwork
            )
            
            var articleReferences: Set<String> = []
            var highlightsByArticle: [String: [HighlightEvent]] = [:]
            
            for await event in highlightSource.events {
                if let highlight = try? HighlightEvent(from: event) {
                    await MainActor.run {
                        withAnimation(DesignSystem.Animation.quick) {
                            if !highlights.contains(where: { $0.id == highlight.id }) {
                                highlights.append(highlight)
                                highlights.sort { $0.createdAt > $1.createdAt }
                                
                                // Track article references
                                if let ref = highlight.referencedEvent {
                                    articleReferences.insert(ref)
                                    if highlightsByArticle[ref] != nil {
                                        highlightsByArticle[ref]?.append(highlight)
                                    } else {
                                        highlightsByArticle[ref] = [highlight]
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            // Fetch referenced articles
            if !articleReferences.isEmpty {
                await fetchHighlightedArticles(references: Array(articleReferences), highlightsByArticle: highlightsByArticle)
            }
        }
        
        // Stream user's highlights
        if let signer = appState.activeSigner {
            Task {
                if let userPubkey = try? await signer.pubkey {
                    let userHighlightSource = ndk.observe(
                        filter: NDKFilter(
                            authors: [userPubkey],
                            kinds: [9802],
                            limit: 5
                        ),
                        maxAge: 3600
                    )
                    
                    for await event in userHighlightSource.events {
                        if let highlight = try? HighlightEvent(from: event) {
                            await MainActor.run {
                                withAnimation(DesignSystem.Animation.quick) {
                                    if !userHighlights.contains(where: { $0.id == highlight.id }) {
                                        userHighlights.append(highlight)
                                        userHighlights.sort { $0.createdAt > $1.createdAt }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        
        // Stream discussions
        Task {
            let discussionSource = ndk.observe(
                filter: NDKFilter(kinds: [1], limit: 10, tags: ["t": Set(["bookstr"])]),
                maxAge: 300,
                cachePolicy: .cacheWithNetwork
            )
            
            for await event in discussionSource.events {
                await MainActor.run {
                    withAnimation(DesignSystem.Animation.quick) {
                        if !discussions.contains(where: { $0.id == event.id }) {
                            discussions.append(event)
                            discussions.sort { $0.createdAt > $1.createdAt }
                        }
                    }
                }
            }
        }
        
        // Stream zap activity
        Task {
            let zapSource = ndk.observe(
                filter: NDKFilter(kinds: [9735], limit: 10),
                maxAge: 300,
                cachePolicy: .cacheWithNetwork
            )
            
            for await event in zapSource.events {
                await MainActor.run {
                    withAnimation(DesignSystem.Animation.quick) {
                        if !zappedArticles.contains(where: { $0.id == event.id }) {
                            zappedArticles.append(event)
                        }
                    }
                }
            }
        }
    }
    
    private func fetchHighlightedArticles(references: [String], highlightsByArticle: [String: [HighlightEvent]]) async {
        guard let ndk = appState.ndk else { return }
        
        // Parse references to extract article IDs
        var articleFilters: [NDKFilter] = []
        
        for reference in references {
            if reference.contains(":") {
                // This is an "a" tag reference (kind:pubkey:d-tag)
                let parts = reference.split(separator: ":")
                if parts.count >= 3,
                   let kind = Int32(parts[0]) {
                    articleFilters.append(NDKFilter(
                        kinds: [kind],
                        authors: [String(parts[1])],
                        tags: ["d": Set([String(parts[2])])]
                    ))
                }
            } else {
                // This is an "e" tag reference (event ID)
                articleFilters.append(NDKFilter(ids: [reference]))
            }
        }
        
        // Fetch articles
        for filter in articleFilters {
            let events = await ndk.fetchEvents(filter)
            for event in events {
                if event.kind == 30023,
                   let article = try? Article(from: event),
                   let highlights = highlightsByArticle[event.id] ?? highlightsByArticle["\(event.kind):\(event.pubkey):\(article.identifier ?? "")"] {
                    
                    let lastHighlight = highlights.max(by: { $0.createdAt < $1.createdAt })
                    
                    await MainActor.run {
                        withAnimation(DesignSystem.Animation.quick) {
                            let highlightedArticle = HighlightedArticle(
                                article: article,
                                highlights: highlights,
                                lastHighlightTime: lastHighlight?.createdAt ?? Date()
                            )
                            
                            if !highlightedArticles.contains(where: { $0.article.id == article.id }) {
                                highlightedArticles.append(highlightedArticle)
                                highlightedArticles.sort { $0.lastHighlightTime > $1.lastHighlightTime }
                            }
                        }
                    }
                }
            }
        }
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
                    HapticManager.shared.impact(.light)
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
        String(pubkey.prefix(8)) + "..."
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
                    Text(String(event.pubkey.prefix(1)).uppercased())
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
        String(pubkey.prefix(8))
    }
    
    private func relativeTime(from timestamp: Timestamp) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
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
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
