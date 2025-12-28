import SwiftUI
import UIKit
import NDKSwiftCore
import NDKSwiftUI

public struct FeedView: View {
    @Environment(ChirpState.self) private var state
    @State private var hasNewPosts = false
    @State private var isScrolledFromTop = false
    @State private var initialLoadTimestamp: Int64?
    @State private var allEvents: [NDKEvent] = []
    @State private var streamTask: Task<Void, Never>?
    @State private var showReplyComposer = false
    @State private var replyToEvent: NDKEvent?
    @Namespace private var animation

    public init() {}

    public var body: some View {
        Group {
            if let followList = state.ndk.sessionData?.followList, !followList.isEmpty {
                feedContent
                    .task {
                        await streamEvents(followList: followList)
                    }
            } else if state.ndk.sessionData == nil {
                emptyFeedContent
            } else {
                noFollowsState
            }
        }
        .navigationTitle("Feed")
        .navigationBarTitleDisplayMode(.large)
        .onChange(of: state.ndk.sessionData?.followList) { _, newFollowList in
            if let newFollowList = newFollowList, !newFollowList.isEmpty {
                streamTask?.cancel()
                streamTask = Task {
                    await streamEvents(followList: newFollowList)
                }
            }
        }
        .sheet(isPresented: $showReplyComposer) {
            ComposerView(ndk: state.ndk, replyTo: replyToEvent)
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
                            FeedPostRow(
                                ndk: state.ndk,
                                event: event,
                                navigateToThread: event,
                                onReply: { eventToReply in
                                    replyToEvent = eventToReply
                                    showReplyComposer = true
                                }
                            )
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
                    streamTask?.cancel()
                    if let followList = state.ndk.sessionData?.followList {
                        await streamEvents(followList: followList)
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
            newPostsLabel
        }
    }

    @ViewBuilder
    private var newPostsLabel: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up")
                    .font(.caption.weight(.semibold))
                Text("New posts")
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(.tint)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(.regular.interactive(), in: Capsule())
        } else {
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

    private func streamEvents(followList: Set<String>) async {
        initialLoadTimestamp = Int64(Date().timeIntervalSince1970)

        let subscription = state.ndk.subscribe(
            filter: NDKFilter(
                authors: Array(followList),
                kinds: [1],
                limit: 10
            ),
            cachePolicy: .cacheWithNetwork,
            subscriptionId: "feed"
        )

        var existingIds = Set(allEvents.map { $0.id })
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

    private func loadOlderPosts(followList: Set<String>, data: [NDKEvent]) {
        guard let oldestEvent = data.last else { return }

        let ndk = state.ndk
        Task { @MainActor in
            let olderEvents = await ndk.fetchEvents(
                filter: NDKFilter(
                    authors: Array(followList),
                    kinds: [1],
                    until: oldestEvent.createdAt,
                    limit: 10
                ),
                cachePolicy: .cacheWithNetwork,
                timeout: 10.0
            )

            let existingIds = Set(allEvents.map { $0.id })
            let newEvents = olderEvents.filter { !existingIds.contains($0.id) }

            if !newEvents.isEmpty {
                withAnimation {
                    allEvents.append(contentsOf: newEvents)
                    allEvents.sort { $0.createdAt > $1.createdAt }
                }
            }
        }
    }
}

// MARK: - Feed Post Row (Twitter-style)

struct FeedPostRow: View {
    let ndk: NDK
    let event: NDKEvent
    var navigateToThread: NDKEvent?
    var onReply: ((NDKEvent) -> Void)?

    // Store profile reference so SwiftUI holds it and observes changes
    @State private var profile: NDKProfile?
    @State private var repostState: RepostState?
    @State private var reactionState: ReactionState?

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
                            Text(profile?.displayName ?? "...")
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

                    // Post content - tappable to navigate to thread
                    if let threadEvent = navigateToThread {
                        NavigationLink(value: threadEvent) {
                            NDKRichText(content: event.content, tags: event.tags)
                                .ndk(ndk)
                        }
                        .buttonStyle(.plain)
                    } else {
                        NDKRichText(content: event.content, tags: event.tags)
                            .ndk(ndk)
                    }

                    // Action bar - NOT inside NavigationLink
                    actionBar
                        .padding(.top, 8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // Divider
            Divider()
        }
        .task {
            // Load profile and hold reference so SwiftUI observes changes
            profile = ndk.profile(for: event.pubkey)

            // Initialize and start interaction state observation
            let repost = RepostState(ndk: ndk, event: event)
            repostState = repost
            await repost.start()
        }
        .task {
            let reaction = ReactionState(ndk: ndk, event: event)
            reactionState = reaction
            await reaction.start()
        }
    }

    private var actionBar: some View {
        HStack(spacing: 0) {
            replyButton
            Spacer()
            repostButton
            Spacer()
            reactionButton
            Spacer()
            actionButton(icon: "bolt", count: nil)
            Spacer()
            moreMenu
        }
        .frame(maxWidth: 300, alignment: .leading)
    }

    private var replyButton: some View {
        Button {
            onReply?(event)
        } label: {
            Image(systemName: "bubble.right")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    private var repostButton: some View {
        Button {
            Task {
                do {
                    try await repostState?.toggle()
                } catch {
                    print("Repost failed: \(error)")
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.2.squarepath")
                    .font(.subheadline)
                if let count = repostState?.count, count > 0 {
                    Text("\(count)")
                        .font(.caption)
                }
            }
            .foregroundStyle(repostState?.hasReposted == true ? .green : .secondary)
        }
        .buttonStyle(.plain)
    }

    private var reactionButton: some View {
        Button {
            Task {
                do {
                    try await reactionState?.toggle()
                } catch {
                    print("Reaction failed: \(error)")
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: reactionState?.hasReacted == true ? "heart.fill" : "heart")
                    .font(.subheadline)
                if let count = reactionState?.count, count > 0 {
                    Text("\(count)")
                        .font(.caption)
                }
            }
            .foregroundStyle(reactionState?.hasReacted == true ? .red : .secondary)
        }
        .buttonStyle(.plain)
    }

    private var moreMenu: some View {
        Menu {
            Button {
                if let bech32 = try? Bech32.note(from: event.id) {
                    UIPasteboard.general.string = bech32
                }
            } label: {
                Label("Copy Note ID", systemImage: "doc.on.doc")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
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

    // Store profile reference so SwiftUI holds it and observes changes
    @State private var profile: NDKProfile?

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
                        Text(profile?.displayName ?? "...")
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
        .task {
            // Load profile and hold reference so SwiftUI observes changes
            profile = ndk.profile(for: event.pubkey)
        }
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
