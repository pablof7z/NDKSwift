import SwiftUI
import NDKSwiftCore
import NDKSwiftUI

struct FollowPackFeedView: View {
    @Environment(ChirpState.self) private var state
    let pack: FollowPack

    @State private var subscription: NDKSubscription<NDKEvent>?
    @State private var allEvents: [NDKEvent] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Members bar
                membersBar

                // Feed posts
                if allEvents.isEmpty {
                    emptyState
                } else {
                    ForEach(allEvents, id: \.id) { event in
                        FeedPostCard(ndk: state.ndk, event: event)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    }
                }
            }
        }
        .navigationTitle(pack.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(pack.name)
                        .font(.headline)
                    Text("\(pack.memberCount) accounts")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task {
            createSubscription()
        }
        .onChange(of: subscription?.data) { _, newData in
            if let newData = newData {
                mergeEvents(from: newData)
            }
        }
    }

    // MARK: - Members Bar

    private var membersBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Members")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(pack.pubkeys.prefix(20), id: \.self) { pubkey in
                        VStack(spacing: 6) {
                            NDKUIProfilePicture(ndk: state.ndk, pubkey: pubkey, size: 48)

                            NDKUIDisplayName(ndk: state.ndk, pubkey: pubkey)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .frame(maxWidth: 60)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 12)
        .background(Color(white: 0.05))
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

    private func createSubscription() {
        guard !pack.pubkeys.isEmpty else { return }

        subscription = state.ndk.subscribe(
            filter: NDKFilter(
                authors: pack.pubkeys,
                kinds: [1],
                limit: 100
            ),
            cachePolicy: .cacheWithNetwork,
            subscriptionId: "pack-feed-\(pack.id)"
        )
    }

    private func mergeEvents(from newData: [NDKEvent]) {
        let existingIds = Set(allEvents.map { $0.id })
        let newEvents = newData.filter { !existingIds.contains($0.id) }

        if !newEvents.isEmpty {
            withAnimation(.spring(response: 0.3)) {
                allEvents = (allEvents + newEvents).sorted { $0.createdAt > $1.createdAt }
            }
        }
    }
}
