import SwiftUI
import NDKSwift

struct SearchView: View {
    @Environment(NostrManager.self) private var nostrManager
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = SearchViewModel()
    @State private var searchText = ""
    @State private var selectedTab = 0
    @FocusState private var isSearchFocused: Bool
    @State private var searchHistory: [String] = []
    
    enum SearchTab: String, CaseIterable {
        case top = "Top"
        case accounts = "Accounts"
        case hashtags = "Tags"
        case places = "Places"
        
        var icon: String {
            switch self {
            case .top: return "sparkles"
            case .accounts: return "person.2"
            case .hashtags: return "number"
            case .places: return "location"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                OlasDesign.Colors.background
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Search bar
                    searchBar
                        .padding(.horizontal, OlasDesign.Spacing.md)
                        .padding(.vertical, OlasDesign.Spacing.sm)
                    
                    // Tab selector
                    if !searchText.isEmpty {
                        searchTabs
                            .padding(.bottom, OlasDesign.Spacing.sm)
                    }
                    
                    // Content
                    ScrollView {
                        if searchText.isEmpty {
                            // Show search history and suggestions
                            searchHistoryView
                        } else {
                            // Show search results
                            searchResultsView
                        }
                    }
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                isSearchFocused = true
                loadSearchHistory()
            }
            .onChange(of: searchText) { _, newValue in
                Task {
                    await viewModel.search(query: newValue, ndk: nostrManager.ndk)
                }
            }
        }
    }
    
    private var searchBar: some View {
        HStack(spacing: OlasDesign.Spacing.sm) {
            HStack(spacing: OlasDesign.Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(OlasDesign.Colors.textSecondary)
                    .font(.system(size: 16))
                
                TextField("Search", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(OlasDesign.Typography.body)
                    .foregroundColor(OlasDesign.Colors.text)
                    .focused($isSearchFocused)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit {
                        addToSearchHistory(searchText)
                    }
                
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        OlasDesign.Haptic.selection()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(OlasDesign.Colors.textSecondary)
                            .font(.system(size: 16))
                    }
                }
            }
            .padding(.horizontal, OlasDesign.Spacing.md)
            .padding(.vertical, OlasDesign.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.full)
                    .fill(OlasDesign.Colors.surface)
            )
            
