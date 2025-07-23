import SwiftUI
import NDKSwift

struct FeedView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = FeedViewModel()
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(viewModel.items) { item in
                        FeedItemView(item: item)
                    }
                }
            }
            .background(OlasDesign.Colors.background)
            .navigationTitle("Olas")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .refreshable {
                await viewModel.refresh()
            }
            .onAppear {
                if let ndk = appState.ndk {
                    viewModel.startFeed(with: ndk)
                }
            }
        }
    }
}

struct FeedItemView: View {
    let item: FeedItem
    @EnvironmentObject var appState: AppState
    @State private var isLiked = false
    @State private var likeCount = 0
    @State private var replyCount = 0
    @State private var zapAmount = 0
    @State private var scale: CGFloat = 1.0
    @State private var isZoomed = false
    @State private var showProfile = false
    @State private var showingReplies = false
    @State private var showingLikeAnimation = false
    @State private var showingZap = false
    @State private var doubleTapLocation: CGPoint = .zero
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: OlasDesign.Spacing.md) {
                NavigationLink(destination: ProfileView(pubkey: item.event.pubkey)) {
                    HStack(spacing: OlasDesign.Spacing.md) {
                        OlasAvatar(
                            url: item.profile?.picture,
                            size: 40,
                            pubkey: item.event.pubkey
                        )
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.profile?.displayName ?? item.profile?.name ?? "Loading...")
                                .font(OlasDesign.Typography.bodyMedium)
                                .foregroundColor(OlasDesign.Colors.text)
                                .olasTextShadow()
                            
                            Text("@\(item.profile?.name ?? String(item.event.pubkey.prefix(8)))")
                                .font(OlasDesign.Typography.caption)
                                .foregroundColor(OlasDesign.Colors.textSecondary)
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle())
                
                Spacer()
                
                Button(action: { OlasDesign.Haptic.selection() }) {
                    Image(systemName: "ellipsis")
                        .foregroundColor(OlasDesign.Colors.textSecondary)
                        .font(.system(size: 18))
                }
            }
            .padding(.horizontal, OlasDesign.Spacing.md)
            .padding(.vertical, OlasDesign.Spacing.md)
            
            // Image display with multi-image support
            if !item.imageURLs.isEmpty {
                OlasMultiImageView(imageURLs: item.imageURLs)
                    .onTapGesture(count: 2) { location in
                        // Double tap to like
                        doubleTapLocation = location
                        showingLikeAnimation = true
                        if !isLiked {
                            toggleLike()
                        }
                    }
                    .onTapGesture {
                        OlasDesign.Haptic.selection()
                        // Single tap - show full screen (handled in OlasMultiImageView)
                    }
                    .gesture(
                        DragGesture(minimumDistance: 50)
                            .onEnded { value in
                                if value.translation.height < -50 {
                                    // Swipe up - View user profile
                                    OlasDesign.Haptic.selection()
                                    showProfile = true
                                }
                                // TODO: Add other swipe gestures
                                // Left: Quick share sheet
                                // Right: Save to collection
                                // Down: Dismiss if in preview
                            }
                    )
                    .overlay(
                        NavigationLink("", destination: ProfileView(pubkey: item.event.pubkey), isActive: $showProfile)
                            .hidden()
                    )
            } else {
                // No image found
                Rectangle()
                    .fill(OlasDesign.Colors.surface)
                    .aspectRatio(4/5, contentMode: .fit)
                    .overlay(
                        VStack(spacing: OlasDesign.Spacing.sm) {
                            Image(systemName: "photo")
                                .font(.system(size: 60))
                                .foregroundColor(OlasDesign.Colors.textTertiary)
                            Text("No Image")
                                .font(OlasDesign.Typography.caption)
                                .foregroundColor(OlasDesign.Colors.textTertiary)
                        }
                    )
            }
            
            // Actions
            HStack(spacing: OlasDesign.Spacing.lg) {
                // Like button with count
                Button(action: { toggleLike() }) {
                    HStack(spacing: 4) {
                        Image(systemName: isLiked ? "heart.fill" : "heart")
                            .font(.title2)
                            .foregroundColor(isLiked ? OlasDesign.Colors.error : OlasDesign.Colors.text)
                            .scaleEffect(isLiked ? 1.1 : 1.0)
                            .olasTextShadow()
                        
                        if likeCount > 0 {
                            Text("\(likeCount)")
                                .font(OlasDesign.Typography.caption)
                                .foregroundColor(OlasDesign.Colors.textSecondary)
                                .olasTextShadow()
                        }
                    }
                }
                
                // Reply button with count
                Button(action: { 
                    OlasDesign.Haptic.selection()
                    showingReplies.toggle()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "bubble.left")
                            .font(.title2)
                            .foregroundColor(OlasDesign.Colors.text)
                            .olasTextShadow()
                        
                        if replyCount > 0 {
                            Text("\(replyCount)")
                                .font(OlasDesign.Typography.caption)
                                .foregroundColor(OlasDesign.Colors.textSecondary)
                                .olasTextShadow()
                        }
                    }
                }
                
                // Zap button with amount
                Button(action: { sendZap() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt")
                            .font(.title2)
                            .foregroundColor(zapAmount > 0 ? OlasDesign.Colors.warning : OlasDesign.Colors.text)
                            .olasTextShadow()
                        
                        if zapAmount > 0 {
                            Text("\(zapAmount)")
                                .font(OlasDesign.Typography.caption)
                                .foregroundColor(OlasDesign.Colors.textSecondary)
                                .olasTextShadow()
                        }
                    }
                }
                
                Spacer()
                
                // Share button
                Button(action: { sharePost() }) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.title2)
                        .foregroundColor(OlasDesign.Colors.text)
                        .olasTextShadow()
                }
            }
            .padding(.horizontal, OlasDesign.Spacing.md)
            .padding(.vertical, OlasDesign.Spacing.md)
            
            // Content with rich text
            if !item.event.content.isEmpty {
                OlasRichText(
                    content: item.event.content,
                    tags: item.event.tags
                )
                .padding(.horizontal, OlasDesign.Spacing.md)
                .padding(.bottom, OlasDesign.Spacing.md)
            }
        }
        .background(OlasDesign.Colors.background)
        .overlay(
            // Like animation overlay
            Group {
                if showingLikeAnimation {
                    HeartAnimation(location: doubleTapLocation)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                showingLikeAnimation = false
                            }
                        }
                }
            }
        )
        .sheet(isPresented: $showingReplies) {
            ReplyView(parentEvent: item.event)
                .environmentObject(appState)
        }
        .sheet(isPresented: $showingZap) {
            ZapView(event: item.event)
                .environmentObject(appState)
        }
        .task {
            await loadEngagementCounts()
        }
    }
    
    // MARK: - Engagement Actions
    
    private func toggleLike() {
        guard let ndk = appState.ndk,
              let signer = NDKAuthManager.shared.activeSigner else { return }
        
        #if os(iOS)
        OlasDesign.Haptic.impact(.light)
        #else
        OlasDesign.Haptic.impact(0)
        #endif
        
        withAnimation(OlasDesign.Animation.spring) {
            isLiked.toggle()
            likeCount += isLiked ? 1 : -1
        }
        
        Task {
            do {
                if isLiked {
                    // Create like reaction (kind 7)
                    let reaction = try await ndk.event()
                        .kind(7)
                        .content("+")
                        .tags([
                            ["e", item.event.id],
                            ["p", item.event.pubkey]
                        ])
                        .build(signer: signer)
                    _ = try await ndk.publish(reaction)
                } else {
                    // TODO: Delete reaction event
                }
            } catch {
                print("Error toggling like: \(error)")
                // Revert on error
                withAnimation {
                    isLiked.toggle()
                    likeCount += isLiked ? 1 : -1
                }
            }
        }
    }
    
    private func sendZap() {
        OlasDesign.Haptic.selection()
        showingZap = true
    }
    
    private func sharePost() {
        OlasDesign.Haptic.selection()
        
        #if os(iOS)
        let noteLink = "nostr:\(item.event.id)"
        let activityVC = UIActivityViewController(
            activityItems: [noteLink],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
        #else
        // macOS sharing
        let noteLink = "nostr:\(item.event.id)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(noteLink, forType: .string)
        #endif
    }
    
    private func loadEngagementCounts() async {
        guard let ndk = appState.ndk else { return }
        
        // Check if we already liked this
        let authManager = NDKAuthManager.shared
        if let signer = authManager.activeSigner,
           let myPubkey = try? await signer.pubkey {
            let likeFilter = NDKFilter(
                authors: [myPubkey],
                kinds: [7],
                events: [item.event.id]
            )
            
            let likeDataSource = ndk.observe(filter: likeFilter, cachePolicy: .cacheOnly)
            let likes = await likeDataSource.collect(timeout: 1.0)
            await MainActor.run {
                isLiked = !likes.isEmpty
            }
        }
        
        // Count total reactions
        let reactionsFilter = NDKFilter(
            kinds: [7],
            events: [item.event.id]
        )
        
        let reactionsDataSource = ndk.observe(filter: reactionsFilter, cachePolicy: .cacheOnly)
        let reactions = await reactionsDataSource.collect(timeout: 1.0)
        let positiveReactions = reactions.filter { $0.content == "+" || $0.content == "🤙" }
        
        // Count replies
        let repliesFilter = NDKFilter(
            kinds: [1],
            events: [item.event.id]
        )
        
        let repliesDataSource = ndk.observe(filter: repliesFilter, cachePolicy: .cacheOnly)
        let replies = await repliesDataSource.collect(timeout: 1.0)
        
        await MainActor.run {
            likeCount = positiveReactions.count
            replyCount = replies.count
        }
    }
}

