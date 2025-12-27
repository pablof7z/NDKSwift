import SwiftUI
import NDKSwiftCore
import NDKSwiftUI

public struct ProfileView: View {
    @Environment(ChirpState.self) private var state
    @State private var allEvents: [NDKEvent] = []
    @State private var selectedTab: ProfileTab = .posts

    /// The pubkey to display. If nil, shows current user's profile.
    let pubkey: String?

    enum ProfileTab: String, CaseIterable {
        case posts = "Posts"
        case replies = "Replies"
        case media = "Media"
    }

    public init(pubkey: String? = nil) {
        self.pubkey = pubkey
    }

    private var displayPubkey: String? {
        pubkey ?? state.ndk.sessionData?.pubkey
    }

    public var body: some View {
        Group {
            if let pubkey = displayPubkey {
                profileContent(pubkey: pubkey)
            } else {
                EmptyStateView(
                    icon: "person.slash",
                    title: "No Account",
                    message: "Please log in to view your profile"
                )
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func profileContent(pubkey: String) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                // Profile Header
                ProfileHeaderView(ndk: state.ndk, pubkey: pubkey)

                // Tab Selector
                tabSelector

                // Content based on tab
                tabContent(pubkey: pubkey)
                    .padding(.top, 8)
            }
        }
        .ignoresSafeArea(edges: .top)
    }

    private var tabSelector: some View {
        HStack(spacing: 0) {
            ForEach(ProfileTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 10) {
                        Text(tab.rawValue)
                            .font(.subheadline.weight(selectedTab == tab ? .semibold : .regular))
                            .foregroundStyle(selectedTab == tab ? .primary : .secondary)

                        Rectangle()
                            .fill(selectedTab == tab ? Color.accentColor : Color.clear)
                            .frame(height: 3)
                            .clipShape(Capsule())
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    @ViewBuilder
    private func tabContent(pubkey: String) -> some View {
        switch selectedTab {
        case .posts:
            postsContent(pubkey: pubkey)
        case .replies:
            EmptyStateView(
                icon: "bubble.left.and.bubble.right",
                title: "No Replies",
                message: "Your replies will appear here"
            )
            .frame(minHeight: 300)
        case .media:
            EmptyStateView(
                icon: "photo.on.rectangle",
                title: "No Media",
                message: "Posts with images will appear here"
            )
            .frame(minHeight: 300)
        }
    }

    @ViewBuilder
    private func postsContent(pubkey: String) -> some View {
        LazyVStack(spacing: 0) {
            if allEvents.isEmpty {
                Text("No posts yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 100)
            } else {
                ForEach(allEvents, id: \.id) { event in
                    NavigationLink(value: event) {
                        FeedPostRow(ndk: state.ndk, event: event)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.bottom, 100)
        .navigationDestination(for: NDKEvent.self) { event in
            ThreadView(event: event)
        }
        .task {
            await streamEvents(pubkey: pubkey)
        }
    }

    private func streamEvents(pubkey: String) async {
        let subscription = state.ndk.subscribe(
            filter: NDKFilter(
                authors: [pubkey],
                kinds: [1],
                limit: 50
            ),
            cachePolicy: .cacheWithNetwork,
            subscriptionId: "profile-posts"
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
