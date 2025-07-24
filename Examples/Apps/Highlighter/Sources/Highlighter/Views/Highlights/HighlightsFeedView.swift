import SwiftUI
import NDKSwift

struct HighlightsFeedView: View {
    @EnvironmentObject var appState: AppState
    @State private var highlights: [HighlightEvent] = []
    @State private var currentIndex = 0
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false
    @Binding var tabBarVisible: Bool
    
    // Author cache
    @State private var authorProfiles: [String: NDKUserProfile] = [:]
    
    // Article cache for highlights from articles
    @State private var articleCache: [String: Article] = [:]
    @State private var articleImages: [String: UIImage] = [:]
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color.black
                    .ignoresSafeArea()
                
                if highlights.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "highlighter")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        Text("No highlights yet")
                            .font(DesignSystem.Typography.title3)
                            .foregroundColor(.gray)
                    }
                } else {
                    // Highlights Stack
                    TabView(selection: $currentIndex) {
                        ForEach(Array(highlights.enumerated()), id: \.element.id) { index, highlight in
                            HighlightFeedItemView(
                                highlight: highlight,
                                author: authorProfiles[highlight.author],
                                article: articleForHighlight(highlight),
                                articleImage: articleImageForHighlight(highlight),
                                onAuthorTap: { showProfile(for: highlight.author) },
                                onZap: { zapHighlight(highlight) },
                                onShare: { shareHighlight(highlight) },
                                onComment: { commentOnHighlight(highlight) }
                            )
                            .tag(index)
                        }
                    }
                    .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                    .ignoresSafeArea()
                    
                    // Top overlay
                    VStack {
                        HStack {
                            Button(action: { tabBarVisible = true }) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(12)
                                    .background(Circle().fill(Color.white.opacity(0.2)))
                            }
                            
                            Spacer()
                            
                            Text("Highlights")
                                .font(DesignSystem.Typography.headline)
                                .foregroundColor(.white)
                            
                            Spacer()
                            
                            Button(action: refreshFeed) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 18))
                                    .foregroundColor(.white)
                                    .padding(12)
                                    .background(Circle().fill(Color.white.opacity(0.2)))
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, geometry.safeAreaInsets.top)
                        
                        Spacer()
                    }
                }
            }
        }
        .onAppear {
            tabBarVisible = false
            Task {
                await loadHighlights()
            }
        }
    }
    
    private func loadHighlights() async {
        guard let ndk = appState.ndk else { return }
        
        let filter = NDKFilter(
            kinds: [9802],
            limit: 50
        )
        
        // Stream highlights as they arrive
        let dataSource = await ndk.outbox.observe(
            filter: filter,
            maxAge: 300, // Use 5 minute cache
            cachePolicy: .cacheWithNetwork
        )
        
        // Process each highlight as it arrives
        for await event in dataSource.events {
            if let highlightEvent = try? HighlightEvent(from: event) {
                await MainActor.run {
                    // Add if not already present
                    if !highlights.contains(where: { $0.id == highlightEvent.id }) {
                        highlights.append(highlightEvent)
                        highlights.sort { $0.createdAt > $1.createdAt }
                    }
                }
                
                // Load author profile for this highlight
                Task {
                    await loadAuthorProfile(for: highlightEvent.author)
                }
                
                // Load referenced article if any
                if highlightEvent.referencedEvent != nil {
                    Task {
                        await loadReferencedArticleForHighlight(highlightEvent)
                    }
                }
            }
        }
    }
    
    private func loadAuthorProfile(for author: String) async {
        guard let ndk = appState.ndk else { return }
        
        // Don't reload if we already have it
        if authorProfiles[author] != nil { return }
        
        for await profile in await ndk.profileManager.observe(for: author, maxAge: 3600) {
            await MainActor.run {
                self.authorProfiles[author] = profile
            }
            break
        }
    }
    
    private func loadReferencedArticleForHighlight(_ highlight: HighlightEvent) async {
        guard let ndk = appState.ndk,
              let ref = highlight.referencedEvent,
              ref.contains(":") else { return }
        
        let parts = ref.split(separator: ":")
        guard parts.count >= 3,
              let kind = Int(parts[0]),
              kind == 30023 else { return }
        
        let author = String(parts[1])
        let identifier = parts[2...].joined(separator: ":")
        
        let filter = NDKFilter(
            authors: [author],
            kinds: [30023],
            limit: 1,
            tags: ["d": [String(identifier)]]
        )
        
        let dataSource = await ndk.outbox.observe(filter: filter, maxAge: 3600)
        
        for await event in dataSource.events {
            if let article = try? Article(from: event) {
                await MainActor.run {
                    self.articleCache[ref] = article
                }
                
                // Load article image if available
                if let imageUrl = article.image,
                   let url = URL(string: imageUrl) {
                    await loadArticleImage(url: url, for: ref)
                }
                break
            }
        }
    }
    
    private func refreshFeed() {
        HapticType.light.trigger()
        // Clear existing data to show fresh content
        highlights.removeAll()
        authorProfiles.removeAll()
        articleCache.removeAll()
        articleImages.removeAll()
        
        Task {
            await loadHighlights()
        }
    }
    
    private func showProfile(for pubkey: String) {
        // TODO: Navigate to profile
        HapticType.light.trigger()
    }
    
    private func zapHighlight(_ highlight: HighlightEvent) {
        // TODO: Implement zapping
        HapticType.medium.trigger()
    }
    
    private func shareHighlight(_ highlight: HighlightEvent) {
        // TODO: Implement sharing
        HapticType.light.trigger()
    }
    
    private func commentOnHighlight(_ highlight: HighlightEvent) {
        // TODO: Implement commenting
        HapticType.light.trigger()
    }
    
    private func loadReferencedArticles(for highlights: [HighlightEvent]) async {
        guard let ndk = appState.ndk else { return }
        
        // Collect all referenced events that look like article references
        let articleReferences = highlights.compactMap { highlight -> String? in
            guard let ref = highlight.referencedEvent else { return nil }
            // Check if it's an article reference (contains ":" for replaceable events)
            return ref.contains(":") ? ref : nil
        }
        
        guard !articleReferences.isEmpty else { return }
        
        // Parse article references and create filters
        for reference in Set(articleReferences) {
            let parts = reference.split(separator: ":")
            guard parts.count >= 3,
                  let kind = Int(parts[0]),
                  kind == 30023 else { continue }
            
            let author = String(parts[1])
            let identifier = parts[2...].joined(separator: ":")
            
            // Create filter for this specific article
            let filter = NDKFilter(
                authors: [author],
                kinds: [30023],
                limit: 1,
                tags: ["d": [String(identifier)]]
            )
            
            // Fetch the article
            let dataSource = await ndk.outbox.observe(filter: filter, maxAge: 3600, cachePolicy: .cacheWithNetwork)
            
            for await event in dataSource.events {
                if let article = try? Article(from: event) {
                    await MainActor.run {
                        self.articleCache[reference] = article
                    }
                    
                    // Load article image if available
                    if let imageUrl = article.image,
                       let url = URL(string: imageUrl) {
                        await loadArticleImage(url: url, for: reference)
                    }
                    break
                }
            }
        }
    }
    
    private func loadArticleImage(url: URL, for reference: String) async {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let image = UIImage(data: data) {
                await MainActor.run {
                    self.articleImages[reference] = image
                }
            }
        } catch {
            print("Failed to load article image: \(error)")
        }
    }
    
    private func articleForHighlight(_ highlight: HighlightEvent) -> Article? {
        guard let ref = highlight.referencedEvent else { return nil }
        return articleCache[ref]
    }
    
    private func articleImageForHighlight(_ highlight: HighlightEvent) -> UIImage? {
        guard let ref = highlight.referencedEvent else { return nil }
        return articleImages[ref]
    }
}