            if !searchText.isEmpty {
                Button("Cancel") {
                    searchText = ""
                    isSearchFocused = false
                    OlasDesign.Haptic.selection()
                }
                .font(OlasDesign.Typography.body)
                .foregroundColor(OlasDesign.Colors.primary)
            }
        }
    }
    
    private var searchTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: OlasDesign.Spacing.xs) {
                ForEach(Array(SearchTab.allCases.enumerated()), id: \.offset) { index, tab in
                    SearchTabButton(
                        title: tab.rawValue,
                        icon: tab.icon,
                        isSelected: selectedTab == index
                    ) {
                        selectedTab = index
                        OlasDesign.Haptic.selection()
                    }
                }
            }
            .padding(.horizontal, OlasDesign.Spacing.md)
        }
    }
    
    private var searchHistoryView: some View {
        VStack(alignment: .leading, spacing: OlasDesign.Spacing.lg) {
            // Recent searches
            if !searchHistory.isEmpty {
                VStack(alignment: .leading, spacing: OlasDesign.Spacing.md) {
                    HStack {
                        Text("Recent")
                            .font(OlasDesign.Typography.bodyBold)
                            .foregroundColor(OlasDesign.Colors.text)
                        
                        Spacer()
                        
                        Button("Clear All") {
                            clearSearchHistory()
                            OlasDesign.Haptic.selection()
                        }
                        .font(OlasDesign.Typography.caption)
                        .foregroundColor(OlasDesign.Colors.primary)
                    }
                    .padding(.horizontal, OlasDesign.Spacing.md)
                    
                    ForEach(searchHistory, id: \.self) { query in
                        SearchHistoryRow(query: query) {
                            searchText = query
                        } onDelete: {
                            removeFromSearchHistory(query)
                        }
                    }
                }
            }
            
            // Suggested users
            if !viewModel.suggestedUsers.isEmpty {
                VStack(alignment: .leading, spacing: OlasDesign.Spacing.md) {
                    Text("Suggested for You")
                        .font(OlasDesign.Typography.bodyBold)
                        .foregroundColor(OlasDesign.Colors.text)
                        .padding(.horizontal, OlasDesign.Spacing.md)
                    
                    ForEach(viewModel.suggestedUsers) { user in
                        UserSearchRow(user: user)
                    }
                }
                .padding(.top, OlasDesign.Spacing.lg)
            }
        }
        .padding(.vertical, OlasDesign.Spacing.sm)
    }
    
    private var searchResultsView: some View {
        Group {
            switch SearchTab.allCases[selectedTab] {
            case .top:
                topSearchResults
            case .accounts:
                accountSearchResults
            case .hashtags:
                hashtagSearchResults
            case .places:
                placesSearchResults
            }
        }
    }
    
    private var topSearchResults: some View {
        VStack(spacing: OlasDesign.Spacing.md) {
            // Mix of users and posts
            if !viewModel.searchUsers.isEmpty {
                VStack(alignment: .leading, spacing: OlasDesign.Spacing.sm) {
                    Text("Accounts")
                        .font(OlasDesign.Typography.caption)
                        .foregroundColor(OlasDesign.Colors.textSecondary)
                        .padding(.horizontal, OlasDesign.Spacing.md)
                    
                    ForEach(viewModel.searchUsers.prefix(3)) { user in
                        UserSearchRow(user: user)
                    }
                    
                    if viewModel.searchUsers.count > 3 {
                        Button {
                            selectedTab = 1 // Switch to accounts tab
                        } label: {
                            Text("See all accounts")
                                .font(OlasDesign.Typography.bodyMedium)
                                .foregroundColor(OlasDesign.Colors.primary)
                                .padding(.horizontal, OlasDesign.Spacing.md)
                        }
                    }
                }
            }
            
            if !viewModel.searchPosts.isEmpty {
                VStack(alignment: .leading, spacing: OlasDesign.Spacing.sm) {
                    Text("Posts")
                        .font(OlasDesign.Typography.caption)
                        .foregroundColor(OlasDesign.Colors.textSecondary)
                        .padding(.horizontal, OlasDesign.Spacing.md)
                        .padding(.top, OlasDesign.Spacing.md)
                    
                    PostSearchGrid(posts: viewModel.searchPosts)
                }
            }
        }
    }
    
    private var accountSearchResults: some View {
        VStack(spacing: 0) {
            if viewModel.isSearching && viewModel.searchUsers.isEmpty {
                ForEach(0..<5) { _ in
                    UserSearchRowSkeleton()
                }
            } else if viewModel.searchUsers.isEmpty {
                noResultsView(for: "accounts")
            } else {
                ForEach(viewModel.searchUsers) { user in
                    UserSearchRow(user: user)
                    
                    if user.id != viewModel.searchUsers.last?.id {
                        Divider()
                            .padding(.leading, 70)
                    }
                }
            }
        }
    }
    
    private var hashtagSearchResults: some View {
        VStack(spacing: OlasDesign.Spacing.md) {
            if viewModel.isSearching && viewModel.searchHashtags.isEmpty {
                loadingView
            } else if viewModel.searchHashtags.isEmpty {
                noResultsView(for: "hashtags")
            } else {
                ForEach(viewModel.searchHashtags) { hashtag in
                    HashtagSearchRow(hashtag: hashtag)
                }
            }
        }
        .padding(.horizontal, OlasDesign.Spacing.md)
    }
    
    private var placesSearchResults: some View {
        VStack {
            Text("Places search coming soon")
                .font(OlasDesign.Typography.body)
                .foregroundColor(OlasDesign.Colors.textSecondary)
                .padding(.top, 100)
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: OlasDesign.Spacing.lg) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: OlasDesign.Colors.primary))
                .scaleEffect(1.2)
            
            Text("Searching...")
                .font(OlasDesign.Typography.body)
                .foregroundColor(OlasDesign.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 100)
    }
    
    private func noResultsView(for type: String) -> some View {
        VStack(spacing: OlasDesign.Spacing.md) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(OlasDesign.Colors.textTertiary)
            
            Text("No \(type) found")
                .font(OlasDesign.Typography.body)
                .foregroundColor(OlasDesign.Colors.textSecondary)
            
            Text("Try searching for something else")
                .font(OlasDesign.Typography.caption)
                .foregroundColor(OlasDesign.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 100)
    }
    
    // MARK: - Search History Management
    
    private func loadSearchHistory() {
        searchHistory = UserDefaults.standard.stringArray(forKey: "OlasSearchHistory") ?? []
    }
    
    private func addToSearchHistory(_ query: String) {
        guard !query.isEmpty else { return }
        
        // Remove if already exists
        searchHistory.removeAll { $0 == query }
        
        // Add to beginning
        searchHistory.insert(query, at: 0)
        
        // Limit to 10 items
        if searchHistory.count > 10 {
            searchHistory = Array(searchHistory.prefix(10))
        }
        
        // Save
        UserDefaults.standard.set(searchHistory, forKey: "OlasSearchHistory")
    }
    
    private func removeFromSearchHistory(_ query: String) {
        searchHistory.removeAll { $0 == query }
        UserDefaults.standard.set(searchHistory, forKey: "OlasSearchHistory")
    }
    
    private func clearSearchHistory() {
        searchHistory.removeAll()
        UserDefaults.standard.removeObject(forKey: "OlasSearchHistory")
    }
}

