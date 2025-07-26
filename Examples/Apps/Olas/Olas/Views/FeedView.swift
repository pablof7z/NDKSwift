import SwiftUI
import NDKSwift

struct FeedView: View {
    @Environment(NostrManager.self) private var nostrManager
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = FeedViewModel()
    @State private var hasAppeared = false
    @State private var showLiveIndicator = false
    @State private var newPostsCount = 0
    @State private var pulseAnimation = false
    @Namespace private var animation
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Subtle animated gradient background
                TimeBasedGradient()
                    .ignoresSafeArea()
                    .opacity(0.1)
                
                OlasDesign.Colors.background
                    .ignoresSafeArea()
                
                if viewModel.items.isEmpty && viewModel.isLoading {
                    // Loading state
                    loadingView
                } else if viewModel.items.isEmpty {
                    // Empty state
                    emptyStateView
                } else {
                    // Feed content
                    ScrollView {
                        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                            // Stories section
                            Section {
                                // Empty section content
                            } header: {
                                VStack(spacing: 0) {
                                    StoriesView()
                                        .background(OlasDesign.Colors.background)
                                    
                                    // Live updates indicator
                                    if showLiveIndicator {
                                        LiveUpdatesIndicator(newPostsCount: $newPostsCount)
                                            .transition(.asymmetric(
                                                insertion: .push(from: .top).combined(with: .opacity),
                                                removal: .push(from: .top).combined(with: .opacity)
                                            ))
                                            .onTapGesture {
                                                loadPendingItems()
                                            }
                                    }
                                }
                            }
                            
                            // Feed items
                            ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, item in
                                FeedItemView(item: item)
                                    .id(item.id)
                                    .transition(.asymmetric(
                                        insertion: .move(edge: .bottom).combined(with: .opacity),
                                        removal: .move(edge: .top).combined(with: .opacity)
                                    ))
                                    .scaleEffect(hasAppeared ? 1 : 0.95)
                                    .opacity(hasAppeared ? 1 : 0)
                                    .animation(
                                        .spring(response: 0.5, dampingFraction: 0.8)
                                        .delay(Double(min(index, 10)) * 0.05),
                                        value: hasAppeared
                                    )
                                
                                if index < viewModel.items.count - 1 {
                                    Rectangle()
                                        .fill(OlasDesign.Colors.divider)
                                        .frame(height: 1)
                                }
                            }
                        }
                        .padding(.top, 0)
                    }
                }
            }
            .navigationTitle("Olas")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .navigationBarLeading) {
                    // Live indicator in toolbar
                    if viewModel.isLive {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                                .overlay(
                                    Circle()
                                        .stroke(Color.green.opacity(0.3), lineWidth: 8)
                                        .scaleEffect(pulseAnimation ? 2 : 1)
                                        .opacity(pulseAnimation ? 0 : 1)
                                        .animation(.easeOut(duration: 1.5).repeatForever(autoreverses: false), value: pulseAnimation)
                                )
                            
                            Text("LIVE")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(.green)
                        }
                        .onAppear { pulseAnimation = true }
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                #else
                ToolbarItem(placement: .automatic) {
                #endif
                    NavigationLink(destination: CreatePostView()) {
                        Image(systemName: "camera.fill")
                            .onTapGesture {
                                OlasDesign.Haptic.selection()
                            }
                            .foregroundStyle(
                                LinearGradient(
                                    colors: OlasDesign.Colors.primaryGradient,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                }
            }
            .refreshable {
                await handleRefresh()
            }
            .onAppear {
                if let ndk = nostrManager.ndk {
                    viewModel.startFeed(with: ndk)
                }
                
                // Trigger staggered animations
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation {
                        hasAppeared = true
                    }
                }
            }
            .onChange(of: viewModel.pendingItemsCount) { _, newValue in
                if newValue > 0 {
                    withAnimation(.spring()) {
                        showLiveIndicator = true
                        newPostsCount = newValue
                    }
                } else {
                    withAnimation(.spring()) {
                        showLiveIndicator = false
                    }
                }
            }
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: OlasDesign.Spacing.lg) {
            ForEach(0..<5) { index in
                FeedItemSkeletonView()
                    .opacity(0.7)
                    .scaleEffect(hasAppeared ? 1 : 0.95)
                    .animation(
                        .easeInOut(duration: 0.5)
                        .delay(Double(index) * 0.1),
                        value: hasAppeared
                    )
            }
        }
        .padding(.horizontal, OlasDesign.Spacing.md)
    }
    
    private var emptyStateView: some View {
        EmptyFeedView(hasAppeared: hasAppeared)
    }
    
    private func handleRefresh() async {
        #if os(iOS)
        OlasDesign.Haptic.impact(.medium)
        #else
        OlasDesign.Haptic.impact(0)
        #endif
        hasAppeared = false
        await viewModel.refresh()
        
        // Re-trigger animations
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation {
                hasAppeared = true
            }
        }
    }
    
    private func loadPendingItems() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            viewModel.loadPendingItems()
            showLiveIndicator = false
            newPostsCount = 0
        }
        
        // Haptic feedback
        #if os(iOS)
        OlasDesign.Haptic.impact(.medium)
        #endif
    }
}

