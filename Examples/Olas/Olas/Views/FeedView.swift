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
                        
                        if item.likeCount > 0 {
                            Text("\(item.likeCount)")
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
                        
                        if item.replyCount > 0 {
                            Text("\(item.replyCount)")
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
                            .foregroundColor(item.zapAmount > 0 ? OlasDesign.Colors.warning : OlasDesign.Colors.text)
                            .olasTextShadow()
                        
                        if item.zapAmount > 0 {
                            Text("\(item.zapAmount)")
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
        
        // Check if we already liked this - reactive pattern
        let authManager = NDKAuthManager.shared
        if let signer = authManager.activeSigner,
           let myPubkey = try? await signer.pubkey {
            let likeFilter = NDKFilter(
                authors: [myPubkey],
                kinds: [7],
                events: [item.event.id]
            )
            
            // Use reactive observe pattern - check cache first
            let likeDataSource = ndk.observe(
                filter: likeFilter,
                maxAge: 3600, // 1 hour cache
                cachePolicy: .cacheOnly // Only check cache, don't fetch from network
            )
            
            // Check first event to see if we liked it
            for await reaction in likeDataSource.events {
                if reaction.content == "+" || reaction.content == "🤙" {
                    await MainActor.run {
                        isLiked = true
                    }
                }
                break // Only need to check if any exist
            }
        }
        
        // Engagement counts are already being loaded reactively by FeedViewModel
        // No need to duplicate that logic here
    }
}

@MainActor
class FeedViewModel: ObservableObject {
    @Published var items: [FeedItem] = []
    private var profileTasks: [String: Task<Void, Never>] = [:]
    private var feedTask: Task<Void, Never>?
    private var engagementTasks: [String: Task<Void, Never>] = [:]
    
    func startFeed(with ndk: NDK) {
        // Cancel any existing feed task
        feedTask?.cancel()
        
        feedTask = Task {
            // Subscribe to kind 20 (picture posts) as per Olas spec
            // Also include kind 1 posts that contain images for compatibility
            let filter = NDKFilter(kinds: [20, 1], limit: 100)
            
            // Create data source using observe with reactive pattern
            let dataSource = ndk.observe(
                filter: filter,
                maxAge: 0,  // Real-time updates
                cachePolicy: .cacheWithNetwork
            )
            
            for await event in dataSource.events {
                // For kind 20, we expect imeta tags or image URLs
                // For kind 1, check if it contains image URLs
                let hasImages = event.kind == 20 || containsImageURL(event.content)
                
                if hasImages {
                    let feedItem = FeedItem(from: event)
                    
                    await MainActor.run {
                        // Insert sorted by timestamp
                        if let insertIndex = items.firstIndex(where: { $0.event.createdAt < event.createdAt }) {
                            items.insert(feedItem, at: insertIndex)
                        } else {
                            items.append(feedItem)
                        }
                        
                        // Limit feed size for performance
                        if items.count > 200 {
                            items.removeLast(items.count - 200)
                        }
                    }
                    
                    // Load profile reactively
                    loadProfileReactively(for: event.pubkey, ndk: ndk)
                    
                    // Load engagement counts reactively
                    loadEngagementReactively(for: event.id, ndk: ndk)
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
        // Cancel all tasks
        feedTask?.cancel()
        profileTasks.values.forEach { $0.cancel() }
        profileTasks.removeAll()
        engagementTasks.values.forEach { $0.cancel() }
        engagementTasks.removeAll()
        
        // Restart feed will happen when view calls startFeed again
    }
    
    private func loadEngagementReactively(for eventId: String, ndk: NDK) {
        // Cancel existing task if any
        engagementTasks[eventId]?.cancel()
        
        engagementTasks[eventId] = Task {
            // Observe reactions (kind 7)
            let reactionsFilter = NDKFilter(
                kinds: [7],
                events: [eventId]
            )
            
            let reactionsDataSource = ndk.observe(
                filter: reactionsFilter,
                maxAge: 0,
                cachePolicy: .cacheWithNetwork
            )
            
            // Observe replies (kind 1 referencing this event)
            let repliesFilter = NDKFilter(
                kinds: [1],
                events: [eventId]
            )
            
            let repliesDataSource = ndk.observe(
                filter: repliesFilter,
                maxAge: 0,
                cachePolicy: .cacheWithNetwork
            )
            
            // Update engagement counts reactively
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    for await reaction in reactionsDataSource.events {
                        if reaction.content == "+" || reaction.content == "🤙" {
                            await MainActor.run {
                                self.updateEngagement(for: eventId, type: .like, increment: true)
                            }
                        }
                    }
                }
                
                group.addTask {
                    for await _ in repliesDataSource.events {
                        await MainActor.run {
                            self.updateEngagement(for: eventId, type: .reply, increment: true)
                        }
                    }
                }
            }
        }
    }
    
    private func updateEngagement(for eventId: String, type: EngagementType, increment: Bool) {
        guard let index = items.firstIndex(where: { $0.event.id == eventId }) else { return }
        
        switch type {
        case .like:
            items[index].likeCount += increment ? 1 : -1
        case .reply:
            items[index].replyCount += increment ? 1 : -1
        case .zap:
            // TODO: Implement zap counting
            break
        }
    }
    
    enum EngagementType {
        case like, reply, zap
    }
}

struct FeedItem: Identifiable {
    let id: String
    let event: NDKEvent
    var profile: NDKUserProfile?
    let imageURLs: [String]
    var likeCount: Int = 0
    var replyCount: Int = 0
    var zapAmount: Int = 0
    
    init(from event: NDKEvent) {
        self.id = event.id
        self.event = event
        
        // Extract images based on event kind
        if event.kind == 20 {
            // Kind 20 should have imeta tags
            self.imageURLs = FeedItem.extractImagesFromTags(event.tags)
        } else {
            // Kind 1 - extract from content
            self.imageURLs = FeedItem.extractImageURLs(from: event.content)
        }
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