// MARK: - Search Tab Button
struct SearchTabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(OlasDesign.Typography.caption).fontWeight(.bold)
            }
            .foregroundColor(isSelected ? .white : OlasDesign.Colors.text)
            .padding(.horizontal, OlasDesign.Spacing.md)
            .padding(.vertical, OlasDesign.Spacing.sm)
            .background(
                Group {
                    if isSelected {
                        LinearGradient(
                            colors: OlasDesign.Colors.primaryGradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    } else {
                        Color.clear
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.full)
                    .stroke(
                        isSelected ? Color.clear : OlasDesign.Colors.divider,
                        lineWidth: 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.full))
        }
    }
}

// MARK: - Search History Row
struct SearchHistoryRow: View {
    let query: String
    let onTap: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            Button(action: onTap) {
                HStack(spacing: OlasDesign.Spacing.md) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 20))
                        .foregroundColor(OlasDesign.Colors.textSecondary)
                    
                    Text(query)
                        .font(OlasDesign.Typography.body)
                        .foregroundColor(OlasDesign.Colors.text)
                    
                    Spacer()
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 14))
                    .foregroundColor(OlasDesign.Colors.textSecondary)
            }
        }
        .padding(.horizontal, OlasDesign.Spacing.md)
        .padding(.vertical, OlasDesign.Spacing.sm)
    }
}

// MARK: - User Search Row
struct UserSearchRow: View {
    let user: SearchUser
    @State private var showProfile = false
    