struct FeedItemView: View {
    let item: FeedItem
    @Environment(NostrManager.self) private var nostrManager
    @EnvironmentObject var appState: AppState
    @State private var isLiked = false
    @State private var scale: CGFloat = 1.0
    @State private var isZoomed = false
    @State private var showProfile = false
    @State private var showingReplies = false
    @State private var showingLikeAnimation = false
    @State private var showingZap = false
    @State private var doubleTapLocation: CGPoint = .zero
    @State private var navigateToProfile = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: OlasDesign.Spacing.md) {
                Button(action: { navigateToProfile = true }) {
                    HStack(spacing: OlasDesign.Spacing.md) {
                        OlasAvatar(
                            url: item.profile?.picture,
                            size: 40,
                            pubkey: item.event.pubkey
                        )
                        
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(item.profile?.displayName ?? item.profile?.name ?? "Loading...")
                                    .font(OlasDesign.Typography.bodyMedium)
                                    .foregroundColor(OlasDesign.Colors.text)
                                    .olasTextShadow()
                                
                                if let clientInfo = item.event.clientTag {
                                    Text("via \(clientInfo.name)")
                                        .font(OlasDesign.Typography.caption)
                                        .foregroundColor(OlasDesign.Colors.textTertiary)
                                        .olasTextShadow()
                                }
                            }
                            
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
                OlasMultiImageView(imageURLs: item.imageURLs, blurhashes: item.blurhashes)
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
                    LikeAnimationView(location: doubleTapLocation)
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
            ZapView(event: item.event, nostrManager: nostrManager)
                .environmentObject(appState)
        }
        .navigationDestination(isPresented: $navigateToProfile) {
            ProfileView(pubkey: item.event.pubkey)
        }
        .navigationDestination(isPresented: $showProfile) {
            ProfileView(pubkey: item.event.pubkey)
        }
        .task {
            await loadEngagementCounts()
        }
    }
    
    // MARK: - Engagement Actions
    
    private func toggleLike() {
        guard let ndk = nostrManager.ndk,
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
                    let reaction = try await NDKEventBuilder(ndk: ndk)
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
        guard let ndk = nostrManager.ndk else { return }
        
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
    @Published var pendingItems: [FeedItem] = []
    @Published var isLoading = true
    @Published var isLive = false
    @Published var pendingItemsCount = 0
    private var profileTasks: [String: Task<Void, Never>] = [:]
    private var feedTask: Task<Void, Never>?
    private var engagementTasks: [String: Task<Void, Never>] = [:]
    private var lastEventTime: Date?
    
    func startFeed(with ndk: NDK) {
        // Cancel any existing feed task
        feedTask?.cancel()
        
        isLoading = true
        
        feedTask = Task {
            // Simulate loading for smooth animation
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            await MainActor.run {
                self.isLoading = false
                self.isLive = true
            }
            
            // Subscribe to both picture posts (NIP-68) and text posts with images
            let filter = NDKFilter(kinds: [EventKind.image, EventKind.textNote], limit: 100)
            
            // Create data source using observe with reactive pattern
            let dataSource = ndk.observe(
                filter: filter,
                maxAge: 0,  // Real-time updates
                cachePolicy: .cacheWithNetwork
            )
            
            for await event in dataSource.events {
                // Check if this is an image post or text post with images
                let isImagePost = event.kind == EventKind.image
                let hasImages = event.kind == EventKind.textNote && containsImageURL(event.content)
                
                if isImagePost || hasImages {
                    let feedItem = FeedItem(from: event)
                    
                    await MainActor.run {
                        // Check if this is a new post (arrived after initial load)
                        let isNewPost = lastEventTime != nil && event.createdAt > lastEventTime!
                        
                        if isNewPost {
                            // Add to pending items
                            if let insertIndex = pendingItems.firstIndex(where: { $0.event.createdAt < event.createdAt }) {
                                pendingItems.insert(feedItem, at: insertIndex)
                            } else {
                                pendingItems.append(feedItem)
                            }
                            pendingItemsCount = pendingItems.count
                            
                            // Haptic feedback for new posts
                            #if os(iOS)
                            OlasDesign.Haptic.impact(.light)
                            #endif
                        } else {
                            // Insert sorted by timestamp
                            if let insertIndex = items.firstIndex(where: { $0.event.createdAt < event.createdAt }) {
                                items.insert(feedItem, at: insertIndex)
                            } else {
                                items.append(feedItem)
                            }
                            
                            // Update last event time
                            if lastEventTime == nil || event.createdAt > lastEventTime! {
                                lastEventTime = event.createdAt
                            }
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
            pendingItems.removeAll()
            pendingItemsCount = 0
            lastEventTime = nil
        }
        // Cancel all tasks
        feedTask?.cancel()
        profileTasks.values.forEach { $0.cancel() }
        profileTasks.removeAll()
        engagementTasks.values.forEach { $0.cancel() }
        engagementTasks.removeAll()
        
        // Restart feed will happen when view calls startFeed again
    }
    
    func loadPendingItems() {
        // Move pending items to main feed
        let itemsToAdd = pendingItems
        pendingItems.removeAll()
        pendingItemsCount = 0
        
        // Insert all pending items with animation
        for item in itemsToAdd {
            if let insertIndex = items.firstIndex(where: { $0.event.createdAt < item.event.createdAt }) {
                items.insert(item, at: insertIndex)
            } else {
                items.append(item)
            }
        }
        
        // Update last event time
        if let latestItem = items.first {
            lastEventTime = latestItem.event.createdAt
        }
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
            
            // Observe comments (NIP-22)
            let repliesFilter = NDKFilter(
                kinds: [EventKind.genericReply],
                tags: [
                    "E": Set([eventId]),  // Comments on this as root
                    "e": Set([eventId])   // Or as parent
                ]
            )
            
            let repliesDataSource = ndk.observe(
                filter: repliesFilter,
                maxAge: 0,
                cachePolicy: .cacheWithNetwork
            )
            
            // Observe zaps (kind 9735)
            let zapsFilter = NDKFilter(
                kinds: [9735],  // NIP-57 zap receipts
                tags: [
                    "e": Set([eventId])  // Zaps for this event
                ]
            )
            
            let zapsDataSource = ndk.observe(
                filter: zapsFilter,
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
                
                group.addTask {
                    for await zapReceipt in zapsDataSource.events {
                        // Extract zap amount from bolt11 tag
                        let zapAmount = await self.extractZapAmount(from: zapReceipt)
                        if zapAmount > 0 {
                            await MainActor.run {
                                self.updateEngagement(for: eventId, type: .zap, amount: zapAmount)
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func updateEngagement(for eventId: String, type: EngagementType, increment: Bool = true, amount: Int = 0) {
        guard let index = items.firstIndex(where: { $0.event.id == eventId }) else { return }
        
        switch type {
        case .like:
            items[index].likeCount += increment ? 1 : -1
        case .reply:
            items[index].replyCount += increment ? 1 : -1
        case .zap:
            items[index].zapAmount += amount
        }
    }
    
    enum EngagementType {
        case like, reply, zap
    }
    
    private func extractZapAmount(from zapReceiptEvent: NDKEvent) async -> Int {
        // Use NDKSwift's built-in NDKZapReceipt for proper NIP-57 parsing
        let zapReceipt = NDKZapReceipt(event: zapReceiptEvent)
        
        // Get amount in sats (NDKZapReceipt handles bolt11 parsing)
        if let amountSats = zapReceipt.amountSats {
            return Int(amountSats)
        }
        
        return 0
    }
}

struct FeedItem: Identifiable {
    let id: String
    let event: NDKEvent
    var profile: NDKUserProfile?
    let imageURLs: [String]
    let blurhashes: [String]
    var likeCount: Int = 0
    var replyCount: Int = 0
    var zapAmount: Int = 0
    
    init(from event: NDKEvent) {
        self.id = event.id
        self.event = event
        
        // Extract images and blurhashes from imeta tags (NIP-68 requires imeta tags)
        self.imageURLs = event.imageURLs
        
        // Extract blurhashes from imeta tags
        var hashes: [String] = []
        for tag in event.tags where tag.count >= 1 && tag[0] == "imeta" {
            var blurhash: String?
            
            // Parse imeta tag values
            for i in stride(from: 1, to: tag.count, by: 2) {
                if i + 1 < tag.count {
                    let key = tag[i]
                    let value = tag[i + 1]
                    
                    if key == "blurhash" {
                        blurhash = value
                    }
                }
            }
            
            if let hash = blurhash {
                hashes.append(hash)
            } else {
                hashes.append("") // Empty string for missing blurhash
            }
        }
        
        self.blurhashes = hashes
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
    
    static func extractImagesFromEvent(_ event: NDKEvent) -> [String] {
        // Use NDKSwift's built-in imeta support
        return event.imageURLs
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

// MARK: - Feed Item Skeleton
struct FeedItemSkeletonView: View {
    @State private var shimmerAnimation = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header skeleton
            HStack(spacing: OlasDesign.Spacing.md) {
                Circle()
                    .fill(OlasDesign.Colors.surface)
                    .overlay(shimmerGradient)
                    .frame(width: 40, height: 40)
                
                VStack(alignment: .leading, spacing: OlasDesign.Spacing.xs) {
                    RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.xs)
                        .fill(OlasDesign.Colors.surface)
                        .overlay(shimmerGradient)
                        .frame(width: 120, height: 14)
                    
                    RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.xs)
                        .fill(OlasDesign.Colors.surface)
                        .overlay(shimmerGradient)
                        .frame(width: 80, height: 12)
                }
                
                Spacer()
            }
            .padding(.horizontal, OlasDesign.Spacing.md)
            .padding(.vertical, OlasDesign.Spacing.md)
            
            // Image skeleton
            Rectangle()
                .fill(OlasDesign.Colors.surface)
                .overlay(shimmerGradient)
                .aspectRatio(4/5, contentMode: .fit)
            
            // Actions skeleton
            HStack(spacing: OlasDesign.Spacing.xl) {
                ForEach(0..<4) { _ in
                    Circle()
                        .fill(OlasDesign.Colors.surface)
                        .overlay(shimmerGradient)
                        .frame(width: 24, height: 24)
                }
                Spacer()
            }
            .padding(.horizontal, OlasDesign.Spacing.md)
            .padding(.vertical, OlasDesign.Spacing.md)
            
            // Content skeleton
            VStack(alignment: .leading, spacing: OlasDesign.Spacing.sm) {
                RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.xs)
                    .fill(OlasDesign.Colors.surface)
                    .overlay(shimmerGradient)
                    .frame(height: 14)
                
                RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.xs)
                    .fill(OlasDesign.Colors.surface)
                    .overlay(shimmerGradient)
                    .frame(width: 200, height: 14)
            }
            .padding(.horizontal, OlasDesign.Spacing.md)
            .padding(.bottom, OlasDesign.Spacing.md)
        }
        .background(OlasDesign.Colors.background)
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                shimmerAnimation = true
            }
        }
    }
    
    private var shimmerGradient: some View {
        LinearGradient(
            colors: [
                Color.white.opacity(0),
                Color.white.opacity(0.1),
                Color.white.opacity(0)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .rotationEffect(.degrees(30))
        .offset(x: shimmerAnimation ? 300 : -300)
        .transition(.move(edge: .leading))
    }
}

// MARK: - Empty Feed View
struct EmptyFeedView: View {
    let hasAppeared: Bool
    @State private var pulseAnimation = false
    
    var body: some View {
        VStack(spacing: OlasDesign.Spacing.xxxl) {
            Spacer()
            
            // Animated illustration
            ZStack {
                // Glowing background
                Circle()
                    .fill(
                        LinearGradient(
                            colors: OlasDesign.Colors.primaryGradient.map { $0.opacity(0.2) },
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 200, height: 200)
                    .blur(radius: 50)
                    .scaleEffect(pulseAnimation ? 1.3 : 0.9)
                    .animation(
                        .easeInOut(duration: 3).repeatForever(autoreverses: true),
                        value: pulseAnimation
                    )
                
                // Camera icon
                Image(systemName: "camera.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(
                        LinearGradient(
                            colors: OlasDesign.Colors.primaryGradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .rotationEffect(.degrees(pulseAnimation ? 10 : -10))
                    .animation(
                        .easeInOut(duration: 2).repeatForever(autoreverses: true),
                        value: pulseAnimation
                    )
            }
            .scaleEffect(hasAppeared ? 1 : 0.5)
            .opacity(hasAppeared ? 1 : 0)
            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: hasAppeared)
            
            VStack(spacing: OlasDesign.Spacing.md) {
                Text("Your Feed is Empty")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                
                Text("Be the first to share a beautiful moment")
                    .font(OlasDesign.Typography.body)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 20)
            .animation(.easeOut(duration: 0.6).delay(0.2), value: hasAppeared)
            
            VStack(spacing: OlasDesign.Spacing.md) {
                Button {
                    #if os(iOS)
        OlasDesign.Haptic.impact(.medium)
        #else
        OlasDesign.Haptic.impact(0)
        #endif
                    // TODO: Navigate to create post
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Create Your First Post")
                    }
                    .font(OlasDesign.Typography.bodyBold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, OlasDesign.Spacing.xl)
                    .padding(.vertical, OlasDesign.Spacing.md)
                    .background(
                        LinearGradient(
                            colors: OlasDesign.Colors.primaryGradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.full))
                    .shadow(color: OlasDesign.Colors.primaryGradient[0].opacity(0.3), radius: 20, y: 10)
                }
                
                Button {
                    #if os(iOS)
                    OlasDesign.Haptic.impact(.light)
                    #else
                    OlasDesign.Haptic.impact(0)
                    #endif
                    // TODO: Navigate to discover
                } label: {
                    Text("Discover People to Follow")
                        .font(OlasDesign.Typography.body)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .scaleEffect(hasAppeared ? 1 : 0.8)
            .opacity(hasAppeared ? 1 : 0)
            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.4), value: hasAppeared)
            
            Spacer()
            Spacer()
        }
        .padding(.horizontal, OlasDesign.Spacing.xl)
        .onAppear {
            pulseAnimation = true
        }
    }
}

// MARK: - Like Animation View
struct LikeAnimationView: View {
    let location: CGPoint
    @State private var hearts: [HeartParticle] = []
    @State private var mainHeartScale: CGFloat = 0
    @State private var mainHeartOpacity: Double = 1
    
    struct HeartParticle: Identifiable {
        let id = UUID()
        var startPosition: CGPoint
        let endPosition: CGPoint
        let rotation: Double
        let scale: CGFloat
        let color: Color
    }
    
    var body: some View {
        ZStack {
            // Main heart
            Image(systemName: "heart.fill")
                .font(.system(size: 100))
                .foregroundStyle(
                    LinearGradient(
                        colors: [OlasDesign.Colors.like, Color.pink],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .scaleEffect(mainHeartScale)
                .opacity(mainHeartOpacity)
                .position(location)
            
            // Particle hearts
            ForEach(hearts) { heart in
                Image(systemName: "heart.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(heart.color)
                    .scaleEffect(heart.scale)
                    .rotationEffect(.degrees(heart.rotation))
                    .position(heart.startPosition)
                    .animation(.easeOut(duration: 1.5), value: heart.startPosition)
            }
        }
        .onAppear {
            // Animate main heart
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                mainHeartScale = 1.2
            }
            
            withAnimation(.easeOut(duration: 0.8).delay(0.2)) {
                mainHeartOpacity = 0
            }
            
            // Generate particles
            generateParticles()
            
            // Animate particles after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                for i in hearts.indices {
                    withAnimation(.easeOut(duration: 1.5)) {
                        hearts[i].startPosition = hearts[i].endPosition
                    }
                }
            }
            
            // Haptic feedback
            OlasDesign.Haptic.success()
        }
    }
    
    private func generateParticles() {
        for _ in 0..<12 {
            let angle = Double.random(in: 0...(2 * .pi))
            let distance = CGFloat.random(in: 100...200)
            let endX = location.x + cos(angle) * distance
            let endY = location.y + sin(angle) * distance - 50 // Bias upward
            
            let heart = HeartParticle(
                startPosition: location,
                endPosition: CGPoint(x: endX, y: endY),
                rotation: Double.random(in: -45...45),
                scale: CGFloat.random(in: 0.5...1.2),
                color: [OlasDesign.Colors.like, .pink, .red].randomElement()!
            )
            hearts.append(heart)
        }
    }
}}