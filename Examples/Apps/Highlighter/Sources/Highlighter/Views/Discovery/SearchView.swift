import SwiftUI
import NDKSwift

struct SearchView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    @State private var selectedTab = DiscoveryTab.articles
    
    enum DiscoveryTab: String, CaseIterable {
        case articles = "Articles"
        case highlights = "Highlights"
        case curations = "Collections"
        case users = "Users"
        
        var icon: String {
            switch self {
            case .articles: return "doc.text"
            case .highlights: return "highlighter"
            case .curations: return "folder"
            case .users: return "person.2"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab selector
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(DiscoveryTab.allCases, id: \.self) { tab in
                            TabButton(
                                title: tab.rawValue,
                                icon: tab.icon,
                                isSelected: selectedTab == tab
                            ) {
                                withAnimation(DesignSystem.Animation.highlighterSpring) {
                                    selectedTab = tab
                                }
                                HapticType.selection.trigger()
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 8)
                
                Divider()
                
                // Content
                switch selectedTab {
                case .articles:
                    ArticleDiscoveryView(searchText: searchText)
                case .highlights:
                    HighlightDiscoveryView(searchText: searchText)
                case .curations:
                    CurationDiscoveryView(searchText: searchText)
                case .users:
                    UserDiscoveryView(searchText: searchText)
                }
            }
            .navigationTitle("Discover")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: searchPrompt)
        }
    }
    
    private var searchPrompt: String {
        switch selectedTab {
        case .articles: return "Search articles"
        case .highlights: return "Search highlights"
        case .curations: return "Search collections"
        case .users: return "Search users"
        }
    }
}

// MARK: - Tab Button

struct TabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                Text(title)
                    .font(.highlighterCaption)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .foregroundColor(isSelected ? .white : .highlighterText)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? Color.highlighterPurple : Color.gray.opacity(0.1))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Highlight Discovery View

struct HighlightDiscoveryView: View {
    let searchText: String
    @EnvironmentObject var appState: AppState
    @State private var highlights: [HighlightEvent] = []
    
    var filteredHighlights: [HighlightEvent] {
        if searchText.isEmpty {
            return highlights
        }
        return highlights.filter { highlight in
            highlight.content.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(filteredHighlights) { highlight in
                    DiscoveryHighlightCard(highlight: highlight)
                }
            }
            .padding()
        }
        .task {
            await loadHighlights()
        }
    }
    
    private func loadHighlights() async {
        guard let ndk = appState.ndk else { return }
        
        
        let highlightSource = await ndk.outbox.observe(
            filter: NDKFilter(kinds: [9802], limit: 100),
            maxAge: 300,
            cachePolicy: .cacheWithNetwork
        )
        
        for await event in highlightSource.events {
            if let highlight = try? HighlightEvent(from: event) {
                await MainActor.run {
                    if !highlights.contains(where: { $0.id == highlight.id }) {
                        highlights.append(highlight)
                        highlights.sort { $0.createdAt > $1.createdAt }
                    }
                }
            }
        }
    }
}

// MARK: - Curation Discovery View

struct CurationDiscoveryView: View {
    let searchText: String
    @EnvironmentObject var appState: AppState
    @State private var curations: [ArticleCuration] = []
    
    var filteredCurations: [ArticleCuration] {
        if searchText.isEmpty {
            return curations
        }
        return curations.filter { curation in
            curation.title.localizedCaseInsensitiveContains(searchText) ||
            curation.description?.localizedCaseInsensitiveContains(searchText) == true
        }
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(filteredCurations) { curation in
                    CurationCard(curation: curation)
                }
            }
            .padding()
        }
        .task {
            await loadCurations()
        }
    }
    
    private func loadCurations() async {
        guard let ndk = appState.ndk else { return }
        
        let curationSource = await ndk.outbox.observe(
            filter: NDKFilter(kinds: [30004], limit: 50),
            maxAge: 300,
            cachePolicy: .cacheWithNetwork
        )
        
        for await event in curationSource.events {
            if let curation = try? ArticleCuration(from: event) {
                await MainActor.run {
                    if !curations.contains(where: { $0.id == curation.id }) {
                        curations.append(curation)
                        curations.sort { $0.createdAt > $1.createdAt }
                    }
                }
            }
        }
    }
}

// MARK: - Article Discovery View

struct ArticleDiscoveryView: View {
    let searchText: String
    @EnvironmentObject var appState: AppState
    @State private var articles: [Article] = []
    
