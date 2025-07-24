import SwiftUI
import NDKSwift

struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @State private var highlights: [HighlightEvent] = []
    @State private var discussions: [NDKEvent] = []
    @State private var zappedArticles: [NDKEvent] = []
    @State private var oldHighlights: [HighlightEvent] = []
    @State private var refreshing = false
    @Binding var tabBarVisible: Bool
    @State private var scrollOffset: CGFloat = 0
    
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.sectionSpacing) {
                        // Header with gradient
                        headerSection
                            .id("top")
                        
                        // Personalized Recap Section - show immediately
                        PersonalizedRecapSection(highlights: oldHighlights)
                            .fadeSlide(isVisible: true, delay: 0.1)
                        
                        // Trending Quotes Carousel - stream in
                        TrendingQuotesSection(highlights: highlights)
                            .fadeSlide(isVisible: true, delay: 0.2)
                        
                        // Community Zaps Section - stream in
                        CommunityZapsSection(zappedArticles: zappedArticles)
                            .fadeSlide(isVisible: true, delay: 0.3)
                        
                        // Bookstr Discussions - stream in
                        BookstrDiscussionsSection(discussions: discussions)
                            .fadeSlide(isVisible: true, delay: 0.4)
                    }
                    .padding(.vertical, DesignSystem.Spacing.medium)
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
                        tabBarVisible = value > -50
                    }
                }
                .refreshable {
                    await refreshContent()
                }
            }
            .background(DesignSystem.Colors.background)
            .navigationTitle("Highlighter")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {}) {
                        Image(systemName: "bell")
                            .font(.system(size: 18))
                            .foregroundColor(DesignSystem.Colors.text)
                    }
                }
            }
        }
        .task {
            await streamContent()
        }
    }
    
    @ViewBuilder
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.micro) {
            Text(greetingText)
                .font(DesignSystem.Typography.title)
                .foregroundColor(DesignSystem.Colors.text)
            
            Text("Discover today's best ideas")
                .font(DesignSystem.Typography.body)
                .foregroundColor(DesignSystem.Colors.textSecondary)
        }
        .padding(.horizontal, DesignSystem.Spacing.screenPadding)
        .padding(.vertical, DesignSystem.Spacing.base)
    }
    
    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }
    
    private func refreshContent() async {
        refreshing = true
        HapticType.medium.trigger()
        
        // Clear and re-stream
        highlights.removeAll()
        discussions.removeAll()
        zappedArticles.removeAll()
        
        await streamContent()
        
        HapticType.success.trigger()
        refreshing = false
    }
    
    private func streamContent() async {
        guard let ndk = appState.ndk else { return }
        
        // Stream recent highlights with cache for immediate display
        Task {
            let highlightSource = ndk.observe(
                filter: NDKFilter(kinds: [9802], limit: 20),
                maxAge: 300, // 5 minute cache
                cachePolicy: .cacheWithNetwork
            )
            
            for await event in highlightSource.events {
                if let highlight = try? HighlightEvent(from: event) {
                    await MainActor.run {
                        withAnimation(DesignSystem.Animation.standard) {
                            if !highlights.contains(where: { $0.id == highlight.id }) {
                                highlights.append(highlight)
                                highlights.sort { $0.createdAt > $1.createdAt }
                            }
                        }
                    }
                }
            }
        }
        
        // Stream old highlights from user
        if let signer = appState.activeSigner {
            Task {
                if let userPubkey = try? await signer.pubkey {
                    let oldHighlightSource = ndk.observe(
                        filter: NDKFilter(
                            authors: [userPubkey],
                            kinds: [9802],
                            until: Timestamp(Date().timeIntervalSince1970 - 86400 * 7), // Last week
                            limit: 3
                        ),
                        maxAge: 3600 // 1 hour cache
                    )
                    
                    for await event in oldHighlightSource.events {
                        if let highlight = try? HighlightEvent(from: event) {
                            await MainActor.run {
                                withAnimation(DesignSystem.Animation.standard) {
                                    if !oldHighlights.contains(where: { $0.id == highlight.id }) {
                                        oldHighlights.append(highlight)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        
        // Stream bookstr discussions
        Task {
            let discussionSource = ndk.observe(
                filter: NDKFilter(kinds: [1], limit: 10, tags: ["t": Set(["bookstr"])]),
                maxAge: 300,
                cachePolicy: .cacheWithNetwork
            )
            
            for await event in discussionSource.events {
                await MainActor.run {
                    withAnimation(DesignSystem.Animation.standard) {
                        if !discussions.contains(where: { $0.id == event.id }) {
                            discussions.append(event)
                            discussions.sort { $0.createdAt > $1.createdAt }
                        }
                    }
                }
            }
        }
        
        // Stream zapped articles (kind 9735 zap receipts)
        Task {
            let zapSource = ndk.observe(
                filter: NDKFilter(kinds: [9735], limit: 10),
                maxAge: 300,
                cachePolicy: .cacheWithNetwork
            )
            
            for await event in zapSource.events {
                await MainActor.run {
                    withAnimation(DesignSystem.Animation.standard) {
                        if !zappedArticles.contains(where: { $0.id == event.id }) {
                            zappedArticles.append(event)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Enhanced Sections

struct PersonalizedRecapSection: View {
    let highlights: [HighlightEvent]
    @State private var selectedHighlight: HighlightEvent?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Your Recap")
                    .font(DesignSystem.Typography.title2)
                
                Spacer()
                
                if !highlights.isEmpty {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 16))
                        .foregroundColor(DesignSystem.Colors.primary)
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.screenPadding)
            
            if highlights.isEmpty {
                // Show placeholder while loading
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        ForEach(0..<2) { index in
                            RecapCardPlaceholder()
                                .fadeSlide(isVisible: true, delay: Double(index) * 0.1)
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.screenPadding)
                }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        ForEach(Array(highlights.enumerated()), id: \.element.id) { index, highlight in
                            RecapCard(
                                highlight: highlight,
                                isSelected: selectedHighlight?.id == highlight.id
                            )
                            .onTapGesture {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                    selectedHighlight = highlight
                                }
                                HapticType.selection.trigger()
                            }
                            .fadeSlide(isVisible: true, delay: Double(index) * 0.1)
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.screenPadding)
                }
            }
        }
    }
}

struct RecapCardPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 120, height: 14)
                
                Spacer()
            }
            
            VStack(spacing: 8) {
                ForEach(0..<3) { _ in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.15))
                        .frame(height: 16)
                }
            }
        }
        .padding(DesignSystem.Spacing.cardPadding)
        .glassBackground()
        .shimmer()
    }
}