@MainActor
class FeedViewModel: ObservableObject {
    @Published var items: [FeedItem] = []
    private var profileTasks: [String: Task<Void, Never>] = [:]
    
    func startFeed(with ndk: NDK) {
        Task {
            // Subscribe to kind 1 (text notes) that contain images
            let filter = NDKFilter(kinds: [1])
            
            // Create data source using observe
            let dataSource = ndk.observe(filter: filter, cachePolicy: .cacheWithNetwork)
            
            for await event in dataSource.events {
                // Only show posts with image URLs
                if containsImageURL(event.content) {
                    let feedItem = FeedItem(from: event)
                    
                    await MainActor.run {
                        items.insert(feedItem, at: 0)
                    }
                    
                    // Load profile reactively
                    loadProfileReactively(for: event.pubkey, ndk: ndk)
                }
            }
        }
    }
    
    private func loadProfileReactively(for pubkey: String, ndk: NDK) {
        // Cancel existing task if any
        profileTasks[pubkey]?.cancel()
        
        // Start new profile observation
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
    
    private func containsImageURL(_ content: String) -> Bool {
        // Simple check for image URLs
        let imageExtensions = [".jpg", ".jpeg", ".png", ".gif", ".webp", ".heic"]
        let lowercased = content.lowercased()
        
        // Check for direct image URLs
        for ext in imageExtensions {
            if lowercased.contains(ext) {
                return true
            }
        }
        
        // Check for common image hosting services
        let imageHosts = ["imgur.com", "i.imgur.com", "nostr.build", "void.cat", "imgprxy.stacker.news"]
        for host in imageHosts {
            if lowercased.contains(host) {
                return true
            }
        }
        
        return false
    }
    
    func refresh() async {
        // Clear items and restart subscription
        await MainActor.run {
            items.removeAll()
        }
        // Subscription will continue running
    }
}

struct FeedItem: Identifiable {
    let id: String
    let event: NDKEvent
    var profile: NDKUserProfile?
    let imageURLs: [String]
    