    var filteredArticles: [Article] {
        if searchText.isEmpty {
            return articles
        }
        return articles.filter { article in
            article.title.localizedCaseInsensitiveContains(searchText) ||
            article.content.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(filteredArticles) { article in
                    NavigationLink(destination: ArticleView(article: article)) {
                        ArticleCardView(article: article)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding()
        }
        .task {
            await loadArticles()
        }
    }
    
    private func loadArticles() async {
        guard let ndk = appState.ndk else { return }
        
        let articleSource = await ndk.outbox.observe(
            filter: NDKFilter(kinds: [30023], limit: 50),
            maxAge: 300,
            cachePolicy: .cacheWithNetwork
        )
        
        for await event in articleSource.events {
            if let article = try? Article(from: event) {
                await MainActor.run {
                    if !articles.contains(where: { $0.id == article.id }) {
                        articles.append(article)
                        articles.sort { $0.createdAt > $1.createdAt }
                    }
                }
            }
        }
    }
}

// MARK: - Article Card View

struct ArticleCardView: View {
    let article: Article
    @State private var author: NDKUserProfile?
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header image
            if let imageURL = article.image, let url = URL(string: imageURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 200)
                        .clipped()
                } placeholder: {
                    Rectangle()
                        .fill(Color.gray.opacity(0.1))
                        .frame(height: 200)
                }
                .cornerRadius(8)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text(article.title)
                    .font(.highlighterHeadline)
                    .foregroundColor(.highlighterText)
                    .lineLimit(2)
                
                if let summary = article.summary {
                    Text(summary)
                        .font(.highlighterBody)
                        .foregroundColor(.highlighterSecondaryText)
                        .lineLimit(3)
                }
                
                HStack {
                    if let author = author {
                        Text("by \(author.displayName ?? formatPubkey(article.author))")
                            .font(.highlighterCaption)
                            .foregroundColor(.highlighterSecondaryText)
                    }
                    
                    Spacer()
                    
                    Text("\(article.estimatedReadingTime) min read")
                        .font(.highlighterCaption)
                        .foregroundColor(.highlighterSecondaryText)
                }
            }
        }
        .padding()
        .modernCard()
        .task {
            await loadAuthor()
        }
    }
    
    private func formatPubkey(_ pubkey: String) -> String {
        String(pubkey.prefix(8)) + "..."
    }
    
    private func loadAuthor() async {
        guard let ndk = appState.ndk else { return }
        
        for await profile in await ndk.profileManager.observe(for: article.author, maxAge: 3600) {
            await MainActor.run {
                self.author = profile
            }
            break
        }
    }
}

// MARK: - User Discovery View

struct UserDiscoveryView: View {
    let searchText: String
    @EnvironmentObject var appState: AppState
    @State private var users: [(pubkey: String, profile: NDKUserProfile)] = []
    
    var filteredUsers: [(pubkey: String, profile: NDKUserProfile)] {
        if searchText.isEmpty {
            return users
        }
        return users.filter { user in
            user.profile.displayName?.localizedCaseInsensitiveContains(searchText) == true ||
            user.profile.name?.localizedCaseInsensitiveContains(searchText) == true ||
            user.profile.about?.localizedCaseInsensitiveContains(searchText) == true
        }
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(filteredUsers, id: \.pubkey) { user in
                    UserCard(pubkey: user.pubkey, profile: user.profile)
                }
            }
            .padding()
        }
        .task {
            await loadUsers()
        }
    }
    
    private func loadUsers() async {
        guard let ndk = appState.ndk else { return }
        
        // Load users who have created highlights
        let highlightSource = await ndk.outbox.observe(
            filter: NDKFilter(kinds: [9802], limit: 100),
            maxAge: 3600,
            cachePolicy: .networkOnly
        )
        
        var uniquePubkeys = Set<String>()
        
        for await event in highlightSource.events {
            uniquePubkeys.insert(event.pubkey)
        }
        
        // Load profiles for these users
        for pubkey in uniquePubkeys.prefix(50) {
            for await profile in await ndk.profileManager.observe(for: pubkey, maxAge: 3600) {
                if let profile = profile {
                    await MainActor.run {
                        if !users.contains(where: { $0.pubkey == pubkey }) {
                            users.append((pubkey: pubkey, profile: profile))
                        }
                    }
                    break // Only need the first result
                }
            }
        }
    }
}

// MARK: - User Card

struct UserCard: View {
    let pubkey: String
    let profile: NDKUserProfile
    @State private var isFollowing = false
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            Circle()
                .fill(Color.highlighterPurple.opacity(0.2))
                .frame(width: 48, height: 48)
                .overlay {
                    if let picture = profile.picture, let url = URL(string: picture) {
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
            
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.displayName ?? profile.name ?? formatPubkey(pubkey))
                    .font(.highlighterBody)
                    .fontWeight(.medium)
                
                if let about = profile.about {
                    Text(about)
                        .font(.highlighterCaption)
                        .foregroundColor(.highlighterSecondaryText)
                        .lineLimit(2)
                }
            }
            
