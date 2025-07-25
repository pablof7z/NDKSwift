import SwiftUI
import NDKSwift
import NDKSwiftUI

struct ArticleView: View {
    let article: Article
    @EnvironmentObject var appState: AppState
    @State private var selectedText: String?
    @State private var showHighlightOptions = false
    @State private var highlightRange: NSRange?
    @State private var author: NDKUserProfile?
    @State private var isBookmarked = false
    @State private var showShareSheet = false
    @State private var showSwarmOverlay = false
    @State private var swarmPulseAnimation = false
    @State private var showTextSelection = false
    @State private var highlightModeActive = false
    @State private var showHeatmap = false
    @StateObject private var swarmManager = SwarmHighlightManager(ndk: NDK(relayUrls: []))
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Hero Image
                    if let imageURL = article.image, let url = URL(string: imageURL) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(height: 250)
                                    .clipped()
                            case .failure(_):
                                Rectangle()
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(height: 250)
                                    .overlay {
                                        Image(systemName: "photo")
                                            .foregroundColor(.gray)
                                    }
                            case .empty:
                                Rectangle()
                                    .fill(Color.gray.opacity(0.1))
                                    .frame(height: 250)
                                    .shimmer()
                            @unknown default:
                                EmptyView()
                            }
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: .ds.medium) {
                        // Title and metadata
                        VStack(alignment: .leading, spacing: .ds.small) {
                            Text(article.title)
                                .font(.highlighterTitle)
                                .foregroundColor(.highlighterText)
                            
                            HStack(spacing: .ds.medium) {
                                // Author
                                HStack(spacing: .ds.micro) {
                                    Circle()
                                        .fill(Color.highlighterPurple.opacity(0.2))
                                        .frame(width: 32, height: 32)
                                        .overlay {
                                            if let picture = author?.picture, let url = URL(string: picture) {
                                                AsyncImage(url: url) { image in
                                                    image
                                                        .resizable()
                                                        .scaledToFill()
                                                        .clipShape(Circle())
                                                } placeholder: {
                                                    Image(systemName: "person.fill")
                                                        .foregroundColor(.highlighterPurple)
                                                }
                                            } else {
                                                Image(systemName: "person.fill")
                                                    .foregroundColor(.highlighterPurple)
                                            }
                                        }
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(author?.displayName ?? formatPubkey(article.author))
                                            .font(.highlighterCaption)
                                            .fontWeight(.medium)
                                        
                                        if let publishedAt = article.publishedAt {
                                            Text(publishedAt.formatted(.relative(presentation: .named)))
                                                .font(.ds.micro)
                                                .foregroundColor(.highlighterSecondaryText)
                                        }
                                    }
                                }
                                
                                Spacer()
                                
                                // Reading time
                                Label("\(article.estimatedReadingTime) min", systemImage: "clock")
                                    .font(.highlighterCaption)
                                    .foregroundColor(.highlighterSecondaryText)
                            }
                        }
                        .padding(.horizontal, .ds.large)
                        .padding(.top, .ds.large)
                        
                        if let summary = article.summary {
                            Text(summary)
                                .font(.highlighterBody)
                                .foregroundColor(.highlighterSecondaryText)
                                .padding(.horizontal, .ds.large)
                        }
                        
                        // Tags
                        if !article.hashtags.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: .ds.small) {
                                    ForEach(article.hashtags, id: \.self) { tag in
                                        Text("#\(tag)")
                                            .font(.highlighterCaption)
                                            .foregroundColor(.highlighterPurple)
                                            .padding(.horizontal, .ds.medium)
                                            .padding(.vertical, .ds.micro)
                                            .background(
                                                Capsule()
                                                    .fill(Color.highlighterPurple.opacity(0.1))
                                            )
                                    }
                                }
                                .padding(.horizontal, .ds.large)
                            }
                        }
                        
                        Divider()
                            .padding(.vertical, .ds.large)
                        
                        // Article Content with markdown rendering and text selection
                        if let ndk = appState.ndk {
                            ZStack {
                                SelectableMarkdownRenderer(
                                    content: article.content,
                                    ndk: ndk,
                                    onTextSelected: { text, range in
                                        selectedText = text
                                        highlightRange = range
                                        showHighlightOptions = true
                                        HapticManager.shared.triggerSelection()
                                    }
                                )
                                .markdownStyle(articleMarkdownStyle())
                                .onNostrEntityTap { entity in
                                    handleNostrEntityTap(entity)
                                }
                                .onHashtagTap { tag in
                                    handleHashtagTap(tag)
                                }
                                .onLinkTap { url in
                                    handleLinkTap(url)
                                }
                                .padding(.bottom, .ds.xl)
                                .opacity(showSwarmOverlay || showHeatmap ? 0 : 1)
                                
                                // Swarm Overlay
                                if showSwarmOverlay {
                                    SwarmOverlayView(
                                        text: article.content,
                                        swarmManager: swarmManager
                                    )
                                    .padding(.horizontal, .ds.large)
                                    .padding(.bottom, .ds.xl)
                                    .transition(.asymmetric(
                                        insertion: .opacity.combined(with: .scale(scale: 0.95)),
                                        removal: .opacity
                                    ))
                                }
                                
                                // NEW: Swarm Heatmap View
                                // if showHeatmap {
                                //     SwarmHeatmapView(
                                //         articleId: article.identifier ?? "",
                                //         content: article.content
                                //     )
                                //     .padding(.horizontal, .ds.large)
                                //     .padding(.bottom, .ds.xl)
                                //     .transition(.asymmetric(
                                //         insertion: .opacity.combined(with: .scale(scale: 0.98)),
                                //         removal: .opacity
                                //     ))
                                // }
                            }
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: .ds.medium) {
                        // Text Selection Mode Toggle
                        Button(action: {
                            showTextSelection = true
                            HapticManager.shared.impact(.light)
                        }) {
                            ZStack {
                                Image(systemName: "highlighter")
                                    .foregroundColor(highlightModeActive ? .highlighterOrange : .highlighterPurple)
                                    .symbolRenderingMode(.hierarchical)
                                
                                if highlightModeActive {
                                    Circle()
                                        .fill(Color.highlighterOrange)
                                        .frame(width: 8, height: 8)
                                        .offset(x: 8, y: -8)
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }
                        }
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: highlightModeActive)
                        
                        // Swarm Overlay Toggle with animation
                        Button(action: { 
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showSwarmOverlay.toggle()
                                if showSwarmOverlay { showHeatmap = false }
                            }
                            HapticManager.shared.impact(.light)
                            if showSwarmOverlay {
                                let articleUrl = article.tags.first(where: { $0.first == "r" })?[safe: 1]
                                swarmManager.loadSwarmHighlights(
                                    for: articleUrl,
                                    articleEvent: article.identifier
                                )
                            }
                        }) {
                            ZStack {
                                Image(systemName: "person.2.fill")
                                    .foregroundColor(showSwarmOverlay ? .highlighterOrange : .highlighterPurple)
                                    .scaleEffect(swarmPulseAnimation ? 1.1 : 1.0)
                                
                                if swarmManager.swarmHighlights.count > 0 {
                                    Circle()
                                        .fill(Color.highlighterOrange)
                                        .frame(width: 8, height: 8)
                                        .offset(x: 8, y: -8)
                                }
                            }
                        }
                        .onAppear {
                            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                                swarmPulseAnimation = true
                            }
                        }
                        
                        // NEW: Heatmap Toggle with spectacular animation
                        // Button(action: { 
                        //     withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        //         showHeatmap.toggle()
                        //         if showHeatmap { showSwarmOverlay = false }
                        //     }
                        //     HapticManager.shared.impact(.medium)
                        // }) {
                        //     ZStack {
                        //         Image(systemName: "heat.waves")
                        //             .foregroundColor(showHeatmap ? .highlighterOrange : .highlighterPurple)
                        //             .symbolEffect(.variableColor.iterative, value: showHeatmap)
                        //         
                        //         if showHeatmap {
                        //             Circle()
                        //                 .fill(
                        //                     RadialGradient(
                        //                         colors: [.highlighterOrange, .highlighterOrange.opacity(0)],
                        //                         center: .center,
                        //                         startRadius: 0,
                        //                         endRadius: 12
                        //                     )
                        //                 )
                        //                 .frame(width: 24, height: 24)
                        //                 .blur(radius: 4)
                        //                 .allowsHitTesting(false)
                        //         }
                        //     }
                        // }
                        
                        Button(action: { 
                            isBookmarked.toggle()
                            HapticManager.shared.impact(.light)
                        }) {
                            Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                                .foregroundColor(.highlighterPurple)
                        }
                        
                        Button(action: { showShareSheet = true }) {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(.highlighterPurple)
                        }
                    }
                }
            }
            .fullScreenCover(isPresented: $showTextSelection) {
                TextSelectionView(
                    content: article.content,
                    source: article.title,
                    author: author?.displayName ?? formatPubkey(article.author)
                )
                .onDisappear {
                    highlightModeActive = false
                }
            }
            .sheet(isPresented: $showHighlightOptions) {
                if let text = selectedText {
                    HighlightOptionsSheet(
                        selectedText: text,
                        articleTitle: article.title,
                        articleUrl: "nostr:\(article.id)",
                        onHighlight: { comment in
                            Task {
                                await createHighlight(text: text, comment: comment)
                            }
                        }
                    )
                }
            }
            .sheet(isPresented: $showShareSheet) {
                ArticleShareSheet(items: [
                    "Check out this article: \(article.title)",
                    "nostr:\(article.id)"
                ])
            }
        }
        .task {
            await loadAuthor()
        }
        .onAppear {
            // Initialize swarm manager with the actual NDK instance
            if let ndk = appState.ndk {
                swarmManager.ndk = ndk
                let articleUrl = article.tags.first(where: { $0.first == "r" })?[safe: 1]
                swarmManager.loadSwarmHighlights(
                    for: articleUrl,
                    articleEvent: article.identifier
                )
            }
        }
    }
    
    private func formatPubkey(_ pubkey: String) -> String {
        PubkeyFormatter.formatShort(pubkey)
    }
    
    private func loadAuthor() async {
        guard let ndk = appState.ndk else { return }
        
        // Load individual profile using declarative data source
        let profileDataSource = await ndk.outbox.observe(
            filter: NDKFilter(
                authors: [article.author],
                kinds: [0]
            ),
            maxAge: 3600,
            cachePolicy: .cacheWithNetwork
        )
        
        for await event in profileDataSource.events {
            if let fetchedProfile = JSONCoding.safeDecode(NDKUserProfile.self, from: event.content) {
                await MainActor.run {
                    self.author = fetchedProfile
                }
                break
            }
        }
    }
    
    private func createHighlight(text: String, comment: String?) async {
        guard let ndk = appState.ndk,
              let signer = appState.activeSigner else { return }
        
        do {
            var tags: [[String]] = []
            
            // Add context tag
            tags.append(["context", text.trimmingCharacters(in: .whitespacesAndNewlines)])
            
            // Add article reference (a tag for replaceable event)
            if let identifier = article.identifier {
                tags.append(["a", "30023:\(article.author):\(identifier)"])
            }
            
            // Add alt tag
            tags.append(["alt", "Highlight: '\(text.prefix(50))...'"])
            
            // Create highlight event
            let highlightContent = comment ?? text
            let event = try await NDKEventBuilder(ndk: ndk)
                .kind(9802)
                .content(highlightContent)
                .tags(tags)
                .build(signer: signer)
            
            _ = try await ndk.publish(event)
            
            await MainActor.run {
                showHighlightOptions = false
                selectedText = nil
                HapticManager.shared.notification(.success)
            }
        } catch {
            print("Failed to create highlight: \(error)")
            HapticManager.shared.notification(.error)
        }
    }
    
    // MARK: - Markdown Configuration
    
    private func articleMarkdownStyle() -> MarkdownConfiguration {
        var config = MarkdownConfiguration()
        
        // Colors
        config.textColor = .highlighterText
        config.headingColor = .highlighterText
        config.linkColor = .highlighterPurple
        config.codeBackgroundColor = Color.gray.opacity(0.1)
        config.blockquoteColor = .highlighterSecondaryText
        config.blockquoteBorderColor = .highlighterPurple
        config.mentionColor = .highlighterPurple
        config.hashtagColor = .highlighterOrange
        config.nostrEntityColor = .highlighterPurple
        
        // Fonts
        config.bodyFont = .highlighterBody
        config.h1Font = .largeTitle
        config.h2Font = .title
        config.h3Font = .title2
        
        // No content padding since we handle it ourselves
        config.contentPadding = EdgeInsets(top: 0, leading: .ds.large, bottom: 0, trailing: .ds.large)
        
        return config
    }
    
    // MARK: - Event Handlers
    
    private func handleNostrEntityTap(_ entity: ContentEntity) {
        switch entity {
        case .npub(let pubkey), .nprofile(let pubkey), .userMention(let pubkey, _):
            // Navigate to profile view
            print("Navigate to profile: \(pubkey)")
        case .note(let eventId), .nevent(let eventId), .eventMention(let eventId):
            // Navigate to event/note view
            print("Navigate to event: \(eventId)")
        case .naddr(let identifier):
            // Navigate to parameterized replaceable event
            print("Navigate to naddr: \(identifier)")
        default:
            break
        }
    }
    
    private func handleHashtagTap(_ tag: String) {
        // Navigate to hashtag search
        print("Search for hashtag: #\(tag)")
    }
    
    private func handleLinkTap(_ url: URL) {
        // Open URL in browser or in-app
        print("Open URL: \(url)")
    }
}

