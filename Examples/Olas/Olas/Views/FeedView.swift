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
            .background(Color.black)
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Text(item.profile?.name?.prefix(1) ?? "?")
                            .font(.headline)
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.profile?.displayName ?? item.profile?.name ?? "Loading...")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    Text("@\(item.profile?.name ?? String(item.event.pubkey.prefix(8)))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: {}) {
                    Image(systemName: "ellipsis")
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            // Image display
            if !item.imageURLs.isEmpty {
                // For now, show first image
                AsyncImage(url: URL(string: item.imageURLs[0])) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            #if os(iOS)
                            .frame(maxHeight: UIScreen.main.bounds.width * 1.25) // 4:5 aspect ratio
                            #else
                            .frame(maxHeight: 600) // Fixed height for macOS
                            #endif
                            .clipped()
                    case .failure(_):
                        Rectangle()
                            .fill(Color.gray.opacity(0.1))
                            .aspectRatio(4/5, contentMode: .fit)
                            .overlay(
                                VStack {
                                    Image(systemName: "exclamationmark.triangle")
                                        .font(.system(size: 40))
                                        .foregroundColor(.gray.opacity(0.5))
                                    Text("Failed to load")
                                        .font(.caption)
                                        .foregroundColor(.gray.opacity(0.5))
                                }
                            )
                    case .empty:
                        Rectangle()
                            .fill(Color.gray.opacity(0.1))
                            .aspectRatio(4/5, contentMode: .fit)
                            .overlay(
                                ProgressView()
                                    .scaleEffect(1.5)
                            )
                    @unknown default:
                        EmptyView()
                    }
                }
                .aspectRatio(4/5, contentMode: .fit)
            } else {
                // No image found
                Rectangle()
                    .fill(Color.gray.opacity(0.1))
                    .aspectRatio(4/5, contentMode: .fit)
                    .overlay(
                        VStack {
                            Image(systemName: "photo")
                                .font(.system(size: 60))
                                .foregroundColor(.gray.opacity(0.3))
                            Text("No Image")
                                .font(.caption)
                                .foregroundColor(.gray.opacity(0.5))
                        }
                    )
            }
            
            // Actions
            HStack(spacing: 24) {
                Button(action: { 
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        isLiked.toggle()
                    }
                }) {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                        .font(.title2)
                        .foregroundColor(isLiked ? .red : .white)
                        .scaleEffect(isLiked ? 1.1 : 1.0)
                }
                
                Button(action: {}) {
                    Image(systemName: "bubble.left")
                        .font(.title2)
                        .foregroundColor(.white)
                }
                
                Button(action: {}) {
                    Image(systemName: "bolt")
                        .font(.title2)
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                Button(action: {}) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.title2)
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            // Content
            if !item.event.content.isEmpty {
                Text(item.event.content)
                    .font(.subheadline)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
        }
        .background(Color.black)
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