// MARK: - Feed Item View
struct HighlightFeedItemView: View {
    let highlight: HighlightEvent
    let author: NDKUserProfile?
    let article: Article?
    let articleImage: UIImage?
    let onAuthorTap: () -> Void
    let onZap: () -> Void
    let onShare: () -> Void
    let onComment: () -> Void
    
    @State private var isZapped = false
    @State private var showingActions = false
    @State private var imageOpacity = 0.0
    @State private var showBlurHash = true
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background with article image or gradient
                if article != nil {
                    ZStack {
                        // Default gradient background (shows while image loads)
                        if showBlurHash {
                            LinearGradient(
                                colors: [
                                    DesignSystem.Colors.primary.opacity(0.3),
                                    DesignSystem.Colors.secondary.opacity(0.3)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            .ignoresSafeArea()
                        }
                        
                        // Article image with overlay
                        if let articleImage = articleImage {
                            Image(uiImage: articleImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .clipped()
                                .opacity(imageOpacity)
                                .onAppear {
                                    withAnimation(.easeIn(duration: 0.5)) {
                                        imageOpacity = 1.0
                                        // Hide blurhash after image loads
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                            showBlurHash = false
                                        }
                                    }
                                }
                        }
                        
                        // Dark gradient overlay for readability
                        LinearGradient(
                            stops: [
                                .init(color: .black.opacity(0.3), location: 0),
                                .init(color: .black.opacity(0.5), location: 0.3),
                                .init(color: .black.opacity(0.8), location: 0.8),
                                .init(color: .black.opacity(0.9), location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                } else {
                    // Sophisticated gradient background
                    ZStack {
                        // Base gradient
                        LinearGradient(
                            colors: [
                                Color(hex: "1a1a2e"),
                                Color(hex: "0f0f1e"),
                                Color.black
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        
                        // Accent gradient overlay
                        RadialGradient(
                            colors: [
                                DesignSystem.Colors.primary.opacity(0.3),
                                DesignSystem.Colors.primary.opacity(0.1),
                                Color.clear
                            ],
                            center: .topTrailing,
                            startRadius: 100,
                            endRadius: 400
                        )
                        
                        // Mesh gradient effect
                        GeometryReader { _ in
                            ForEach(0..<3) { index in
                                Circle()
                                    .fill(
                                        RadialGradient(
                                            colors: [
                                                DesignSystem.Colors.primary.opacity(0.15),
                                                Color.clear
                                            ],
                                            center: .center,
                                            startRadius: 50,
                                            endRadius: 200
                                        )
                                    )
                                    .frame(width: 300, height: 300)
                                    .offset(
                                        x: CGFloat.random(in: -100...geometry.size.width),
                                        y: CGFloat.random(in: -100...geometry.size.height)
                                    )
                                    .blur(radius: 40)
                            }
                        }
                    }
                }
                
                // Content
                VStack {
                    Spacer()
                    
                    // Main content area
                    VStack(alignment: .leading, spacing: 20) {
                        // Article context if available
                        if let article = article {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("From")
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundColor(.white.opacity(0.7))
                                
                                Text(article.title)
                                    .font(DesignSystem.Typography.bodyMedium)
                                    .foregroundColor(.white)
                                    .lineLimit(2)
                                
                                if let summary = article.summary {
                                    Text(summary)
                                        .font(DesignSystem.Typography.footnote)
                                        .foregroundColor(.white.opacity(0.7))
                                        .lineLimit(2)
                                }
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.white.opacity(0.1))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                                    )
                            )
                            .padding(.horizontal, 24)
                        }
                        
                        // Quote
                        VStack(alignment: .leading, spacing: 16) {
                            Image(systemName: "quote.opening")
                                .font(.system(size: 24))
                                .foregroundColor(.white.opacity(0.6))
                            
                            Text(highlight.content)
                                .font(.system(size: article != nil ? 20 : 24, weight: .medium, design: .serif))
                                .foregroundColor(.white)
                                .lineSpacing(article != nil ? 6 : 8)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                            
                            Image(systemName: "quote.closing")
                                .font(.system(size: 24))
                                .foregroundColor(.white.opacity(0.6))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .padding(.horizontal, 24)
                        
                        // Comment if available
                        if let comment = highlight.comment {
                            Text(comment)
                                .font(DesignSystem.Typography.body)
                                .foregroundColor(.white.opacity(0.9))
                                .padding(.horizontal, 20)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.white.opacity(0.08))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                                        )
                                )
                                .padding(.horizontal, 24)
                        }
                        
                        // Context/Source
                        if let url = highlight.url, article == nil {
                            HStack(spacing: 8) {
                                Image(systemName: "link.circle.fill")
                                    .font(.system(size: 16))
                                Text(URL(string: url)?.host ?? "Source")
                                    .font(DesignSystem.Typography.footnote)
                            }
                            .foregroundColor(.white.opacity(0.7))
                            .padding(.horizontal, 24)
                        }
                        
                        // Author info
                        Button(action: onAuthorTap) {
                            HStack(spacing: 12) {
                                // Author avatar with gradient border
                                ZStack {
                                    Circle()
                                        .strokeBorder(
                                            LinearGradient(
                                                colors: [
                                                    DesignSystem.Colors.primary,
                                                    DesignSystem.Colors.primary.opacity(0.5)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 2
                                        )
                                        .frame(width: 48, height: 48)
                                    
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: [.white.opacity(0.2), .white.opacity(0.1)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 44, height: 44)
                                        .overlay(
                                            Text((author?.name ?? author?.displayName ?? "U").prefix(1).uppercased())
                                                .font(DesignSystem.Typography.headline)
                                                .foregroundColor(.white)
                                        )
                                }
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(author?.name ?? author?.displayName ?? String(highlight.author.prefix(8)))
                                        .font(DesignSystem.Typography.bodyMedium)
                                        .foregroundColor(.white)
                                    
                                    Text(relativeTime(from: highlight.createdAt))
                                        .font(DesignSystem.Typography.caption)
                                        .foregroundColor(.white.opacity(0.7))
                                }
                                
                                Spacer()
                                
                                // Follow button
                                Button(action: {}) {
                                    Text("Follow")
                                        .font(DesignSystem.Typography.footnoteMedium)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 10)
                                        .background(
                                            Capsule()
                                                .fill(Color.white.opacity(0.15))
                                                .overlay(
                                                    Capsule()
                                                        .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
                                                )
                                        )
                                }
                            }
                            .padding(.horizontal, 24)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.bottom, 100)
                    
                    Spacer()
                }
                
                // Action buttons on the right
                VStack(spacing: 24) {
                    Spacer()
                    
                    VStack(spacing: 20) {
                        // Zap
                        Button(action: {
                            onZap()
                            withAnimation(DesignSystem.Animation.springSnappy) {
                                isZapped.toggle()
                            }
                        }) {
                            VStack(spacing: 4) {
                                ZStack {
                                    Circle()
                                        .fill(Color.white.opacity(0.1))
                                        .frame(width: 48, height: 48)
                                    
                                    Image(systemName: isZapped ? "bolt.fill" : "bolt")
                                        .font(.system(size: 24))
                                        .foregroundColor(isZapped ? .orange : .white)
                                        .scaleEffect(isZapped ? 1.2 : 1.0)
                                        .animation(DesignSystem.Animation.springBouncy, value: isZapped)
                                }
                                
                                if isZapped {
                                    Text("21")
                                        .font(DesignSystem.Typography.caption)
                                        .foregroundColor(.white)
                                }
                            }
                        }
                        
                        // Comment
                        Button(action: onComment) {
                            VStack(spacing: 4) {
                                ZStack {
                                    Circle()
                                        .fill(Color.white.opacity(0.1))
                                        .frame(width: 48, height: 48)
                                    
                                    Image(systemName: "bubble.left")
                                        .font(.system(size: 22))
                                        .foregroundColor(.white)
                                }
                                
                                Text("5")
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundColor(.white)
                            }
                        }
                        
                        // Share
                        Button(action: onShare) {
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.1))
                                    .frame(width: 48, height: 48)
                                
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 22))
                                    .foregroundColor(.white)
                            }
                        }
                        
                        // More options
                        Button(action: { showingActions = true }) {
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.1))
                                    .frame(width: 48, height: 48)
                                
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 22))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 100)
                }
            }
        }
        .actionSheet(isPresented: $showingActions) {
            ActionSheet(
                title: Text("Highlight Options"),
                buttons: [
                    .default(Text("Save to Library")) {},
                    .default(Text("Copy Text")) {
                        UIPasteboard.general.string = highlight.content
                        HapticType.success.trigger()
                    },
                    .default(Text("View Article")) {
                        // Navigate to article
                    },
                    .default(Text("Report")) {},
                    .cancel()
                ]
            )
        }
    }
    
    private func relativeTime(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// Color extension removed - using the one from SharedStyles.swift

#Preview {
    HighlightsFeedView(tabBarVisible: .constant(false))
        .environmentObject(AppState())
}