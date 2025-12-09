import SwiftUI
import NDKSwift
import NDKSwiftUI

extension NDKEvent: @retroactive Identifiable {}

public struct ExploreView: View {
    let ndk: NDK

    @EnvironmentObject private var authViewModel: AuthViewModel
    @EnvironmentObject private var muteListManager: MuteListManager
    @State private var searchText = ""
    @State private var searchResults: [NDKEvent] = []
    @State private var userResults: [SearchUserResult] = []
    @State private var trendingPosts: [NDKEvent] = []
    @State private var suggestedUsers: [SuggestedUser] = []
    @State private var selectedTab: ExploreTab = .forYou
    @State private var selectedPost: NDKEvent?
    @State private var seenPubkeys: Set<String> = []

    @FocusState private var isSearchFocused: Bool

    private var filteredTrendingPosts: [NDKEvent] {
        trendingPosts.filter { !muteListManager.isMuted($0.pubkey) }
    }

    private var filteredSuggestedUsers: [SuggestedUser] {
        suggestedUsers.filter { !muteListManager.isMuted($0.pubkey) }
    }

    private var filteredSearchResults: [NDKEvent] {
        searchResults.filter { !muteListManager.isMuted($0.pubkey) }
    }

    private var filteredUserResults: [SearchUserResult] {
        userResults.filter { !muteListManager.isMuted($0.pubkey) }
    }

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
            .fullScreenCover(item: $selectedPost) { post in
                FullscreenPostViewer(
                    event: post,
                    ndk: ndk,
                    isPresented: Binding(
                        get: { selectedPost != nil },
                        set: { if !$0 { selectedPost = nil } }
                    )
                )
            }
            .navigationDestination(for: String.self) { pubkey in
                ProfileView(ndk: ndk, pubkey: pubkey, currentUserPubkey: authViewModel.currentUser?.pubkey)
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
            } else if filteredUserResults.isEmpty && filteredSearchResults.isEmpty {
                emptySearchResults
            } else {
                // User results
                if !filteredUserResults.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Users")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.top, 16)

                        ForEach(filteredUserResults) { user in
                            NavigationLink(value: user.pubkey) {
                                SearchUserRow(user: user, ndk: ndk)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Post results
                if !filteredSearchResults.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Posts")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.top, 16)

                        LazyVStack(spacing: 1) {
                            ForEach(filteredSearchResults, id: \.id) { event in
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

            // Suggested Users Section - shows as users stream in
            if !filteredSuggestedUsers.isEmpty {
                suggestedUsersSection
            }

            // Trending/Recent Grid - shows posts as they stream in
            postsGrid
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
                    ForEach(filteredSuggestedUsers) { user in
                        NavigationLink(value: user.pubkey) {
                            SuggestedUserCard(user: user, ndk: ndk)
                        }
                        .buttonStyle(.plain)
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
            ForEach(filteredTrendingPosts, id: \.id) { event in
                GridPostCell(event: event, ndk: ndk) {
                    selectedPost = event
                }
            }
        }
        .padding(.top, 16)
    }

    private var feedKinds: [Kind] {
        var kinds: [Kind] = [OlasConstants.EventKinds.image]
        if SettingsManager.shared.showVideos {
            kinds.append(OlasConstants.EventKinds.shortVideo)
        }
        return kinds
    }

    private func loadDiscoverContent() async {
        // Fetch recent posts (images and optionally videos)
        let filter = NDKFilter(
            kinds: feedKinds,
            limit: 50
        )

        let subscription = ndk.subscribe(filter: filter)

        // Stream posts as they arrive
        for await event in subscription.events {
            // Insert in sorted position (newest first)
            let insertIndex = trendingPosts.firstIndex { event.createdAt > $0.createdAt } ?? trendingPosts.endIndex
            trendingPosts.insert(event, at: insertIndex)

            // Add to suggested users if we haven't seen this pubkey yet
            if !seenPubkeys.contains(event.pubkey) && suggestedUsers.count < 10 {
                seenPubkeys.insert(event.pubkey)
                suggestedUsers.append(SuggestedUser(pubkey: event.pubkey))
            }
        }
    }

    private func performSearch(query: String) async {
        guard !query.isEmpty else {
            searchResults = []
            userResults = []
            return
        }

        // Clear previous results
        searchResults = []
        userResults = []

        // Search for users by npub or name
        if query.hasPrefix("npub") {
            // Direct npub lookup
            if let user = try? NDKUser(npub: query) {
                userResults = [SearchUserResult(pubkey: user.pubkey)]
            }
        } else {
            // Search metadata events for matching names - stream results
            let metadataFilter = NDKFilter(
                kinds: [EventKind.metadata],
                limit: 50
            )

            let metaSub = ndk.subscribe(filter: metadataFilter)

            // Stream user results as they match
            for await event in metaSub.events {
                if let data = event.content.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let displayName = json["display_name"] as? String ?? json["displayName"] as? String
                    let name = json["name"] as? String
                    let searchableName = displayName ?? name ?? ""
                    if searchableName.localizedCaseInsensitiveContains(query) {
                        userResults.append(SearchUserResult(pubkey: event.pubkey))
                    }
                }
            }
        }

        // Search posts for content matching query - stream results
        let postFilter = NDKFilter(
            kinds: feedKinds,
            limit: 50
        )

        let postSub = ndk.subscribe(filter: postFilter)

        for await event in postSub.events {
            if event.content.localizedCaseInsensitiveContains(query) {
                searchResults.append(event)
            }
        }
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

            NDKUIFollowButton(ndk: ndk, pubkey: user.pubkey, style: .compact)
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
            // Thumbnail with blurhash placeholder
            if let imageURL = image.primaryImageURL, let url = URL(string: imageURL) {
                CachedAsyncImage(
                    url: url,
                    blurhash: image.primaryBlurhash,
                    aspectRatio: 1
                ) { loadedImage in
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
                .accessibilityLabel(image.primaryAlt ?? "Post thumbnail")
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

            NDKUIFollowButton(ndk: ndk, pubkey: user.pubkey, style: .compact)
        }
        .frame(width: 130)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
    }
}

private struct GridPostCell: View {
    let event: NDKEvent
    let ndk: NDK
    let onTap: () -> Void

    private var isVideo: Bool {
        event.kind == OlasConstants.EventKinds.shortVideo
    }

    private var image: NDKImage {
        NDKImage(event: event)
    }

    private var video: NDKVideo {
        NDKVideo(event: event)
    }

    private var thumbnailURL: URL? {
        if isVideo {
            // For videos, try thumbnail first, then fallback to video URL (some players show first frame)
            if let thumb = video.thumbnailURL, let url = URL(string: thumb) {
                return url
            }
            return nil
        } else {
            if let urlStr = image.primaryImageURL {
                return URL(string: urlStr)
            }
            return nil
        }
    }

    private var blurhash: String? {
        isVideo ? video.primaryBlurhash : image.primaryBlurhash
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let url = thumbnailURL {
                    CachedAsyncImage(
                        url: url,
                        blurhash: blurhash,
                        aspectRatio: 1
                    ) { loadedImage in
                        loadedImage
                            .resizable()
                            .scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.width)
                            .clipped()
                    } placeholder: {
                        Rectangle()
                            .fill(Color.gray.opacity(0.1))
                            .overlay(ProgressView().tint(OlasTheme.Colors.deepTeal))
                    }
                    .accessibilityLabel(isVideo ? (video.primaryAlt ?? "Video") : (image.primaryAlt ?? "Post image"))
                } else if isVideo {
                    // Video without thumbnail - show gradient with play icon
                    LinearGradient(
                        colors: [OlasTheme.Colors.deepTeal.opacity(0.8), OlasTheme.Colors.oceanBlue.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .overlay(
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.white.opacity(0.9))
                    )
                    .accessibilityLabel("Video")
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.1))
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                        )
                        .accessibilityLabel("Image not available")
                }

                // Video indicator overlay (only when there's a thumbnail)
                if isVideo && thumbnailURL != nil {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Image(systemName: "play.fill")
                                .font(.caption)
                                .foregroundStyle(.white)
                                .padding(4)
                                .background(.black.opacity(0.5))
                                .clipShape(Circle())
                                .padding(6)
                        }
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }
}
