import SwiftUI
import NDKSwift
import NDKSwiftUI

public struct ExploreView: View {
    let ndk: NDK

    @State private var searchText = ""
    @State private var isSearching = false
    @State private var searchResults: [NDKEvent] = []
    @State private var userResults: [SearchUserResult] = []
    @State private var trendingPosts: [NDKEvent] = []
    @State private var suggestedUsers: [SuggestedUser] = []
    @State private var isLoading = true
    @State private var selectedTab: ExploreTab = .forYou

    @FocusState private var isSearchFocused: Bool

    enum ExploreTab: String, CaseIterable {
        case forYou = "For You"
        case trending = "Trending"
        case recent = "Recent"
    }

    public init(ndk: NDK) {
        self.ndk = ndk
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    searchBar

                    if isSearchFocused || !searchText.isEmpty {
                        searchResultsView
                    } else {
                        discoverContent
                    }
                }
            }
            .navigationTitle("Explore")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .task {
                await loadDiscoverContent()
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.body)
                    .foregroundStyle(.secondary)

                TextField("Search users or posts...", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($isSearchFocused)
                    .onChange(of: searchText) { _, newValue in
                        Task { await performSearch(query: newValue) }
                    }

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        searchResults = []
                        userResults = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .cornerRadius(12)

            if isSearchFocused {
                Button("Cancel") {
                    isSearchFocused = false
                    searchText = ""
                    searchResults = []
                    userResults = []
                }
                .foregroundStyle(OlasTheme.Colors.deepTeal)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .animation(.easeInOut(duration: 0.2), value: isSearchFocused)
    }

    private var searchResultsView: some View {
        LazyVStack(spacing: 0) {
            if searchText.isEmpty {
                recentSearches
            } else if isSearching {
                ProgressView()
                    .padding(.top, 40)
            } else if userResults.isEmpty && searchResults.isEmpty {
                emptySearchResults
            } else {
                // User results
                if !userResults.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Users")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.top, 16)

                        ForEach(userResults) { user in
                            SearchUserRow(user: user, ndk: ndk)
                        }
                    }
                }

                // Post results
                if !searchResults.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Posts")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.top, 16)

                        LazyVStack(spacing: 1) {
                            ForEach(searchResults, id: \.id) { event in
                                SearchPostRow(event: event, ndk: ndk)
                            }
                        }
                    }
                }
            }
        }
    }

    private var recentSearches: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Try searching for")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 24)

            VStack(spacing: 0) {
                SuggestionRow(icon: "person.fill", text: "Users by name or npub")
                SuggestionRow(icon: "photo.fill", text: "Posts with keywords")
                SuggestionRow(icon: "number", text: "Hashtags like #photography")
            }
        }
    }

    private var emptySearchResults: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.secondary.opacity(0.5))

            Text("No results found")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Try a different search term")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .padding(.top, 60)
    }

    private var discoverContent: some View {
        VStack(spacing: 0) {
            // Tab picker
            tabPicker

            if isLoading {
                ProgressView()
                    .padding(.top, 60)
            } else {
                // Suggested Users Section
                if !suggestedUsers.isEmpty {
                    suggestedUsersSection
                }

                // Trending/Recent Grid
                postsGrid
            }
        }
    }

    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(ExploreTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 8) {
                        Text(tab.rawValue)
                            .font(.subheadline.weight(selectedTab == tab ? .semibold : .regular))
                            .foregroundStyle(selectedTab == tab ? .primary : .secondary)

                        Rectangle()
                            .fill(selectedTab == tab ? OlasTheme.Colors.deepTeal : .clear)
                            .frame(height: 2)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 8)
    }

    private var suggestedUsersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Suggested for you")
                    .font(.headline)

                Spacer()

                Button("See All") {}
                    .font(.subheadline)
                    .foregroundStyle(OlasTheme.Colors.deepTeal)
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(suggestedUsers) { user in
                        SuggestedUserCard(user: user, ndk: ndk)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private var postsGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 2),
                GridItem(.flexible(), spacing: 2),
                GridItem(.flexible(), spacing: 2)
            ],
            spacing: 2
        ) {
            ForEach(trendingPosts, id: \.id) { event in
                GridPostCell(event: event, ndk: ndk)
            }
        }
        .padding(.top, 16)
    }

    private func loadDiscoverContent() async {
        isLoading = true
        defer { isLoading = false }

        // Fetch recent image posts (kind 20)
        let filter = NDKFilter(
            kinds: [OlasConstants.EventKinds.image],
            limit: 50
        )

        let subscription = ndk.subscribe(filter: filter)
        var posts: [NDKEvent] = []

        for await event in subscription.events {
            posts.append(event)
            if posts.count >= 30 { break }
        }

        // Sort by created_at descending
        trendingPosts = posts.sorted { $0.createdAt > $1.createdAt }

        // Generate suggested users from post authors
        let uniquePubkeys = Array(Set(posts.map(\.pubkey))).prefix(10)
        suggestedUsers = uniquePubkeys.map { SuggestedUser(pubkey: $0) }
    }

    private func performSearch(query: String) async {
        guard !query.isEmpty else {
            searchResults = []
            userResults = []
            return
        }

        isSearching = true
        defer { isSearching = false }

        // Search for users by npub or name
        if query.hasPrefix("npub") {
            // Direct npub lookup
            if let user = try? NDKUser(npub: query) {
                userResults = [SearchUserResult(pubkey: user.pubkey)]
            }
        } else {
            // Search metadata events for matching names
            let metadataFilter = NDKFilter(
                kinds: [EventKind.metadata],
                limit: 20
            )

            let metaSub = ndk.subscribe(filter: metadataFilter)
            var matchingUsers: [SearchUserResult] = []

            for await event in metaSub.events {
                if let data = event.content.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let displayName = json["display_name"] as? String ?? json["displayName"] as? String
                    let name = json["name"] as? String
                    let searchableName = displayName ?? name ?? ""
                    if searchableName.localizedCaseInsensitiveContains(query) {
                        matchingUsers.append(SearchUserResult(pubkey: event.pubkey))
                    }
                }
                if matchingUsers.count >= 10 { break }
            }

            userResults = matchingUsers
        }

        // Search posts for content matching query
        let postFilter = NDKFilter(
            kinds: [OlasConstants.EventKinds.image],
            limit: 30
        )

        let postSub = ndk.subscribe(filter: postFilter)
        var matchingPosts: [NDKEvent] = []

        for await event in postSub.events {
            if event.content.localizedCaseInsensitiveContains(query) {
                matchingPosts.append(event)
            }
            if matchingPosts.count >= 15 { break }
        }

        searchResults = matchingPosts
    }
}

