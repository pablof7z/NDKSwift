import SwiftUI
import NDKSwift

// Make NDKEvent conform to Identifiable for SwiftUI usage
extension NDKEvent: @retroactive Identifiable {}

struct SimplifiedHybridFeedView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var dataManager = HomeDataManager()
    @State private var selectedSection = 0
    @State private var scrollOffset: CGFloat = 0
    @State private var headerOpacity: Double = 1
    @State private var highlightEngagements: [String: EngagementService.EngagementMetrics] = [:]
    @State private var discussionEngagements: [String: EngagementService.EngagementMetrics] = [:]
    
    // Dynamic gradient colors that shift based on time of day
    private var gradientColors: [Color] {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: // Morning
            return [Color(hex: "FFE5B4"), Color(hex: "FFD700").opacity(0.3)]
        case 12..<17: // Afternoon
            return [Color(hex: "87CEEB").opacity(0.3), Color(hex: "4682B4").opacity(0.2)]
        case 17..<21: // Evening
            return [Color(hex: "FF6B6B").opacity(0.3), Color(hex: "FF8E53").opacity(0.2)]
        default: // Night
            return [Color(hex: "2C3E50").opacity(0.3), Color(hex: "34495E").opacity(0.2)]
        }
    }
    
    // MARK: - Engagement Fetching
    private func fetchHighlightEngagements() async {
        let eventIds = dataManager.userHighlights.map { $0.id }
        guard !eventIds.isEmpty else { return }
        
        let engagements = await appState.engagementService.fetchEngagementBatch(for: eventIds)
        await MainActor.run {
            highlightEngagements = engagements
        }
    }
    
    private func fetchDiscussionEngagements() async {
        let eventIds = dataManager.discussions.prefix(10).map { $0.id }
        guard !eventIds.isEmpty else { return }
        
        let engagements = await appState.engagementService.fetchEngagementBatch(for: eventIds)
        await MainActor.run {
            discussionEngagements = engagements
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                // Animated gradient background
                LinearGradient(
                    colors: gradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                .opacity(0.3)
                .animation(.easeInOut(duration: 3), value: gradientColors)
                
                ScrollViewReader { scrollProxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 0) {
                            // Parallax header with live indicator
                            headerView
                                .padding(.horizontal, 20)
                                .padding(.top, 16)
                                .offset(y: scrollOffset * 0.5)
                                .opacity(headerOpacity)
                                .id("header")
                            
                            
                            VStack(spacing: 32) {
                                // Recently Highlighted Articles
                                if !dataManager.highlightedArticles.isEmpty {
                                    recentlyHighlightedSection
                                }
                                
                                // Featured Highlights with enhanced carousel
                                if !dataManager.userHighlights.isEmpty {
                                    enhancedCarouselSection(
                                        title: "Featured Highlights",
                                        subtitle: "Top highlights from your network",
                                        items: dataManager.userHighlights,
                                        icon: "sparkle"
                                    ) { highlight in
                                        EnhancedHighlightCard(
                                            highlight: highlight,
                                            engagement: highlightEngagements[highlight.id] ?? EngagementService.EngagementMetrics()
                                        )
                                    }
                                } else {
                                    // Loading state with skeleton UI
                                    carouselLoadingState(title: "Featured Highlights")
                                }
                                
                                // Active Discussions
                                if !dataManager.discussions.isEmpty {
                                    enhancedDiscussionsSection
                                }
                            }
                            .padding(.top, 24)
                        }
                        .padding(.bottom, 100)
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
                        withAnimation(.easeOut(duration: 0.2)) {
                            headerOpacity = min(1.0, max(0.0, (50.0 + value) / 50.0))
                        }
                    }
                    .refreshable {
                        HapticManager.shared.impact(.medium)
                        await dataManager.refresh()
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            dataManager.appState = appState
        }
        .task {
            await dataManager.startStreaming()
        }
        .onChange(of: dataManager.userHighlights) { _ in
            Task {
                await fetchHighlightEngagements()
            }
        }
        .onChange(of: dataManager.discussions) { _ in
            Task {
                await fetchDiscussionEngagements()
            }
        }
    }
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Text(GreetingFormatter.timeBasedGreeting())
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundColor(.ds.text)
                    
                    // Time-based emoji without pulsing animation
                    Text(timeBasedEmoji)
                        .font(.system(size: 28))
                }
                
                HStack(spacing: 6) {
                    Text(GreetingFormatter.formattedDate())
                        .font(.ds.footnote)
                        .foregroundColor(.ds.textSecondary)
                    
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    
                    Text("Live")
                        .font(.ds.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.green)
                }
            }
            
            Spacer()
            
            // Activity indicator
            ActivityRing()
                .frame(width: 48, height: 48)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var timeBasedEmoji: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "☀️"
        case 12..<17: return "🌤"
        case 17..<21: return "🌅"
        default: return "🌙"
        }
    }
    
    private func enhancedCarouselSection<Item: Identifiable, Content: View>(
        title: String,
        subtitle: String? = nil,
        items: [Item],
        icon: String? = nil,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    if let icon = icon {
                        Image(systemName: icon)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.ds.primary)
                    }
                    
                    Text(title)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.ds.text)
                }
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.ds.footnote)
                        .foregroundColor(.ds.textSecondary)
                }
            }
            .padding(.horizontal, 20)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    ForEach(items) { item in
                        content(item)
                            .frame(width: 300)
                            .transition(.asymmetric(
                                insertion: .scale.combined(with: .opacity),
                                removal: .scale.combined(with: .opacity)
                            ))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4) // For shadows
            }
        }
    }
    
    private func carouselLoadingState(title: String) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.ds.text)
                .padding(.horizontal, 20)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.ds.surfaceSecondary)
                            .frame(width: 300, height: 200)
                            .shimmer()
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }
    
    private var recentlyHighlightedSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Recently Highlighted")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.ds.text)
                
                Text("Articles you might enjoy")
                    .font(.ds.body)
                    .foregroundColor(.ds.textSecondary)
            }
            .padding(.horizontal, 20)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(dataManager.highlightedArticles.prefix(5), id: \.article.id) { highlightedArticle in
                        NavigationLink(destination: ArticleView(article: highlightedArticle.article)) {
                            RecentlyHighlightedArticleCard(highlightedArticle: highlightedArticle)
                                .frame(width: 280)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }
        }
    }
    
    private var enhancedDiscussionsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.ds.primary)
                        
                        Text("Active Discussions")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(.ds.text)
                    }
                    
                    Text("\(dataManager.discussions.count) conversations happening now")
                        .font(.ds.footnote)
                        .foregroundColor(.ds.textSecondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
            
            VStack(spacing: 0) {
                ForEach(dataManager.discussions.prefix(5), id: \.id) { event in
                    EnhancedDiscussionRow(
                        event: event,
                        engagement: discussionEngagements[event.id] ?? EngagementService.EngagementMetrics()
                    )
                    
                    if event.id != dataManager.discussions.prefix(5).last?.id {
                        Divider()
                            .background(Color.ds.divider)
                            .padding(.leading, 60)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.ds.surfaceSecondary)
                    .shadow(color: Color.black.opacity(0.05), radius: 10, y: 5)
            )
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Enhanced Cards

struct EnhancedHighlightCard: View {
    let highlight: HighlightEvent
    let engagement: EngagementService.EngagementMetrics
    @State private var isPressed = false
    @State private var showingDetail = false
    
    var body: some View {
        Button(action: { showingDetail = true }) {
            ZStack {
                // Gradient background
                LinearGradient(
                    colors: [
                        Color.ds.primary.opacity(0.15),
                        Color.ds.primary.opacity(0.05)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                
                VStack(alignment: .leading, spacing: 16) {
                    // Source info if available
                    if let url = highlight.url {
                        HStack(spacing: 8) {
                            Image(systemName: "link.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.ds.primary)
                            
                            Text(ContentFormatter.extractDomain(from: url))
                                .font(.ds.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.ds.primary)
                                .lineLimit(1)
                            
                            Spacer()
                        }
                    }
                    
                    // Quote text with stylish quotes
                    HStack(alignment: .top, spacing: 12) {
                        Text("\"")
                            .font(.system(size: 36, weight: .black, design: .serif))
                            .foregroundColor(.ds.primary.opacity(0.3))
                            .offset(y: -8)
                        
                        Text(highlight.content)
                            .font(.system(size: 18, weight: .medium, design: .rounded))
                            .foregroundColor(.ds.text)
                            .lineLimit(4)
                            .multilineTextAlignment(.leading)
                        
                        Spacer(minLength: 0)
                    }
                    
                    Spacer()
                    
                    // Footer with interactions
                    HStack {
                        // Time and author
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color.ds.primary.opacity(0.2))
                                .frame(width: 24, height: 24)
                                .overlay(
                                    Text(PubkeyFormatter.formatForAvatar(highlight.author))
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.ds.primary)
                                )
                            
                            Text(RelativeTimeFormatter.relativeTime(from: highlight.createdAt ?? Date()))
                                .font(.ds.caption)
                                .foregroundColor(.ds.textSecondary)
                        }
                        
                        Spacer()
                        
                        // Interaction buttons
                        HStack(spacing: 16) {
                            InteractionButton(icon: "heart", count: engagement.likes)
                            InteractionButton(icon: "bubble.right", count: engagement.comments)
                            InteractionButton(icon: "bolt.fill", count: engagement.zaps, color: .orange)
                        }
                    }
                }
                .padding(24)
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Color.black.opacity(0.08), radius: 16, y: 8)
            .scaleEffect(isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
        }
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: 0.1, maximumDistance: .infinity, pressing: { pressing in
            isPressed = pressing
            if pressing {
                HapticManager.shared.impact(.light)
            }
        }, perform: {})
        .sheet(isPresented: $showingDetail) {
            HighlightDetailView(highlight: highlight)
        }
    }
}


struct EnhancedDiscussionRow: View {
    let event: NDKEvent
    let engagement: EngagementService.EngagementMetrics
    @State private var author: NDKUserProfile?
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar with online indicator
            ZStack(alignment: .bottomTrailing) {
                AsyncProfileImage(pubkey: event.pubkey, size: 44)
                
                Circle()
                    .fill(Color.green)
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle()
                            .stroke(Color.ds.background, lineWidth: 2)
                    )
            }
            
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(author?.displayName ?? PubkeyFormatter.formatCompact(event.pubkey))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.ds.text)
                    
                    Text("·")
                        .foregroundColor(.ds.textTertiary)
                    
                    Text(RelativeTimeFormatter.shortRelativeTime(from: event.createdAt))
                        .font(.ds.caption)
                        .foregroundColor(.ds.textTertiary)
                    
                    Spacer()
                    
                    if Bool.random() {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.blue)
                    }
                }
                
                Text(event.content)
                    .font(.system(size: 14))
                    .foregroundColor(.ds.text)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                
                // Engagement row with real metrics
                HStack(spacing: 20) {
                    EngagementButton(icon: "bubble.right", count: engagement.comments)
                    EngagementButton(icon: "arrow.2.squarepath", count: engagement.reposts)
                    EngagementButton(icon: "heart", count: engagement.likes)
                    EngagementButton(icon: "bolt.fill", count: engagement.zaps, color: .orange)
                }
                .padding(.top, 4)
            }
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Supporting Components

