import SwiftUI
import NDKSwiftCore
import NDKSwiftUI

public struct FeedView: View {
    @Environment(ChirpState.self) private var state
    @State private var subscription: NDKSubscription<NDKEvent>?
    @State private var hasNewPosts = false
    @State private var isScrolledFromTop = false
    @State private var initialLoadTimestamp: Int64?
    @State private var allEvents: [NDKEvent] = []
    @Namespace private var animation

    public init() {}

    public var body: some View {
        Group {
            if let followList = state.ndk.sessionData?.followList, !followList.isEmpty {
                feedContent
                    .task {
                        if subscription == nil {
                            createSubscription(followList: followList)
                        }
                    }
            } else if state.ndk.sessionData == nil {
                emptyFeedContent
            } else {
                noFollowsState
            }
        }
        .navigationTitle("Feed")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if let subscription = subscription {
                        Task { await subscription.refresh() }
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .onChange(of: state.ndk.sessionData?.followList) { _, newFollowList in
            if let newFollowList = newFollowList, !newFollowList.isEmpty {
                createSubscription(followList: newFollowList)
            }
        }
    }

    // MARK: - States

    private var noFollowsState: some View {
        ContentUnavailableView {
            Label("No Follows Yet", systemImage: "person.2.slash")
        } description: {
            Text("Follow some users to see their posts in your feed")
        }
    }

    private var emptyFeedContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {}
        }
    }

    // MARK: - Feed Content

    private var feedContent: some View {
        ZStack(alignment: .top) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(allEvents, id: \.id) { event in
                            NavigationLink(value: event) {
                                FeedPostRow(ndk: state.ndk, event: event)
                            }
                            .buttonStyle(.plain)
                            .id(event.id)
                            .onAppear {
                                trackScrollPosition(event: event, data: allEvents)
                                loadMoreIfNeeded(event: event, data: allEvents, followList: state.ndk.sessionData?.followList)
                            }
                        }
                    }
                }
                .navigationDestination(for: NDKEvent.self) { event in
                    ThreadView(event: event)
                }
                .refreshable {
                    if let subscription = subscription {
                        await subscription.refresh()
                    }
                }
                .onChange(of: subscription?.data) { _, newData in
                    if let newData = newData {
                        withAnimation(.spring(response: 0.3)) {
                            mergeEvents(from: newData)
                        }
                    }
                }
                .onChange(of: allEvents.count) { oldCount, newCount in
                    detectNewPosts(oldCount: oldCount, newCount: newCount, data: allEvents)
                }
                .overlay(alignment: .top) {
                    if hasNewPosts && isScrolledFromTop {
                        newPostsButton(proxy: proxy)
                            .padding(.top, 8)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            }
        }
    }

    private func newPostsButton(proxy: ScrollViewProxy) -> some View {
        Button {
            hasNewPosts = false
            if let firstEvent = allEvents.first {
                withAnimation(.spring(response: 0.4)) {
                    proxy.scrollTo(firstEvent.id, anchor: .top)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up")
                    .font(.caption.weight(.semibold))
                Text("New posts")
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.blue, in: Capsule())
        }
    }

    // MARK: - Subscription Management

    private func createSubscription(followList: Set<String>) {
        subscription = state.ndk.subscribe(
            filter: NDKFilter(
                authors: Array(followList),
                kinds: [1],
                limit: 50
            ),
            cachePolicy: .cacheWithNetwork,
            subscriptionId: "feed"
        )
        initialLoadTimestamp = Int64(Date().timeIntervalSince1970)
    }

    private func trackScrollPosition(event: NDKEvent, data: [NDKEvent]) {
        guard let firstEvent = data.first else { return }
        isScrolledFromTop = event.id != firstEvent.id
    }

    private func detectNewPosts(oldCount: Int, newCount: Int, data: [NDKEvent]) {
        guard let initialTimestamp = initialLoadTimestamp else { return }

        if newCount > oldCount, let newestEvent = data.first {
            if newestEvent.createdAt > initialTimestamp && isScrolledFromTop {
                withAnimation {
                    hasNewPosts = true
                }
            }
        }
    }

    private func loadMoreIfNeeded(event: NDKEvent, data: [NDKEvent], followList: Set<String>?) {
        guard let followList = followList else { return }

        let thresholdIndex = data.index(data.endIndex, offsetBy: -5, limitedBy: data.startIndex) ?? data.startIndex

        if let eventIndex = data.firstIndex(where: { $0.id == event.id }),
           eventIndex >= thresholdIndex {
            loadOlderPosts(followList: followList, data: data)
        }
    }

    private func mergeEvents(from newData: [NDKEvent]) {
        let existingIds = Set(allEvents.map { $0.id })
        let newEvents = newData.filter { !existingIds.contains($0.id) }

        if !newEvents.isEmpty {
            allEvents = (allEvents + newEvents).sorted { $0.createdAt > $1.createdAt }
        }
    }

    private func loadOlderPosts(followList: Set<String>, data: [NDKEvent]) {
        guard let oldestEvent = data.last else { return }

        let olderSubscription = state.ndk.subscribe(
            filter: NDKFilter(
                authors: Array(followList),
                kinds: [1],
                until: oldestEvent.createdAt,
                limit: 50
            ),
            cachePolicy: .cacheWithNetwork,
            subscriptionId: "feed-older-\(UUID().uuidString)",
            closeOnEose: true
        )

        Task {
            for await events in olderSubscription.events {
                await MainActor.run {
                    let existingIds = Set(allEvents.map { $0.id })
                    let newEvents = events.filter { !existingIds.contains($0.id) }

                    if !newEvents.isEmpty {
                        withAnimation {
                            allEvents.append(contentsOf: newEvents)
                            allEvents.sort { $0.createdAt > $1.createdAt }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Feed Post Row (Twitter-style)

struct FeedPostRow: View {
    let ndk: NDK
    let event: NDKEvent

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                // Avatar - tappable to go to profile
                NavigationLink(destination: ProfileView(pubkey: event.pubkey)) {
                    NDKUIProfilePicture(ndk: ndk, pubkey: event.pubkey, size: 40)
                }
                .buttonStyle(.plain)

                // Content column
                VStack(alignment: .leading, spacing: 4) {
                    // Name and time row
                    HStack(spacing: 4) {
                        NavigationLink(destination: ProfileView(pubkey: event.pubkey)) {
                            Text(ndk.profile(for: event.pubkey).displayName)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)

                        Text("·")
                            .foregroundStyle(.secondary)

                        Text(relativeTime)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Spacer()
                    }

                    // Reply indicator
                    NDKUIReplyIndicator(ndk: ndk, event: event)

                    // Post content
                    NDKRichText(content: event.content, tags: event.tags)
                        .ndk(ndk)

                    // Action bar
                    actionBar
                        .padding(.top, 8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // Divider
            Divider()
        }
    }

    private var actionBar: some View {
        HStack(spacing: 0) {
            actionButton(icon: "bubble.right", count: nil)
            Spacer()
            actionButton(icon: "arrow.2.squarepath", count: nil)
            Spacer()
            actionButton(icon: "heart", count: nil)
            Spacer()
            actionButton(icon: "bolt", count: nil)
            Spacer()
            actionButton(icon: "square.and.arrow.up", count: nil)
        }
        .frame(maxWidth: 300, alignment: .leading)
    }

    private func actionButton(icon: String, count: Int?) -> some View {
        Button {
            // Action
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.subheadline)
                if let count = count, count > 0 {
                    Text("\(count)")
                        .font(.caption)
                }
            }
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    private var relativeTime: String {
        formatRelativeTime(event.createdAt)
    }
}

// MARK: - Feed Post Card (Card-style for profiles/explore)

struct FeedPostCard: View {
    let ndk: NDK
    let event: NDKEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with avatar and name
            HStack(spacing: 10) {
                NavigationLink(destination: ProfileView(pubkey: event.pubkey)) {
                    NDKUIProfilePicture(ndk: ndk, pubkey: event.pubkey, size: 40)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    NavigationLink(destination: ProfileView(pubkey: event.pubkey)) {
                        Text(ndk.profile(for: event.pubkey).displayName)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)

                    Text(formatRelativeTime(event.createdAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            // Reply indicator
            NDKUIReplyIndicator(ndk: ndk, event: event)

            // Content
            NDKRichText(content: event.content, tags: event.tags)
                .ndk(ndk)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Shared Utilities

private func formatRelativeTime(_ timestamp: Timestamp) -> String {
    let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
    let now = Date()
    let interval = now.timeIntervalSince(date)

    if interval < 60 {
        return "now"
    } else if interval < 3600 {
        let minutes = Int(interval / 60)
        return "\(minutes)m"
    } else if interval < 86400 {
        let hours = Int(interval / 3600)
        return "\(hours)h"
    } else {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}
