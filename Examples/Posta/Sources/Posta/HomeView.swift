import SwiftUI
import NDKSwift

struct HomeView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var posts: [PostItem] = []
    @State private var isLoading = true
    @State private var isRefreshing = false
    @State private var subscription: NDKSubscription?
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
                LinearGradient(
                    gradient: Gradient(colors: [Color(.systemBackground), Color(.systemGray6)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Custom navigation header
                    customHeader
                    
                    // Main content
                    if isLoading && posts.isEmpty {
                        loadingView
                    } else if posts.isEmpty {
                        emptyStateView
                    } else {
                        postsList
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            Task {
                await startSubscription()
            }
        }
        .onDisappear {
            Task {
                await subscription?.close()
            }
        }
    }
    
    private var customHeader: some View {
        HStack {
            Text("Posta")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            Spacer()
            
            Button(action: {
                authManager.logout()
            }) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .padding(8)
                    .background(Circle().fill(Color(.systemGray5)))
            }
        }
        .padding(.horizontal)
        .padding(.top, 60)
        .padding(.bottom, 16)
        .background(
            Color(.systemBackground)
                .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        )
    }
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(.accentColor)
            
            Text("Loading messages...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 60))
                .foregroundColor(.secondary.opacity(0.5))
            
            Text("No messages yet")
                .font(.title3)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            Text("New messages will appear here")
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var postsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(posts) { post in
                    PostRowView(post: post)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    
                    Divider()
                        .padding(.leading, 72)
                }
            }
            .padding(.top, 8)
        }
        .refreshable {
            await refreshPosts()
        }
    }
    
    private func startSubscription() async {
        guard let ndk = authManager.getNDK() else { return }
        
        // Create filter for kind:1 notes
        let filter = NDKFilter(
            kinds: [EventKind.textNote],
            limit: 50
        )
        
        // Subscribe to events
        subscription = await ndk.subscribe(filters: [filter])
        
        Task {
            do {
                for try await event in subscription! {
                    await processEvent(event)
                }
            } catch {
                print("Subscription error: \(error)")
            }
        }
        
        // Also fetch existing events
        await fetchInitialPosts()
    }
    
    private func fetchInitialPosts() async {
        guard let ndk = authManager.getNDK() else { return }
        
        let filter = NDKFilter(
            kinds: [EventKind.textNote],
            limit: 100
        )
        
        do {
            let events = try await ndk.fetchEvents([filter])
            
            // Process all events
            for event in events {
                await processEvent(event)
            }
            
            isLoading = false
        } catch {
            print("Error fetching posts: \(error)")
            isLoading = false
        }
    }
    
    private func processEvent(_ event: NDKEvent) async {
        // Filter out replies (posts with 'e' tags)
        let hasReplyTag = event.tags.contains { tag in
            tag.first == "e"
        }
        
        if hasReplyTag {
           // return // Skip replies
        }
        
        // Create PostItem
        await createPostItem(from: event)
    }
    
    private func createPostItem(from event: NDKEvent) async {
        guard let ndk = authManager.getNDK() else { return }
        
        // Create user
        let user = NDKUser(pubkey: event.pubkey)
        user.ndk = ndk
        
        // Fetch profile
        let profile = try? await ndk.fetchProfile(event.pubkey)
        
        let post = PostItem(
            id: event.id,
            eventId: event.id,
            authorPubkey: event.pubkey,
            authorName: profile?.displayName ?? profile?.name,
            content: event.content,
            timestamp: Date(timeIntervalSince1970: TimeInterval(event.createdAt)),
            avatarURL: profile?.picture
        )
        
        // Add to posts array (avoid duplicates)
        await MainActor.run {
            if !posts.contains(where: { $0.eventId == event.id }) {
                posts.append(post)
                // Sort by timestamp (newest first)
                posts.sort { $0.timestamp > $1.timestamp }
            }
        }
    }
    
    private func refreshPosts() async {
        isRefreshing = true
        posts.removeAll()
        await fetchInitialPosts()
        isRefreshing = false
    }
}

struct PostItem: Identifiable {
    let id: String
    let eventId: String
    let authorPubkey: String
    let authorName: String?
    let content: String
    let timestamp: Date
    let avatarURL: String?
}

struct PostRowView: View {
    let post: PostItem
    @State private var isPressed = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar
            AsyncImage(url: URL(string: post.avatarURL ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(Color(.systemGray4))
            }
            .frame(width: 48, height: 48)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(Color(.systemGray5), lineWidth: 0.5)
            )
            
            VStack(alignment: .leading, spacing: 4) {
                // Header
                HStack(alignment: .firstTextBaseline) {
                    Text(post.authorName ?? shortenPubkey(post.authorPubkey))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Text(post.timestamp, style: .relative)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                
                // Content preview
                Text(post.content)
                    .font(.system(size: 15))
                    .lineLimit(2)
                    .foregroundColor(.primary.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Color(.systemBackground)
                .opacity(isPressed ? 0.8 : 1.0)
        )
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isPressed = false
            }
        }
    }
    
    private func shortenPubkey(_ pubkey: String) -> String {
        if pubkey.count > 16 {
            return String(pubkey.prefix(6)) + "..." + String(pubkey.suffix(6))
        }
        return pubkey
    }
}

#Preview {
    HomeView()
        .environmentObject(AuthManager())
}
