import SwiftUI
import NDKSwiftCore
import NDKSwiftUI

struct RelayFeedView: View {
    @Environment(ChirpState.self) private var state
    let relay: RankedRelay

    @State private var allEvents: [NDKEvent] = []
    @Environment(\.dismiss) private var dismiss

    private var isSaved: Bool {
        state.feedSourcesManager.isRelaySaved(relay.url)
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Banner header
                bannerSection

                // Info section
                infoSection

                // Divider
                Divider()
                    .padding(.top, 16)

                // Feed posts
                if allEvents.isEmpty {
                    emptyState
                } else {
                    ForEach(allEvents, id: \.id) { event in
                        FeedPostRow(ndk: state.ndk, event: event)
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                saveButton
            }
        }
        .ignoresSafeArea(edges: .top)
        .task {
            await streamEvents()
        }
    }

    // MARK: - Banner Section

    private var bannerSection: some View {
        ZStack(alignment: .bottomLeading) {
            // Background image or gradient
            if let iconURLString = relay.iconURL,
               let iconURL = URL(string: iconURLString) {
                AsyncImage(url: iconURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure, .empty:
                        gradientFallback
                    @unknown default:
                        gradientFallback
                    }
                }
            } else {
                gradientFallback
            }
        }
        .frame(height: 200)
        .clipped()
    }

    private var gradientFallback: some View {
        ZStack {
            LinearGradient(
                colors: [.orange.opacity(0.8), .red.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(.white.opacity(0.3))
        }
    }

    // MARK: - Info Section

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Relay name
            Text(relay.displayName)
                .font(.title2.bold())

            // Description if available
            if let description = relay.description {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Stats row
            HStack(spacing: 16) {
                // Relay URL
                Label(relay.url, systemImage: "link")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                // Popularity indicator
                if relay.appearanceCount > 0 {
                    Label("\(relay.appearanceCount) users", systemImage: "person.2")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    // MARK: - Save Button

    private var saveButton: some View {
        Button {
            if isSaved {
                state.feedSourcesManager.removeRelay(url: relay.url)
            } else {
                state.feedSourcesManager.saveRelay(relay)
            }
        } label: {
            Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                .font(.body.weight(.medium))
                .foregroundStyle(isSaved ? .blue : .primary)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "text.bubble")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)

            Text("Loading posts...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Subscription

    private func streamEvents() async {
        let subscription = state.ndk.subscribe(
            filter: NDKFilter(
                kinds: [1],
                limit: 100
            ),
            cachePolicy: .networkOnly,
            relays: Set([relay.url]),
            exclusiveRelays: true,
            subscriptionId: "relay-feed-\(relay.url)"
        )

        var existingIds = Set<String>()
        for await batch in subscription.events {
            let newEvents = batch.filter { !existingIds.contains($0.id) }
            if !newEvents.isEmpty {
                for event in newEvents {
                    existingIds.insert(event.id)
                }
                withAnimation(.spring(response: 0.3)) {
                    allEvents = (allEvents + newEvents).sorted { $0.createdAt > $1.createdAt }
                }
            }
        }
    }
}