struct RecapCard: View {
    let highlight: HighlightEvent
    let isSelected: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 14))
                    .foregroundColor(DesignSystem.Colors.primary)
                
                Text("You highlighted this last week")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                
                Spacer()
            }
            
            Text("\"\(highlight.content)\"")
                .font(DesignSystem.Typography.body)
                .foregroundColor(DesignSystem.Colors.text)
                .multilineTextAlignment(.leading)
                .lineLimit(isSelected ? nil : 3)
            
            HStack {
                if let url = highlight.url {
                    Link(destination: URL(string: url)!) {
                        Label("Source", systemImage: "link")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.primary)
                    }
                } else {
                    Label("Nostr", systemImage: "bolt.circle.fill")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.primary)
                }
                Spacer()
            }
        }
        .padding(DesignSystem.Spacing.cardPadding)
        .cardBackground(isSelected: isSelected)
    }
}

struct TrendingQuotesSection: View {
    let highlights: [HighlightEvent]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Trending Quotes")
                    .font(DesignSystem.Typography.title2)
                
                Spacer()
                
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 16))
                    .foregroundColor(DesignSystem.Colors.primary)
                    .pulse()
            }
            .padding(.horizontal, DesignSystem.Spacing.screenPadding)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    if highlights.isEmpty {
                        // Show placeholders while loading
                        ForEach(0..<3) { index in
                            QuoteCardPlaceholder()
                                .frame(width: 280)
                                .fadeSlide(isVisible: true, delay: Double(index) * 0.1)
                        }
                    } else {
                        ForEach(Array(highlights.prefix(10).enumerated()), id: \.element.id) { index, highlight in
                            QuoteCard(highlight: highlight)
                                .frame(width: 280)
                                .fadeSlide(isVisible: true, delay: Double(index) * 0.1)
                        }
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.screenPadding)
            }
        }
    }
}