struct RecentlyHighlightedArticleCard: View {
    let highlightedArticle: HomeDataManager.HighlightedArticle
    @State private var isPressed = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Article thumbnail/gradient
            ZStack(alignment: .bottom) {
                // Background image or gradient
                if let imageUrl = highlightedArticle.article.image {
                    AsyncImage(url: URL(string: imageUrl)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(height: 180)
                                .clipped()
                        case .empty, .failure:
                            LinearGradient(
                                colors: [
                                    Color.ds.primary.opacity(0.8),
                                    Color.ds.primary.opacity(0.4)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            .frame(height: 180)
                        @unknown default:
                            EmptyView()
                        }
                    }
                } else {
                    LinearGradient(
                        colors: [
                            Color.ds.primary.opacity(0.8),
                            Color.ds.primary.opacity(0.4)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(height: 180)
                }
                
                // Overlay gradient for readability
                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.black.opacity(0.7)
                    ],
                    startPoint: .center,
                    endPoint: .bottom
                )
                
                // Article title
                VStack(alignment: .leading, spacing: 8) {
                    Text(highlightedArticle.article.title)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    if let summary = highlightedArticle.article.summary {
                        Text(summary)
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.8))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 180)
            
            // Bottom metadata
            VStack(alignment: .leading, spacing: 12) {
                // Author and time
                HStack(spacing: 8) {
                    AsyncProfileImage(pubkey: highlightedArticle.article.author, size: 24)
                    
                    Text(PubkeyFormatter.formatCompact(highlightedArticle.article.author))
                        .font(.ds.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.ds.text)
                    
                    Spacer()
                    
                    Text(highlightedArticle.article.estimatedReadingTime > 0 ? "\(highlightedArticle.article.estimatedReadingTime) min read" : "Quick read")
                        .font(.ds.caption)
                        .foregroundColor(.ds.textSecondary)
                }
                
                // Highlight count and sample
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "highlighter")
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                        
                        Text("\(highlightedArticle.highlights.count) highlight\(highlightedArticle.highlights.count == 1 ? "" : "s")")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.orange)
                        
