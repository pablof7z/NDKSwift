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
        
        for await profile in await ndk.profileManager.observe(for: author, maxAge: TimeConstants.hour) {
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
        HapticManager.shared.impact(.light)
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
        HapticManager.shared.impact(.light)
    }
    
    private func zapHighlight(_ highlight: HighlightEvent) {
        // TODO: Implement zapping
        HapticManager.shared.impact(.medium)
    }
    
    private func shareHighlight(_ highlight: HighlightEvent) {
        // TODO: Implement sharing
        HapticManager.shared.impact(.light)
    }
    
    private func commentOnHighlight(_ highlight: HighlightEvent) {
        // TODO: Implement commenting
        HapticManager.shared.impact(.light)
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
    
    @State private var isLiked = false
    @State private var showingActions = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background Layer - Fullscreen image with overlay
                if let articleImage = articleImage {
                    // Article image background with blur
                    Image(uiImage: articleImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .blur(radius: 20) // Gaussian blur
                        .opacity(0.4) // Standardized opacity (0.3-0.5)
                } else {
                    // Purple-to-orange gradient fallback
                    LinearGradient(
                        colors: [
                            Color(hex: "7B3FF2"), // Purple
                            Color(hex: "E94057"), // Pink-red
                            Color(hex: "F27121")  // Orange
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
                
                // Dark overlay for text contrast - increased to 0.5
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                
                // Main Content Layout
                VStack {
                    // Header Area - Source info capsule (top-left)
                    HStack {
                        HStack(spacing: 4) {
                            Text(sourceText)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Color(hex: "CCCCCC"))
                            Text("·")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Color(hex: "CCCCCC"))
                            Text(relativeTime(from: highlight.createdAt))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Color(hex: "CCCCCC"))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(0.3))
                                .overlay(
                                    Capsule()
                                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                                )
                        )
                        .padding(.leading, 16)
                        .padding(.top, 16)
                        
                        Spacer()
                    }
                    
                    Spacer()
                    
                    // Main Quote Block (centered vertically)
                    Text(highlight.content)
                        .font(.system(size: 26, weight: .semibold, design: .serif))
                        .foregroundColor(.white)
                        .lineSpacing(10)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: geometry.size.width * 0.8)
                        .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                    
                    Spacer()
                    
                    // Bottom User Info (bottom-left)
                    HStack {
                        HStack(spacing: 10) {
                            // Small avatar or placeholder
                            Circle()
                                .fill(Color.white.opacity(0.2))
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Text(authorInitial)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.white)
                                )
                            
                            Text(authorName)
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(.white)
                            
                            // Follow button
                            Button(action: {}) {
                                Text("Follow")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 5)
                                    .background(
                                        Capsule()
                                            .fill(Color.white.opacity(0.15))
                                            .overlay(
                                                Capsule()
                                                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
                                            )
                                    )
                            }
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
                
                // Action buttons overlay (positioned absolutely)
                VStack {
                    Spacer()
                    
                    HStack {
                        Spacer()
                        
                        // Actions Stack (bottom-right, vertical)
                        VStack(spacing: 16) {
                            // Like
                            Button(action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                    isLiked.toggle()
                                }
                                HapticManager.shared.impact(.light)
                            }) {
                                VStack(spacing: 4) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.black.opacity(0.3))
                                            .frame(width: 42, height: 42)
                                        
                                        Image(systemName: isLiked ? "heart.fill" : "heart")
                                            .font(.system(size: 20))
                                            .foregroundColor(isLiked ? .red : .white)
                                            .scaleEffect(isLiked ? 1.1 : 1.0)
                                    }
                                    .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 2)
                                }
                            }
                            
                            // Comment
                            Button(action: onComment) {
                                VStack(spacing: 4) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.black.opacity(0.3))
                                            .frame(width: 42, height: 42)
                                        
                                        Image(systemName: "message")
                                            .font(.system(size: 18))
                                            .foregroundColor(.white)
                                    }
                                    .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 2)
                                    
                                    Text("5")
                                        .font(.system(size: 11))
                                        .foregroundColor(.white.opacity(0.8))
                                }
                            }
                            
                            // Repost
                            Button(action: {}) {
                                ZStack {
                                    Circle()
                                        .fill(Color.black.opacity(0.3))
                                        .frame(width: 42, height: 42)
                                    
                                    Image(systemName: "arrow.2.squarepath")
                                        .font(.system(size: 18))
                                        .foregroundColor(.white)
                                }
                                .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 2)
                            }
                            
                            // Share
                            Button(action: onShare) {
                                ZStack {
                                    Circle()
                                        .fill(Color.black.opacity(0.3))
                                        .frame(width: 42, height: 42)
                                    
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 18))
                                        .foregroundColor(.white)
                                }
                                .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 2)
                            }
                        }
                        .padding(.trailing, 16)
                        .padding(.bottom, 80) // Extra padding to position above user info
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
    
    // Computed properties for cleaner code
    private var sourceText: String {
        if let article = article {
            return article.title.count > 30 ? String(article.title.prefix(27)) + "..." : article.title
        } else if let url = highlight.url, let host = URL(string: url)?.host {
            return host.replacingOccurrences(of: "www.", with: "")
        } else {
            return "Highlight"
        }
    }
    
    private var authorName: String {
        if let name = author?.name ?? author?.displayName {
            return name.count > 20 ? String(name.prefix(17)) + "..." : name
        } else {
            return String(highlight.author.prefix(8))
        }
    }
    
    private var authorInitial: String {
        (author?.name ?? author?.displayName ?? "U").prefix(1).uppercased()
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