    var body: some View {
        Button {
            showProfile = true
        } label: {
            HStack(spacing: OlasDesign.Spacing.md) {
                OlasAvatar(
                    url: user.profile?.picture,
                    size: 54,
                    pubkey: user.pubkey
                )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(user.profile?.displayName ?? user.profile?.name ?? "User")
                        .font(OlasDesign.Typography.bodyMedium)
                        .foregroundColor(OlasDesign.Colors.text)
                        .lineLimit(1)
                    
                    Text("@\(user.profile?.name ?? String(user.pubkey.prefix(16)))")
                        .font(OlasDesign.Typography.caption)
                        .foregroundColor(OlasDesign.Colors.textSecondary)
                        .lineLimit(1)
                    
                    if let about = user.profile?.about {
                        Text(about)
                            .font(OlasDesign.Typography.caption)
                            .foregroundColor(OlasDesign.Colors.textTertiary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, OlasDesign.Spacing.md)
            .padding(.vertical, OlasDesign.Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .navigationDestination(isPresented: $showProfile) {
            ProfileView(pubkey: user.pubkey)
        }
    }
}

// MARK: - User Search Row Skeleton
struct UserSearchRowSkeleton: View {
    var body: some View {
        HStack(spacing: OlasDesign.Spacing.md) {
            Circle()
                .fill(OlasDesign.Colors.surface)
                .frame(width: 54, height: 54)
                .shimmer()
            
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(OlasDesign.Colors.surface)
                    .frame(width: 120, height: 16)
                    .shimmer()
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(OlasDesign.Colors.surface)
                    .frame(width: 80, height: 14)
                    .shimmer()
            }
            
            Spacer()
        }
        .padding(.horizontal, OlasDesign.Spacing.md)
        .padding(.vertical, OlasDesign.Spacing.sm)
    }
}

// MARK: - Hashtag Search Row
struct HashtagSearchRow: View {
    let hashtag: SearchHashtag
    @State private var showHashtagView = false
    
    var body: some View {
        Button {
            showHashtagView = true
        } label: {
            HStack(spacing: OlasDesign.Spacing.md) {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: OlasDesign.Colors.primaryGradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 54, height: 54)
                    .overlay(
                        Text("#")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white)
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("#\(hashtag.tag)")
                        .font(OlasDesign.Typography.bodyMedium)
                        .foregroundColor(OlasDesign.Colors.text)
                    
                    Text("\(hashtag.postCount) posts")
                        .font(OlasDesign.Typography.caption)
                        .foregroundColor(OlasDesign.Colors.textSecondary)
                }
                
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .navigationDestination(isPresented: $showHashtagView) {
            HashtagView(hashtag: hashtag.tag)
        }
    }
}

// MARK: - Post Search Grid
struct PostSearchGrid: View {
    let posts: [SearchPost]
    let columns = [
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1)
    ]
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: 1) {
            ForEach(posts) { post in
                PostSearchGridItem(post: post)
            }
        }
    }
}

struct PostSearchGridItem: View {
    let post: SearchPost
    @State private var showDetail = false
    
    var body: some View {
        GeometryReader { geometry in
            Button {
                showDetail = true
            } label: {
                if let imageURL = post.imageURLs.first, let url = URL(string: imageURL) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geometry.size.width, height: geometry.size.width)
                            .clipped()
                    } placeholder: {
                        Rectangle()
                            .fill(OlasDesign.Colors.surface)
                            .overlay(
                                ProgressView()
                            )
                    }
                } else {
                    Rectangle()
                        .fill(OlasDesign.Colors.surface)
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundColor(OlasDesign.Colors.textTertiary)
                        )
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .navigationDestination(isPresented: $showDetail) {
            PostDetailView(event: post.event)
        }
    }
}

// MARK: - View Model
@MainActor
class SearchViewModel: ObservableObject {
    @Published var searchUsers: [SearchUser] = []
    @Published var searchPosts: [SearchPost] = []
    @Published var searchHashtags: [SearchHashtag] = []
    @Published var suggestedUsers: [SearchUser] = []
    @Published var isSearching = false
    
    private var searchTask: Task<Void, Never>?
    
    func search(query: String, ndk: NDK?) async {
        searchTask?.cancel()
        
        guard !query.isEmpty, let ndk = ndk else {
            searchUsers = []
            searchPosts = []
            searchHashtags = []
            isSearching = false
            return
        }
        
        isSearching = true
        
        searchTask = Task {
            // Simulate search delay
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
            
            guard !Task.isCancelled else { return }
            
            // Search users
            await searchForUsers(query: query, ndk: ndk)
            
            // Search posts
            await searchForPosts(query: query, ndk: ndk)
            
            // Extract hashtags from query
            searchForHashtags(query: query)
            
            isSearching = false
        }
    }
    