// MARK: - Highlight Options Sheet

struct HighlightOptionsSheet: View {
    let selectedText: String
    let articleTitle: String
    let articleUrl: String
    let onHighlight: (String?) -> Void
    @State private var comment = ""
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: .ds.large) {
                VStack(alignment: .leading, spacing: .ds.small) {
                    Text("Selected Text")
                        .font(.highlighterCaption)
                        .foregroundColor(.highlighterSecondaryText)
                    
                    Text("\"\(selectedText)\"")
                        .font(.highlighterQuote)
                        .foregroundColor(.highlighterText)
                        .padding()
                        .background(Color.highlighterOrange.opacity(0.1))
                        .cornerRadius(12)
                }
                
                VStack(alignment: .leading, spacing: .ds.small) {
                    Text("Add a comment (optional)")
                        .font(.highlighterCaption)
                        .foregroundColor(.highlighterSecondaryText)
                    
                    TextField("Your thoughts...", text: $comment, axis: .vertical)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .lineLimit(3...6)
                }
                
                Spacer()
                
                VStack(spacing: .ds.medium) {
                    Button(action: {
                        onHighlight(comment.isEmpty ? nil : comment)
                        dismiss()
                    }) {
                        HStack {
                            Image(systemName: "highlighter")
                            Text("Create Highlight")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ModernPrimaryButton())
                    
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(ModernSecondaryButton())
                }
            }
            .padding()
            .navigationTitle("Highlight")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Share Sheet

struct ArticleShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    ArticleView(article: try! Article(
        from: NDKEvent(
            id: "test",
            pubkey: "test",
            createdAt: 0,
            kind: 30023,
            tags: [
                ["title", "Sample Article"],
                ["summary", "This is a sample article for preview"],
                ["published_at", "1234567890"]
            ],
            content: "# Sample Article\n\nThis is some **bold** text and some *italic* text.\n\nLorem ipsum dolor sit amet.",
            sig: ""
        )
    ))
    .environmentObject(AppState())
}