    init(from event: NDKEvent) {
        self.id = event.id
        self.event = event
        self.imageURLs = FeedItem.extractImageURLs(from: event.content)
    }
    
    static func extractImageURLs(from content: String) -> [String] {
        var urls: [String] = []
        
        // Regular expression to find URLs
        let urlPattern = #"https?://[^\s<>"{}|\\^\[\]`]+"#
        
        do {
            let regex = try NSRegularExpression(pattern: urlPattern, options: [])
            let matches = regex.matches(in: content, options: [], range: NSRange(content.startIndex..., in: content))
            
            for match in matches {
                if let range = Range(match.range, in: content) {
                    let urlString = String(content[range])
                    
                    // Check if it's an image URL
                    let imageExtensions = [".jpg", ".jpeg", ".png", ".gif", ".webp", ".heic"]
                    let lowercasedURL = urlString.lowercased()
                    
                    // Check for direct image extensions
                    if imageExtensions.contains(where: { lowercasedURL.contains($0) }) {
                        urls.append(urlString)
                        continue
                    }
                    
                    // Check for image hosting services
                    let imageHosts = ["imgur.com", "i.imgur.com", "nostr.build", "void.cat", "imgprxy.stacker.news"]
                    if imageHosts.contains(where: { lowercasedURL.contains($0) }) {
                        urls.append(urlString)
                    }
                }
            }
        } catch {
            print("Error extracting URLs: \(error)")
        }
        
        return urls
    }
}