                        Text("·")
                            .foregroundColor(.ds.textTertiary)
                        
                        Text(RelativeTimeFormatter.shortRelativeTime(from: highlightedArticle.lastHighlightTime))
                            .font(.system(size: 12))
                            .foregroundColor(.ds.textTertiary)
                    }
                    
                    // Show a preview of the most recent highlight
                    if let latestHighlight = highlightedArticle.highlights.first {
                        Text("\"\(latestHighlight.content.prefix(80))...\"")
                            .font(.system(size: 13, design: .serif))
                            .italic()
                            .foregroundColor(.ds.textSecondary)
                            .lineLimit(2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.ds.highlightSubtle.opacity(0.5))
                            )
                    }
                }
            }
            .padding(16)
            .background(Color.ds.surface)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.1), radius: 12, y: 6)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.ds.divider.opacity(0.5), lineWidth: 0.5)
        )
        .scaleEffect(isPressed ? 0.97 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
        .onLongPressGesture(minimumDuration: 0.1, maximumDistance: .infinity, pressing: { pressing in
            isPressed = pressing
            if pressing {
                HapticManager.shared.impact(.light)
            }
        }, perform: {})
    }
}


struct ActivityRing: View {
    @State private var progress: CGFloat = 0.75
    @State private var rotation: Double = 0
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.ds.surfaceSecondary, lineWidth: 4)
            
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    LinearGradient(
                        colors: [.ds.primary, .ds.primary.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .rotationEffect(.degrees(rotation))
                .animation(.linear(duration: 20).repeatForever(autoreverses: false), value: rotation)
            
            VStack(spacing: 0) {
                Text("\(Int(progress * 100))")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.ds.primary)
                Text("%")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.ds.textSecondary)
            }
        }
        .onAppear {
            rotation = 360
        }
    }
}


