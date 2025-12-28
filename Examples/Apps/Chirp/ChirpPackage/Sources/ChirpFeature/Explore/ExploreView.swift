import SwiftUI
import NDKSwiftCore
import NDKSwiftUI

public struct ExploreView: View {
    @Environment(ChirpState.self) private var state
    @State private var packs: [FollowPack] = []
    @State private var relaySets: [RelaySet] = []
    @State private var searchText = ""
    @State private var searchDataSource: NDKUnifiedSearchDataSource?
    @FocusState private var isSearchFocused: Bool

    // Navigation state for auto-navigation
    @State private var navigateToProfilePubkey: String?
    @State private var navigateToEventId: String?

    /// Fallback pubkey for discovering content when user has no follows
    private let fallbackPubkey = "fa984bd7dbb282f07e16e7ae87b26a2a7b9b90b7246a44771f0cf5ae58018f52"

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Search bar - always visible at top
            searchBar
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

            // Content switches between explore and search results
            if searchText.isEmpty {
                exploreContent
            } else {
                searchResultsContent
            }
        }
        .navigationTitle("Explore")
        .task {
            searchDataSource = NDKUnifiedSearchDataSource(ndk: state.ndk)
            await loadContent()
        }
        .refreshable {
            await loadContent()
        }
        .onChange(of: searchText) { _, newValue in
            searchDataSource?.search(query: newValue)
        }
        // Auto-navigate when data source signals profile navigation
        .onChange(of: searchDataSource?.navigateToProfile) { _, pubkey in
            if let pubkey = pubkey {
                navigateToProfilePubkey = pubkey
                searchDataSource?.acknowledgeNavigation()
            }
        }
        // Handle profile navigation (programmatic)
        .navigationDestination(item: $navigateToProfilePubkey) { pubkey in
            ProfileView(pubkey: pubkey)
        }
        // Handle profile navigation (from search results tap)
        .navigationDestination(for: String.self) { pubkey in
            ProfileView(pubkey: pubkey)
        }
        // Handle event navigation
        .navigationDestination(for: NDKEvent.self) { event in
            ThreadView(event: event)
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search notes, users, hashtags...", text: $searchText)
                .textFieldStyle(.plain)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .focused($isSearchFocused)
                .submitLabel(submitLabel)
                .onSubmit {
                    handleSearchSubmit()
                }

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    searchDataSource?.clear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var submitLabel: SubmitLabel {
        if case .hashtag = searchDataSource?.inputType {
            return .search
        }
        return .done
    }

    private func handleSearchSubmit() {
        if case .hashtag = searchDataSource?.inputType {
            Task {
                await searchDataSource?.submitHashtagSearch()
            }
        }
    }

    // MARK: - Explore Content

    private var exploreContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // Featured Follow Packs (horizontal)
                featuredPacksSection

                // Relay Sets (horizontal)
                relaySetsSection

                // All Follow Packs (vertical list)
                allPacksSection
                    .padding(.bottom, 100)
            }
        }
    }

    // MARK: - Search Results Content

    @ViewBuilder
    private var searchResultsContent: some View {
        if let dataSource = searchDataSource {
            switch dataSource.inputType {
            case .empty:
                exploreContent

            case .hashtag(let tag):
                hashtagView(tag: tag, dataSource: dataSource)

            case .nip05:
                nip05ResolvingView(dataSource: dataSource)

            case .npub, .nprofile, .note, .nevent:
                navigationPendingView(dataSource: dataSource)

            case .text, .profileOnly:
                combinedResultsView(dataSource: dataSource)
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Hashtag View

    private func hashtagView(tag: String, dataSource: NDKUnifiedSearchDataSource) -> some View {
        Group {
            if dataSource.hasSubmittedHashtagSearch {
                // Show events list - events stream in as they arrive (no loading spinner)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(dataSource.events, id: \.id) { event in
                            NavigationLink(value: event) {
                                EventSearchResultRow(ndk: state.ndk, event: event)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else {
                // Not yet searched - show prompt
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "number")
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(.blue)
                    Text("#\(tag)")
                        .font(.title.bold())
                    Text("Press return to search this hashtag")
                        .foregroundStyle(.secondary)
                    Button {
                        Task { await searchDataSource?.submitHashtagSearch() }
                    } label: {
                        Text("Search")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(width: 120, height: 44)
                            .background(Color.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: - NIP-05 Resolving View

    private func nip05ResolvingView(dataSource: NDKUnifiedSearchDataSource) -> some View {
        VStack(spacing: 16) {
            Spacer()
            if dataSource.isResolvingNIP05 {
                ProgressView()
                    .scaleEffect(1.2)
                Text("Resolving...")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text(searchText)
                    .font(.body)
            } else if let error = dataSource.error {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(.orange)
                Text("Could not resolve")
                    .font(.headline)
                Text(error.localizedDescription)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Spacer()
        }
        .onChange(of: dataSource.navigateToProfile) { _, pubkey in
            if let pubkey = pubkey {
                navigateToProfilePubkey = pubkey
                dataSource.acknowledgeNavigation()
            }
        }
    }

    // MARK: - Navigation Pending View

    private func navigationPendingView(dataSource: NDKUnifiedSearchDataSource) -> some View {
        // Auto-navigate when data source has navigation target
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading...")
                .font(.headline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // Trigger navigation immediately when this view appears
            if let pubkey = dataSource.navigateToProfile {
                navigateToProfilePubkey = pubkey
                dataSource.acknowledgeNavigation()
            }
        }
    }

    // MARK: - Combined Results View

    private func combinedResultsView(dataSource: NDKUnifiedSearchDataSource) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // Profile results - stream in as they arrive
                if !dataSource.profilePubkeys.isEmpty {
                    Text("Profiles")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 8)

                    ForEach(dataSource.profilePubkeys, id: \.self) { pubkey in
                        NavigationLink(value: pubkey) {
                            ProfileSearchResultRow(ndk: state.ndk, pubkey: pubkey)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Event results (only for text search) - stream in as they arrive
                if case .text = dataSource.inputType, !dataSource.events.isEmpty {
                    Text("Notes")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 8)

                    ForEach(dataSource.events, id: \.id) { event in
                        NavigationLink(value: event) {
                            EventSearchResultRow(ndk: state.ndk, event: event)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
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
        case orange, blue

        var gradient: LinearGradient {
            switch self {
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
        // Search filtering now happens in SearchView
        // This just returns all packs for display
        return packs
    }

    // MARK: - Data Loading

    private func loadContent() async {
        // Load all content types concurrently
        async let packsTask: Void = discoverPacks()
        async let relaysTask: Void = discoverRelaySets()

        _ = await (packsTask, relaysTask)
    }

    private func discoverPacks() async {
        let subscription = state.ndk.subscribe(
            filter: NDKFilter(
                kinds: [39089, 39092],
                limit: 10
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

// MARK: - Event Navigation Helper

/// Helper view to fetch and navigate to an event by ID
private struct EventNavigationHelper: View {
    let ndk: NDK
    let eventId: String
    let relays: [String]?

    @State private var event: NDKEvent?
    @State private var isLoading = true
    @State private var error: Error?

    var body: some View {
        Group {
            if let event = event {
                NavigationLink(value: event) {
                    EmptyView()
                }
            } else if isLoading {
                ProgressView()
            } else if error != nil {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(.orange)
                    Text("Could not load event")
                        .font(.headline)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await fetchEvent()
        }
    }

    private func fetchEvent() async {
        isLoading = true

        // Try cache first
        if let cached = await ndk.cache.getEvent(id: eventId) {
            event = cached
            isLoading = false
            return
        }

        // Fetch from relays
        let filter = NDKFilter(ids: [eventId], limit: 1)
        let subscription = ndk.subscribe(
            filter: filter,
            cachePolicy: .networkOnly,
            relays: relays.map { Set($0) },
            closeOnEose: true
        )

        for await batch in subscription.events {
            if let first = batch.first {
                event = first
                break
            }
        }

        isLoading = false
    }
}