struct QuoteCardPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 8) {
                ForEach(0..<4) { _ in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.15))
                        .frame(height: 16)
                }
            }
            
            Spacer()
            
            HStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 80, height: 14)
                
                Spacer()
            }
        }
        .frame(height: 160)
        .padding(DesignSystem.Spacing.cardPadding)
        .glassBackground()
        .shimmer()
    }
}

struct QuoteCard: View {
    let highlight: HighlightEvent
    @State private var isZapped = false
    @State private var isPressed = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("\"\(highlight.content)\"")
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(DesignSystem.Colors.text)
                .lineLimit(4)
                .multilineTextAlignment(.leading)
            
            Spacer()
            
            HStack {
                Text(formatAuthor(highlight.author))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                
                Spacer()
                
                Button(action: {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.5)) {
                        isZapped.toggle()
                    }
                    HapticType.light.trigger()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: isZapped ? "bolt.fill" : "bolt")
                            .rotateAndScale(isActive: isZapped)
                        
                        if isZapped {
                            Text("Zapped!")
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(isZapped ? .white : DesignSystem.Colors.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(isZapped ? AnyShapeStyle(LinearGradient(colors: [DesignSystem.Colors.primary, DesignSystem.Colors.primaryDark], startPoint: .topLeading, endPoint: .bottomTrailing)) : AnyShapeStyle(Color.clear))
                            .overlay(
                                Capsule()
                                    .stroke(DesignSystem.Colors.primary, lineWidth: 1)
                                    .opacity(isZapped ? 0 : 1)
                            )
                    )
                }
                .buttonStyle(PressButtonStyle())
            }
        }
        .frame(height: 160)
        .padding(DesignSystem.Spacing.cardPadding)
        .glassBackground()
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    isZapped ? AnyShapeStyle(LinearGradient(colors: [DesignSystem.Colors.primary, DesignSystem.Colors.primaryDark], startPoint: .topLeading, endPoint: .bottomTrailing)) : AnyShapeStyle(Color.clear),
                    lineWidth: 2
                )
                .opacity(isZapped ? 1 : 0)
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isZapped)
        )
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .onLongPressGesture(
            minimumDuration: 0.1,
            maximumDistance: .infinity,
            pressing: { pressing in
                withAnimation(.easeOut(duration: 0.2)) {
                    isPressed = pressing
                }
                if pressing {
                    HapticType.light.trigger()
                }
            },
            perform: {}
        )
    }
    
    private func formatAuthor(_ pubkey: String) -> String {
        String(pubkey.prefix(8)) + "..."
    }
}

struct CommunityZapsSection: View {
    let zappedArticles: [NDKEvent]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Community Zaps")
                    .font(DesignSystem.Typography.title2)
                
                Spacer()
                
                Image(systemName: "bolt.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(LinearGradient(colors: [DesignSystem.Colors.primary, DesignSystem.Colors.primaryDark], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .padding(.horizontal, DesignSystem.Spacing.screenPadding)
            
            VStack(spacing: 16) {
                if zappedArticles.isEmpty {
                    ForEach(0..<2) { index in
                        CommunityZapCardPlaceholder()
                            .fadeSlide(isVisible: true, delay: Double(index) * 0.1)
                    }
                } else {
                    ForEach(Array(zappedArticles.prefix(4).enumerated()), id: \.element.id) { index, zapEvent in
                        CommunityZapCard(zapEvent: zapEvent)
                            .fadeSlide(isVisible: true, delay: Double(index) * 0.1)
                    }
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.screenPadding)
        }
    }
}

struct CommunityZapCardPlaceholder: View {
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Circle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: 40, height: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 120, height: 14)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.15))
                    .frame(width: 180, height: 18)
            }
            
            Spacer()
        }
        .padding(DesignSystem.Spacing.cardPadding)
        .glassBackground()
        .shimmer()
    }
}