struct InteractionButton: View {
    let icon: String
    let count: Int
    var color: Color = .ds.textSecondary
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14))
            if count > 0 {
                Text(formatCount(count))
                    .font(.system(size: 12, weight: .medium))
            }
        }
        .foregroundColor(color)
    }
    
    private func formatCount(_ count: Int) -> String {
        if count >= 1000 {
            return "\(count / 1000)k"
        }
        return "\(count)"
    }
}

struct EngagementButton: View {
    let icon: String
    let count: Int
    var color: Color = .ds.textSecondary
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12))
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 11, weight: .medium))
            }
        }
        .foregroundColor(color)
    }
}

struct MetricPill: View {
    let icon: String
    let value: String
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12))
            Text(value)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundColor(.ds.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.ds.surfaceSecondary)
        )
    }
}

struct AsyncProfileImage: View {
    let pubkey: String
    let size: CGFloat
    
    var body: some View {
        // Placeholder implementation - would load actual profile image
        Circle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.ds.primary.opacity(0.6),
                        Color.ds.secondary.opacity(0.6)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
            .overlay(
                Text(PubkeyFormatter.formatForAvatar(pubkey))
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundColor(.white)
            )
    }
}


#Preview {
    SimplifiedHybridFeedView()
        .environmentObject(AppState())
}