// MARK: - Supporting Types

struct SearchUserResult: Identifiable {
    let id = UUID()
    let pubkey: String
}

struct SuggestedUser: Identifiable {
    let id = UUID()
    let pubkey: String
}

// MARK: - Supporting Views

private struct SuggestionRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct SearchUserRow: View {
    let user: SearchUserResult
    let ndk: NDK

    var body: some View {
        HStack(spacing: 12) {
            NDKUIProfilePicture(ndk: ndk, pubkey: user.pubkey, size: 50)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                NDKUIDisplayName(ndk: ndk, pubkey: user.pubkey)
                    .font(.subheadline.weight(.semibold))

                Text(String(user.pubkey.prefix(16)) + "...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                // Follow action
            } label: {
                Text("Follow")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(OlasTheme.Colors.deepTeal)
                    .cornerRadius(8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

private struct SearchPostRow: View {
    let event: NDKEvent
    let ndk: NDK

    private var image: NDKImage {
        NDKImage(event: event)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            if let imageURL = image.primaryImageURL, let url = URL(string: imageURL) {
                CachedAsyncImage(url: url) { loadedImage in
                    loadedImage
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Rectangle()
                        .fill(Color.gray.opacity(0.1))
                }
                .frame(width: 60, height: 60)
                .cornerRadius(8)
                .clipped()
            }

            VStack(alignment: .leading, spacing: 4) {
                NDKUIDisplayName(ndk: ndk, pubkey: event.pubkey)
                    .font(.subheadline.weight(.semibold))

                Text(event.content)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

private struct SuggestedUserCard: View {
    let user: SuggestedUser
    let ndk: NDK

    @State private var isFollowing = false

    var body: some View {
        VStack(spacing: 12) {
            NDKUIProfilePicture(ndk: ndk, pubkey: user.pubkey, size: 70)
                .clipShape(Circle())

            VStack(spacing: 2) {
                NDKUIDisplayName(ndk: ndk, pubkey: user.pubkey)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Text("Suggested")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    isFollowing.toggle()
                }
                triggerHaptic()
            } label: {
                Text(isFollowing ? "Following" : "Follow")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isFollowing ? Color.secondary : Color.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 6)
                    .background(isFollowing ? Color.secondary.opacity(0.2) : OlasTheme.Colors.deepTeal)
                    .cornerRadius(8)
            }
        }
        .frame(width: 130)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
    }

    private func triggerHaptic() {
        #if os(iOS)
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
        #endif
    }
}

private struct GridPostCell: View {
    let event: NDKEvent
    let ndk: NDK

    private var image: NDKImage {
        NDKImage(event: event)
    }

    var body: some View {
        GeometryReader { geometry in
            if let imageURL = image.primaryImageURL, let url = URL(string: imageURL) {
                CachedAsyncImage(url: url) { loadedImage in
                    loadedImage
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.width)
                        .clipped()
                } placeholder: {
                    Rectangle()
                        .fill(Color.gray.opacity(0.1))
                        .overlay(ProgressView())
                }
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.1))
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    )
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
