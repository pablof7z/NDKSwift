import SwiftUI
import NDKSwiftCore
import NDKSwiftUI

public struct ExploreView: View {
    @Environment(ChirpState.self) private var state
    @State private var packs: [FollowPack] = []
    @State private var relaySets: [RelaySet] = []
    @State private var trendingHashtags: [TrendingHashtag] = []
    @State private var searchText = ""

    /// Fallback pubkey for discovering content when user has no follows
    private let fallbackPubkey = "fa984bd7dbb282f07e16e7ae87b26a2a7b9b90b7246a44771f0cf5ae58018f52"

    public init() {}

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // Search bar
                searchBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)

                // Trending Hashtags
                hashtagsSection

                // Featured Follow Packs (horizontal)
                featuredPacksSection

                // Relay Sets (horizontal)
                relaySetsSection

                // All Follow Packs (vertical list)
                allPacksSection
                    .padding(.bottom, 100)
            }
        }
        .navigationTitle("Explore")
        .task {
            await loadContent()
        }
        .refreshable {
            await loadContent()
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search notes, users, hashtags...", text: $searchText)
                .textFieldStyle(.plain)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Hashtags Section

    private var hashtagsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(icon: "#", iconGradient: .green, title: "Trending Hashtags", showSeeAll: true)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(trendingHashtags) { hashtag in
                        NavigationLink(destination: hashtagFeedDestination(hashtag.hashtag)) {
                            HashtagPill(hashtag: hashtag.hashtag, noteCount: hashtag.noteCount)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.bottom, 24)
    }

    @ViewBuilder
    private func hashtagFeedDestination(_ hashtag: String) -> some View {
        // Placeholder - can be expanded to a full hashtag feed view
        Text("#\(hashtag) Feed")
            .navigationTitle("#\(hashtag)")
    }

    // MARK: - Featured Packs Section

    private var featuredPacksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(icon: "👥", iconGradient: .orange, title: "Follow Packs", showSeeAll: false)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(featuredPacks) { pack in
                        NavigationLink(destination: FollowPackFeedView(pack: pack)) {
                            FeaturedFollowPackCard(ndk: state.ndk, pack: pack)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.bottom, 24)
    }

    private var featuredPacks: [FollowPack] {
        Array(filteredPacks.prefix(5))
    }

    // MARK: - Relay Sets Section

    private var relaySetsSection: some View {
        Group {
            if !relaySets.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader(icon: "📡", iconGradient: .blue, title: "Relay Sets", showSeeAll: true)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(relaySets) { relaySet in
                                NavigationLink(destination: relaySetDetailDestination(relaySet)) {
                                    RelaySetCard(ndk: state.ndk, relaySet: relaySet)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 24)
            }
        }
    }

    @ViewBuilder
    private func relaySetDetailDestination(_ relaySet: RelaySet) -> some View {
        // Placeholder - can be expanded to show relay set details
        List {
            Section("Relays") {
                ForEach(relaySet.relays, id: \.url) { relay in
                    VStack(alignment: .leading) {
                        Text(relay.url)
                            .font(.body)
                        if let marker = relay.marker {
                            Text(marker)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(relaySet.name)
    }

    // MARK: - All Packs Section

    private var allPacksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("All Follow Packs")
                    .font(.system(size: 20, weight: .bold))
                Spacer()
            }
            .padding(.horizontal, 16)

            LazyVStack(spacing: 0) {
                ForEach(filteredPacks) { pack in
                    NavigationLink(destination: FollowPackFeedView(pack: pack)) {
                        FollowPackRowView(ndk: state.ndk, pack: pack)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Section Header

    private func sectionHeader(icon: String, iconGradient: IconGradient, title: String, showSeeAll: Bool) -> some View {
        HStack {
            HStack(spacing: 8) {
                Text(icon)
                    .font(.system(size: 14))
                    .frame(width: 28, height: 28)
                    .background(iconGradient.gradient)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Text(title)
                    .font(.system(size: 20, weight: .bold))
            }

            Spacer()

            if showSeeAll {
                Text("See All")
                    .font(.system(size: 15))
                    .foregroundStyle(.blue)
            }
        }
        .padding(.horizontal, 16)
    }

    private enum IconGradient {
        case green, orange, blue

        var gradient: LinearGradient {
            switch self {
            case .green:
                return LinearGradient(
                    colors: [Color(red: 0.19, green: 0.82, blue: 0.35), Color(red: 0, green: 0.78, blue: 0.75)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case .orange:
                return LinearGradient(
                    colors: [Color(red: 1, green: 0.42, blue: 0.42), Color(red: 1, green: 0.56, blue: 0.33)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case .blue:
                return LinearGradient(
                    colors: [Color(red: 0.04, green: 0.52, blue: 1), Color(red: 0.37, green: 0.36, blue: 0.9)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }

    // MARK: - Computed Properties

    private var filteredPacks: [FollowPack] {
        if searchText.isEmpty {
            return packs
        }

        return packs.filter { pack in
            pack.name.localizedCaseInsensitiveContains(searchText) ||
            (pack.description?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    // MARK: - Data Loading

    private func loadContent() async {
        // Load all content types concurrently
        async let packsTask: Void = discoverPacks()
        async let relaysTask: Void = discoverRelaySets()
        async let hashtagsTask: Void = loadTrendingHashtags()

        _ = await (packsTask, relaysTask, hashtagsTask)
    }

    private func discoverPacks() async {
        let subscription = state.ndk.subscribe(
            filter: NDKFilter(
                kinds: [39089, 39092],
                limit: 50
            ),
            cachePolicy: .cacheWithNetwork,
            subscriptionId: "pack-discovery",
            closeOnEose: true
        )

        var discovered: [String: FollowPack] = [:]

        for await batch in subscription.events {
            for event in batch {
                guard let pack = FollowPack(event: event) else { continue }
                guard pack.memberCount > 0 else { continue }

                let key = pack.name.lowercased()
                if let existing = discovered[key] {
                    if pack.memberCount > existing.memberCount {
                        discovered[key] = pack
                    }
                } else {
                    discovered[key] = pack
                }
            }

            await MainActor.run {
                packs = discovered.values
                    .sorted { $0.memberCount > $1.memberCount }
                    .prefix(20)
                    .map { $0 }
            }

            if discovered.count >= 20 { break }
        }
    }

    private func discoverRelaySets() async {
        // Get pubkeys to fetch relay sets from
        let pubkeysToQuery = getNetworkPubkeys()

        guard !pubkeysToQuery.isEmpty else { return }

        let subscription = state.ndk.subscribe(
            filter: NDKFilter(
                authors: pubkeysToQuery,
                kinds: [30002],
                limit: 30
            ),
            cachePolicy: .cacheWithNetwork,
            subscriptionId: "relay-set-discovery",
            closeOnEose: true
        )

        var discovered: [String: RelaySet] = [:]

        for await batch in subscription.events {
            for event in batch {
                guard let relaySet = RelaySet(event: event) else { continue }
                guard relaySet.relayCount > 0 else { continue }

                // Use event id as key to avoid duplicates
                discovered[event.id] = relaySet
            }

            await MainActor.run {
                relaySets = discovered.values
                    .sorted { $0.relayCount > $1.relayCount }
                    .prefix(10)
                    .map { $0 }
            }
        }
    }

    private func loadTrendingHashtags() async {
        // For now, use static trending hashtags
        // This can be expanded to fetch from a NIP-50 search relay
        await MainActor.run {
            trendingHashtags = [
                TrendingHashtag(hashtag: "bitcoin", noteCount: 12400),
                TrendingHashtag(hashtag: "nostr", noteCount: 8700),
                TrendingHashtag(hashtag: "zaps", noteCount: 3200),
                TrendingHashtag(hashtag: "plebchain", noteCount: 1800),
                TrendingHashtag(hashtag: "asknostr", noteCount: 956)
            ]
        }
    }

    /// Returns pubkeys to query for relay sets - user's follows or fallback
    private func getNetworkPubkeys() -> [String] {
        if let followList = state.ndk.sessionData?.followList, !followList.isEmpty {
            return Array(followList.prefix(50))
        }

        // Fallback: use the entry point pubkey's follows
        // For now, just return the fallback pubkey itself
        return [fallbackPubkey]
    }
}
