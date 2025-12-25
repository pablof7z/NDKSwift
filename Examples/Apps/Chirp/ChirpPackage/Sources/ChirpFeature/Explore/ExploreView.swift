import SwiftUI
import NDKSwiftCore
import NDKSwiftUI

public struct ExploreView: View {
    @Environment(ChirpState.self) private var state
    @State private var packs: [FollowPack] = []
    @State private var searchText = ""
    @State private var selectedCategory = "All"

    private let categories = ["All", "Tech", "Art", "Bitcoin", "Music", "News"]

    public init() {}

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // Header
                header
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)

                // Search bar
                searchBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)

                // Categories
                categoryChips
                    .padding(.bottom, 16)

                // Featured pack (first one with most members)
                if let featured = featuredPack {
                    NavigationLink(destination: FollowPackFeedView(pack: featured)) {
                        FollowPackCardView(ndk: state.ndk, pack: featured, isFeatured: true)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }

                // Section title
                Text("Popular Packs")
                    .font(.title3.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                // Pack grid
                packGrid
                    .padding(.horizontal, 16)
                    .padding(.bottom, 100)
            }
        }
        .navigationTitle("Explore")
        .task {
            await discoverPacks()
        }
        .refreshable {
            await discoverPacks()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Explore")
                .font(.largeTitle.weight(.bold))

            Text("Discover communities to follow")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search follow packs...", text: $searchText)
                .textFieldStyle(.plain)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Category Chips

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories, id: \.self) { category in
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            selectedCategory = category
                        }
                    } label: {
                        Text(category)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                selectedCategory == category
                                    ? Color.accentColor
                                    : Color(.secondarySystemBackground)
                            )
                            .foregroundStyle(
                                selectedCategory == category
                                    ? Color.white
                                    : Color.primary
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Pack Grid

    private var packGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]

        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(filteredPacks) { pack in
                NavigationLink(destination: FollowPackFeedView(pack: pack)) {
                    FollowPackCardView(ndk: state.ndk, pack: pack)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Computed Properties

    private var featuredPack: FollowPack? {
        packs.first
    }

    private var filteredPacks: [FollowPack] {
        // Skip featured pack, filter by search
        let remaining = packs.dropFirst()

        if searchText.isEmpty {
            return Array(remaining)
        }

        return remaining.filter { pack in
            pack.name.localizedCaseInsensitiveContains(searchText) ||
            (pack.description?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    // MARK: - Data Loading

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

        // Stream packs as they arrive
        for await batch in subscription.events {
            for event in batch {
                guard let pack = FollowPack(event: event) else { continue }
                guard pack.memberCount > 0 else { continue }

                // Dedupe by name (case-insensitive)
                let key = pack.name.lowercased()
                if let existing = discovered[key] {
                    // Keep the one with more members
                    if pack.memberCount > existing.memberCount {
                        discovered[key] = pack
                    }
                } else {
                    discovered[key] = pack
                }
            }

            // Update UI with current discoveries
            await MainActor.run {
                packs = discovered.values
                    .sorted { $0.memberCount > $1.memberCount }
                    .prefix(20)
                    .map { $0 }
            }

            // Stop after collecting enough
            if discovered.count >= 20 { break }
        }
    }
}
