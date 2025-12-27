import SwiftUI
import NDKSwiftCore
import NDKSwiftUI

struct FollowPackFeedView: View {
    @Environment(ChirpState.self) private var state
    let pack: FollowPack

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
                        FeedPostRow(ndk: state.ndk, event: event)
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
            await streamEvents()
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
                        MemberAvatarView(ndk: state.ndk, pubkey: pubkey)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground))
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
        guard !pack.pubkeys.isEmpty else { return }

        let subscription = state.ndk.subscribe(
            filter: NDKFilter(
                authors: pack.pubkeys,
                kinds: [1],
                limit: 100
            ),
            cachePolicy: .cacheWithNetwork,
            subscriptionId: "pack-feed-\(pack.id)"
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

// MARK: - Member Avatar View

private struct MemberAvatarView: View {
    let ndk: NDK
    let pubkey: String

    // Store profile reference so SwiftUI holds it and observes changes
    @State private var profile: NDKProfile?

    var body: some View {
        VStack(spacing: 6) {
            NDKUIProfilePicture(ndk: ndk, pubkey: pubkey, size: 48)

            Text(profile?.displayName ?? "...")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: 60)
        }
        .task {
            profile = ndk.profile(for: pubkey)
        }
    }
}