    private func searchForUsers(query: String, ndk: NDK) async {
        let filter = NDKFilter(
            kinds: [0], // Metadata
            limit: 20
        )
        
        do {
            let dataSource = ndk.observe(filter: filter)
            let events = await dataSource.collect(timeout: 5.0)
            
            var users: [SearchUser] = []
            
            for event in events {
                guard let metadata = try? JSONDecoder().decode(NDKUserProfile.self, from: Data(event.content.utf8)) else { continue }
                
                // Check if name or display name matches query
                let nameMatch = metadata.name?.localizedCaseInsensitiveContains(query) ?? false
                let displayNameMatch = metadata.displayName?.localizedCaseInsensitiveContains(query) ?? false
                
                if nameMatch || displayNameMatch {
                    let user = SearchUser(
                        pubkey: event.pubkey,
                        profile: metadata
                    )
                    users.append(user)
                }
            }
            
            self.searchUsers = users
        } catch {
            print("Failed to search users: \(error)")
        }
    }
    
    private func searchForPosts(query: String, ndk: NDK) async {
        // Search in recent posts
        let filter = NDKFilter(
            kinds: [EventKind.image],
            limit: 50
        )
        
        do {
            let dataSource = ndk.observe(filter: filter)
            let events = await dataSource.collect(timeout: 5.0)
            
            var posts: [SearchPost] = []
            
            for event in events {
                // Check if content contains query
                if event.content.localizedCaseInsensitiveContains(query) ||
                   event.tags.contains(where: { tag in
                       tag.count >= 2 && tag[0] == "t" && tag[1].localizedCaseInsensitiveContains(query)
                   }) {
                    let post = SearchPost(event: event)
                    posts.append(post)
                }
            }
            
            self.searchPosts = Array(posts.prefix(12))
        } catch {
            print("Failed to search posts: \(error)")
        }
    }
    
    private func searchForHashtags(query: String) {
        // Extract hashtags from query
        let words = query.split(separator: " ")
        var hashtags: [SearchHashtag] = []
        
        for word in words {
            let cleanedWord = String(word).trimmingCharacters(in: .punctuationCharacters)
            if cleanedWord.hasPrefix("#") {
                let tag = String(cleanedWord.dropFirst())
                if !tag.isEmpty {
                    hashtags.append(SearchHashtag(tag: tag, postCount: Int.random(in: 10...1000)))
                }
            } else if !cleanedWord.isEmpty {
                // Also search for tags without the # prefix
                hashtags.append(SearchHashtag(tag: cleanedWord, postCount: Int.random(in: 10...1000)))
            }
        }
        
        self.searchHashtags = hashtags
    }
    
    func loadSuggestedUsers(ndk: NDK) async {
        // Load some random users as suggestions
        let filter = NDKFilter(
            kinds: [0],
            limit: 10
        )
        
        do {
            let dataSource = ndk.observe(filter: filter)
            let events = await dataSource.collect(timeout: 5.0)
            
            let users = events.compactMap { event -> SearchUser? in
                guard let metadata = try? JSONDecoder().decode(NDKUserProfile.self, from: Data(event.content.utf8)) else { return nil }
                return SearchUser(pubkey: event.pubkey, profile: metadata)
            }
            
            self.suggestedUsers = Array(users.prefix(5))
        } catch {
            print("Failed to load suggested users: \(error)")
        }
    }
}

// MARK: - Models
struct SearchUser: Identifiable {
    let id = UUID()
    let pubkey: String
    let profile: NDKUserProfile?
}

struct SearchPost: Identifiable {
    let id: String
    let event: NDKEvent
    
    var imageURLs: [String] {
        event.imageURLs
    }
    
    init(event: NDKEvent) {
        self.id = event.id
        self.event = event
    }
}

struct SearchHashtag: Identifiable {
    let id = UUID()
    let tag: String
    let postCount: Int
}