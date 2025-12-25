import SwiftUI
import NDKSwiftCore
import NDKSwiftCashu

/// Discovered mint from NIP-87
struct DiscoveredMint: Identifiable, Sendable {
    let id: String  // mint URL
    let url: URL
    let name: String?
    let description: String?
    var recommendationCount: Int

    var displayName: String {
        name ?? url.host ?? url.absoluteString
    }
}

/// NIP-87 Mint browser view
struct MintBrowserView: View {
    @Environment(ChirpState.self) private var state
    @Binding var selectedMints: Set<String>

    @State private var discoveredMints: [DiscoveredMint] = []
    @State private var searchText = ""

    var body: some View {
        Group {
            if filteredMints.isEmpty && searchText.isEmpty {
                // Show empty state that updates as mints stream in
                ContentUnavailableView(
                    "Discovering Mints",
                    systemImage: "building.columns",
                    description: Text("Mints will appear as they're discovered")
                )
            } else if filteredMints.isEmpty {
                ContentUnavailableView(
                    "No Mints Found",
                    systemImage: "building.columns",
                    description: Text("No mints match your search")
                )
            } else {
                List(filteredMints) { mint in
                    MintRow(
                        mint: mint,
                        isSelected: selectedMints.contains(mint.id)
                    ) {
                        toggleMint(mint)
                    }
                }
                .listStyle(.plain)
                .searchable(text: $searchText, prompt: "Search mints")
            }
        }
        .task {
            await discoverMints()
        }
    }

    private var filteredMints: [DiscoveredMint] {
        if searchText.isEmpty {
            return discoveredMints.sorted { $0.recommendationCount > $1.recommendationCount }
        }

        return discoveredMints
            .filter { mint in
                mint.displayName.localizedCaseInsensitiveContains(searchText) ||
                mint.url.absoluteString.localizedCaseInsensitiveContains(searchText)
            }
            .sorted { $0.recommendationCount > $1.recommendationCount }
    }

    private func toggleMint(_ mint: DiscoveredMint) {
        if selectedMints.contains(mint.id) {
            selectedMints.remove(mint.id)
        } else {
            selectedMints.insert(mint.id)
        }
    }

    private func discoverMints() async {
        // Track discovered mints and their recommendations
        var mintsByURL: [String: DiscoveredMint] = [:]
        var recommendationCounts: [String: Int] = [:]

        // Query mint announcements (kind 38172) - stream as they arrive
        let announcementSubscription = state.ndk.subscribe(
            filter: NDKFilter(
                kinds: [38172],
                limit: 100
            ),
            cachePolicy: .cacheWithNetwork,
            subscriptionId: "mint-discovery-announcements"
        )

        // Query recommendations (kind 38000 with k=38172) - stream as they arrive
        let recommendationSubscription = state.ndk.subscribe(
            filter: NDKFilter(
                kinds: [38000],
                limit: 200,
                tags: ["k": ["38172"]]
            ),
            cachePolicy: .cacheWithNetwork,
            subscriptionId: "mint-discovery-recommendations"
        )

        // Process announcements as they stream in
        Task {
            for await batch in announcementSubscription.events {
                for event in batch {
                    let announcement = NDKCashuMintAnnouncement(event: event)

                    // Skip testnet mints
                    if announcement.network != nil && announcement.network != "mainnet" {
                        continue
                    }

                    guard let mintURL = announcement.mintURL,
                          let url = URL(string: mintURL) else {
                        continue
                    }

                    let mint = DiscoveredMint(
                        id: mintURL,
                        url: url,
                        name: announcement.name,
                        description: announcement.description,
                        recommendationCount: recommendationCounts[mintURL] ?? 0
                    )

                    mintsByURL[mintURL] = mint
                }

                // Update UI immediately as each batch arrives
                await MainActor.run {
                    discoveredMints = Array(mintsByURL.values)
                }
            }
        }

        // Process recommendations as they stream in
        Task {
            for await batch in recommendationSubscription.events {
                for event in batch {
                    let recommendation = NDKMintRecommendation(event: event)

                    guard let mintURL = recommendation.mintURL else { continue }

                    recommendationCounts[mintURL, default: 0] += 1

                    // Update existing mint's recommendation count
                    if var mint = mintsByURL[mintURL] {
                        mint.recommendationCount = recommendationCounts[mintURL] ?? 0
                        mintsByURL[mintURL] = mint
                    }
                }

                // Update UI immediately as each batch arrives
                await MainActor.run {
                    discoveredMints = Array(mintsByURL.values)
                }
            }
        }
    }
}

/// Individual mint row
struct MintRow: View {
    let mint: DiscoveredMint
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? .green : .secondary)

                // Mint info
                VStack(alignment: .leading, spacing: 2) {
                    Text(mint.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    if let description = mint.description, !description.isEmpty {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Text(mint.url.absoluteString)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer()

                // Recommendation count
                if mint.recommendationCount > 0 {
                    VStack(spacing: 2) {
                        Text("\(mint.recommendationCount)")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("recs")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        MintBrowserView(selectedMints: .constant(["https://mint.minibits.cash"]))
            .environment(ChirpState(
                ndk: NDK(relayURLs: []),
                authManager: NDKAuthManager(ndk: NDK(relayURLs: [])),
                relayCollection: NDKRelayCollection(ndk: NDK(relayURLs: []))
            ))
    }
}
