import SwiftUI
import NDKSwift

struct HighlightsFeedView: View {
    @EnvironmentObject var appState: AppState
    @State private var highlights: [HighlightEvent] = []
    @State private var currentIndex = 0
    @State private var isLoading = true
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false
    @Binding var tabBarVisible: Bool
    
    // Author cache
    @State private var authorProfiles: [String: NDKUserProfile] = [:]
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color.black
                    .ignoresSafeArea()
                
                if isLoading {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.5)
                } else if highlights.isEmpty {
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
        
        do {
            let events = await ndk.fetchEvents(filter: filter)
            let highlightEvents = events.compactMap { event -> HighlightEvent? in
                try? HighlightEvent(from: event)
            }
            
            await MainActor.run {
                self.highlights = highlightEvents.sorted { $0.createdAt > $1.createdAt }
                self.isLoading = false
            }
            
            // Load author profiles
            await loadAuthorProfiles(for: highlightEvents)
        } catch {
            print("Failed to load highlights: \(error)")
            await MainActor.run {
                self.isLoading = false
            }
        }
    }
    
    private func loadAuthorProfiles(for highlights: [HighlightEvent]) async {
        guard let ndk = appState.ndk else { return }
        
        let uniqueAuthors = Set(highlights.map { $0.author })
        
        for author in uniqueAuthors {
            for await profile in await ndk.profileManager.observe(for: author, maxAge: 3600) {
                await MainActor.run {
                    self.authorProfiles[author] = profile
                }
                break
            }
        }
    }
    
    private func refreshFeed() {
        HapticType.light.trigger()
        Task {
            isLoading = true
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
}

// MARK: - Feed Item View
struct HighlightFeedItemView: View {
    let highlight: HighlightEvent
    let author: NDKUserProfile?
    let onAuthorTap: () -> Void
    let onZap: () -> Void
    let onShare: () -> Void
    let onComment: () -> Void
    
    @State private var isZapped = false
    @State private var showingActions = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Gradient background
                LinearGradient(
                    colors: [
                        DesignSystem.Colors.primary.opacity(0.8),
                        DesignSystem.Colors.primary.opacity(0.3),
                        Color.black
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                // Content
                VStack {
                    Spacer()
                    
                    // Main content area
                    VStack(alignment: .leading, spacing: 20) {
                        // Quote
                        VStack(alignment: .leading, spacing: 16) {
                            Image(systemName: "quote.opening")
                                .font(.system(size: 30))
                                .foregroundColor(.white.opacity(0.5))
                            
                            Text(highlight.content)
                                .font(.system(size: 24, weight: .medium, design: .serif))
                                .foregroundColor(.white)
                                .lineSpacing(8)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            Image(systemName: "quote.closing")
                                .font(.system(size: 30))
                                .foregroundColor(.white.opacity(0.5))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .padding(.horizontal, 24)
                        
                        // Comment if available
                        if let comment = highlight.comment {
                            Text(comment)
                                .font(DesignSystem.Typography.body)
                                .foregroundColor(.white.opacity(0.9))
                                .padding(.horizontal, 24)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.white.opacity(0.1))
                                )
                                .padding(.horizontal, 24)
                        }
                        
                        // Context/Source
                        if let url = highlight.url {
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
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [.white.opacity(0.3), .white.opacity(0.1)],
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
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(
                                            Capsule()
                                                .stroke(Color.white.opacity(0.5), lineWidth: 1)
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
                                Image(systemName: isZapped ? "bolt.fill" : "bolt")
                                    .font(.system(size: 28))
                                    .foregroundColor(isZapped ? .orange : .white)
                                    .scaleEffect(isZapped ? 1.2 : 1.0)
                                    .animation(DesignSystem.Animation.springBouncy, value: isZapped)
                                
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
                                Image(systemName: "bubble.left")
                                    .font(.system(size: 26))
                                    .foregroundColor(.white)
                                
                                Text("5")
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundColor(.white)
                            }
                        }
                        
                        // Share
                        Button(action: onShare) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 26))
                                .foregroundColor(.white)
                        }
                        
                        // More options
                        Button(action: { showingActions = true }) {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 26))
                                .foregroundColor(.white)
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

#Preview {
    HighlightsFeedView(tabBarVisible: .constant(false))
        .environmentObject(AppState())
}