struct CommunityZapCard: View {
    let zapEvent: NDKEvent
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Circle()
                .fill(LinearGradient(colors: [DesignSystem.Colors.primary, DesignSystem.Colors.primaryDark], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text("\(zapEvent.pubkey.prefix(8))... zapped")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                
                Text("Content")
                    .font(.system(size: 16, weight: .regular))
                    .fontWeight(.medium)
                
                Text(relativeTime(from: zapEvent.createdAt))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(Color.gray)
            }
            
            Spacer()
            
            ZapAmountBadge()
        }
        .padding(DesignSystem.Spacing.cardPadding)
        .glassBackground()
    }
    
    private func relativeTime(from timestamp: Timestamp) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct ZapAmountBadge: View {
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 10))
            Text("1k")
                .font(DesignSystem.Typography.caption)
                .fontWeight(.semibold)
        }
        .foregroundColor(DesignSystem.Colors.primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(DesignSystem.Colors.primary.opacity(0.15))
        )
    }
}

struct BookstrDiscussionsSection: View {
    let discussions: [NDKEvent]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("#bookstr Discussions")
                    .font(DesignSystem.Typography.title2)
                
                Spacer()
                
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 16))
                    .foregroundColor(DesignSystem.Colors.primary)
            }
            .padding(.horizontal, DesignSystem.Spacing.screenPadding)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    if discussions.isEmpty {
                        ForEach(0..<3) { index in
                            DiscussionCardPlaceholder()
                                .frame(width: 280)
                                .fadeSlide(isVisible: true, delay: Double(index) * 0.1)
                        }
                    } else {
                        ForEach(Array(discussions.prefix(8).enumerated()), id: \.element.id) { index, discussion in
                            DiscussionCard(event: discussion)
                                .frame(width: 280)
                                .fadeSlide(isVisible: true, delay: Double(index) * 0.1)
                        }
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.screenPadding)
            }
        }
    }
}

struct DiscussionCardPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Circle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 24, height: 24)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 60, height: 14)
                
                Spacer()
            }
            
            VStack(spacing: 8) {
                ForEach(0..<3) { _ in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.15))
                        .frame(height: 14)
                }
            }
            
            Spacer()
        }
        .frame(height: 140)
        .padding(DesignSystem.Spacing.cardPadding)
        .glassBackground()
        .shimmer()
    }
}

struct DiscussionCard: View {
    let event: NDKEvent
    @State private var isLiked = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Circle()
                    .fill(LinearGradient(colors: [Color.gray.opacity(0.1), Color.gray.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 24, height: 24)
                    .overlay(
                        Text(String(event.pubkey.prefix(1)).uppercased())
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.text)
                    )
                
                Text(event.pubkey.prefix(8) + "...")
                    .font(DesignSystem.Typography.caption)
                    .fontWeight(.medium)
                
                Spacer()
                
                Text(relativeTime(from: event.createdAt))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(Color.gray)
            }
            
            Text(event.content)
                .font(.system(size: 15, weight: .regular))
                .lineLimit(3)
                .multilineTextAlignment(.leading)
            
            Spacer()
            
            HStack {
                InteractionButton(
                    icon: "bubble.left",
                    count: 0,
                    action: {}
                )
                
                Spacer()
                
                InteractionButton(
                    icon: "arrow.2.squarepath",
                    count: 0,
                    action: {}
                )
                
                Spacer()
                
                InteractionButton(
                    icon: isLiked ? "heart.fill" : "heart",
                    count: 0,
                    isActive: isLiked,
                    action: {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.5)) {
                            isLiked.toggle()
                        }
                        HapticType.light.trigger()
                    }
                )
            }
        }
        .frame(height: 140)
        .padding(DesignSystem.Spacing.cardPadding)
        .glassBackground()
    }
    
    private func relativeTime(from timestamp: Timestamp) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct InteractionButton: View {
    let icon: String
    let count: Int
    var isActive: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                
                if count > 0 {
                    Text("\(count)")
                        .font(DesignSystem.Typography.caption)
                }
            }
            .foregroundColor(isActive ? DesignSystem.Colors.primary : DesignSystem.Colors.textSecondary)
            .scaleEffect(isActive ? 1.1 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preference Key

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

#Preview {
    HomeView(tabBarVisible: .constant(true))
        .environmentObject(AppState())
}