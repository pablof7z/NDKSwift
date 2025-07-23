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
    @State private var isLiked = false
    @State private var scale: CGFloat = 1.0
    @State private var isZoomed = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
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
                    .onTapGesture {
                        OlasDesign.Haptic.selection()
                        // TODO: Show full screen image viewer
                    }
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
                Button(action: { 
                    #if os(iOS)
                    OlasDesign.Haptic.impact(.light)
                    #else
                    OlasDesign.Haptic.impact(0)
                    #endif
                    withAnimation(OlasDesign.Animation.spring) {
                        isLiked.toggle()
                    }
                }) {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                        .font(.title2)
                        .foregroundColor(isLiked ? OlasDesign.Colors.error : OlasDesign.Colors.text)
                        .scaleEffect(isLiked ? 1.1 : 1.0)
                        .olasTextShadow()
                }
                
                Button(action: { OlasDesign.Haptic.selection() }) {
                    Image(systemName: "bubble.left")
                        .font(.title2)
                        .foregroundColor(OlasDesign.Colors.text)
                        .olasTextShadow()
                }
                
                Button(action: { OlasDesign.Haptic.selection() }) {
                    Image(systemName: "bolt")
                        .font(.title2)
                        .foregroundColor(OlasDesign.Colors.text)
                        .olasTextShadow()
                }
                
                Spacer()
                
                Button(action: { OlasDesign.Haptic.selection() }) {
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