            Spacer()
            
            Button(action: toggleFollow) {
                Text(isFollowing ? "Following" : "Follow")
                    .font(.highlighterCaption)
                    .fontWeight(.medium)
                    .foregroundColor(isFollowing ? .highlighterPurple : .white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(isFollowing ? Color.clear : Color.highlighterPurple)
                            .overlay(
                                Capsule()
                                    .stroke(Color.highlighterPurple, lineWidth: 1)
                            )
                    )
            }
        }
        .padding()
        .modernCard()
    }
    
    private func formatPubkey(_ pubkey: String) -> String {
        String(pubkey.prefix(8)) + "..."
    }
    
    private func toggleFollow() {
        isFollowing.toggle()
        HapticType.light.trigger()
    }
}

// MARK: - Discovery Highlight Card

struct DiscoveryHighlightCard: View {
    let highlight: HighlightEvent
    @State private var author: NDKUserProfile?
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Author info
            HStack(spacing: 8) {
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
                                    .font(.system(size: 16))
                                    .foregroundColor(.highlighterPurple)
                            }
                        } else {
                            Image(systemName: "person.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.highlighterPurple)
                        }
                    }
                
                Text(author?.displayName ?? formatPubkey(highlight.author))
                    .font(.highlighterCaption)
                    .fontWeight(.medium)
                
                Spacer()
                
                Text(highlight.createdAt.formatted(.relative(presentation: .named)))
                    .font(.highlighterCaption)
                    .foregroundColor(.highlighterSecondaryText)
            }
            
            // Highlight content
            Text("\"\(highlight.content)\"")
                .font(.highlighterQuote)
                .foregroundColor(.highlighterText)
                .lineLimit(4)
            
            // Source
            if highlight.url != nil {
                HStack {
                    Image(systemName: "link")
                        .font(.system(size: 12))
                    Text("Source")
                        .font(.highlighterCaption)
                }
                .foregroundColor(.highlighterSecondaryText)
            }
        }
        .padding()
        .modernCard()
        .task {
            await loadAuthor()
        }
    }
    
    private func formatPubkey(_ pubkey: String) -> String {
        String(pubkey.prefix(8)) + "..."
    }
    
    private func loadAuthor() async {
        guard let ndk = appState.ndk else { return }
        
        for await profile in await ndk.profileManager.observe(for: highlight.author, maxAge: 3600) {
            await MainActor.run {
                self.author = profile
            }
            break // Only need the first result
        }
    }
}

// MARK: - Curation Card

struct CurationCard: View {
    let curation: ArticleCuration
    @State private var author: NDKUserProfile?
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Cover image
            if let imageURL = curation.image, let url = URL(string: imageURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 120)
                            .clipped()
                    case .failure(_), .empty:
                        Rectangle()
                            .fill(Color.gray.opacity(0.1))
                            .frame(height: 120)
                            .overlay {
                                Image(systemName: "folder")
                                    .foregroundColor(.gray)
                            }
                    @unknown default:
                        EmptyView()
                    }
                }
                .cornerRadius(8)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text(curation.title)
                    .font(.highlighterHeadline)
                    .foregroundColor(.highlighterText)
                
                if let description = curation.description {
                    Text(description)
                        .font(.highlighterBody)
                        .foregroundColor(.highlighterSecondaryText)
                        .lineLimit(2)
                }
                
                HStack {
                    if let author = author {
                        Text("by \(author.displayName ?? formatPubkey(curation.author))")
                            .font(.highlighterCaption)
                            .foregroundColor(.highlighterSecondaryText)
                    }
                    
                    Spacer()
                    
                    Label("\(curation.articles.count) articles", systemImage: "doc.text")
                        .font(.highlighterCaption)
                        .foregroundColor(.highlighterSecondaryText)
                }
            }
        }
        .padding()
        .modernCard()
        .task {
            await loadAuthor()
        }
    }
    
    private func formatPubkey(_ pubkey: String) -> String {
        String(pubkey.prefix(8)) + "..."
    }
    
    private func loadAuthor() async {
        guard let ndk = appState.ndk else { return }
        
        for await profile in await ndk.profileManager.observe(for: curation.author, maxAge: 3600) {
            await MainActor.run {
                self.author = profile
            }
            break // Only need the first result
        }
    }
}

#Preview {
    SearchView()
        .environmentObject(AppState())
}
