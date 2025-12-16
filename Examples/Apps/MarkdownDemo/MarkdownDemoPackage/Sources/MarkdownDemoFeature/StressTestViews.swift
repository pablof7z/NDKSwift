import SwiftUI
import NDKSwiftCore
import NDKSwiftUI

// MARK: - Constants

private let testPubkey = "fa984bd7dbb282f07e16e7ae87b26a2a7b9b90b7246a44771f0cf5ae58018f52"

// MARK: - Feed Tab View (Kind:1 from follows)

struct FeedTabView: View {
    let ndk: NDK
    let rendererStyle: RendererStyle

    @State private var followListDataSource: NDKUIFollowListDataSource?
    @State private var eventDataSource: NDKEventDataSource?
    @State private var lastTappedItem = ""
    @State private var searchDataSource: NDKSearchDataSource?
    @State private var searchText: String = ""

    var body: some View {
        NavigationView {
            Group {
                // Show search results when searching
                if !searchText.isEmpty, let searchDataSource = searchDataSource {
                    if searchDataSource.isLoading {
                        ProgressView("Searching...")
                    } else if searchDataSource.events.isEmpty {
                        ContentUnavailableView(
                            "No Results",
                            systemImage: "magnifyingglass",
                            description: Text("No notes found matching '\(searchText)'")
                        )
                    } else {
                        feedList(events: searchDataSource.events)
                    }
                }
                // Show regular feed when not searching
                else if let eventDataSource = eventDataSource {
                    if eventDataSource.events.isEmpty && eventDataSource.isLoading {
                        ProgressView("Loading feed...")
                    } else if eventDataSource.events.isEmpty {
                        ContentUnavailableView(
                            "No Posts",
                            systemImage: "text.bubble",
                            description: Text("No kind:1 events found from followed users")
                        )
                    } else {
                        feedList(events: eventDataSource.events)
                    }
                } else if let followListDataSource = followListDataSource {
                    if followListDataSource.isLoading || followListDataSource.followList.isEmpty {
                        ProgressView("Loading follows...")
                    } else {
                        ProgressView("Subscribing to events...")
                    }
                } else {
                    ProgressView("Initializing...")
                }
            }
            .navigationTitle("Feed (\(searchText.isEmpty ? (eventDataSource?.events.count ?? 0) : (searchDataSource?.events.count ?? 0)))")
            .navigationBarTitleDisplayMode(.inline)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                if !lastTappedItem.isEmpty {
                    tappedItemBanner
                }

                // Search bar
                NDKUISearchBar(text: $searchText, onClear: {
                    searchDataSource?.clear()
                })
            }
        }
        .task {
            // Create the follow list data source - reactive updates handle the rest
            followListDataSource = NDKUIFollowListDataSource(ndk: ndk, pubkey: testPubkey)
            // Create search data source
            searchDataSource = NDKSearchDataSource(ndk: ndk)
        }
        .onChange(of: searchText) { _, newValue in
            searchDataSource?.search(query: newValue)
        }
        .onChange(of: followListDataSource?.followList) { _, newFollowList in
            updateEventSubscription(for: newFollowList)
        }
    }

    @ViewBuilder
    private func feedList(events: [NDKEvent]) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(events, id: \.id) { event in
                    eventCard(for: event)

                    if event.id != events.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func eventCard(for event: NDKEvent) -> some View {
        VStack(alignment: .leading, spacing: NDKEventViewStyles.verticalSpacing(for: .feed)) {
            // Author header
            NDKUIEventAuthorHeader(
                ndk: ndk,
                pubkey: event.pubkey,
                timestamp: event.createdAt,
                style: .standard
            )

            // Content using selected renderer style
            richTextContent(for: event)
        }
        .padding(NDKEventViewStyles.containerPadding(for: .feed))
    }

    @ViewBuilder
    private func richTextContent(for event: NDKEvent) -> some View {
        switch rendererStyle {
        case .default:
            DefaultStyleRichText(content: event.content)
            .ndk(ndk)
            .onMentionTap { pubkey in lastTappedItem = "Mention: @\(pubkey.prefix(8))..." }
            .onHashtagTap { tag in lastTappedItem = "Hashtag: #\(tag)" }
            .onLinkTap { url in lastTappedItem = "Link: \(url.host ?? url.absoluteString)" }
            .onImageTap { url in lastTappedItem = "Image: \(url.lastPathComponent)" }
            .onEventTap { event in lastTappedItem = "Event: \(event.id.prefix(8))..." }

        case .compact:
            CompactStyleRichText(content: event.content)
            .ndk(ndk)
            .onMentionTap { pubkey in lastTappedItem = "Mention: @\(pubkey.prefix(8))..." }
            .onHashtagTap { tag in lastTappedItem = "Hashtag: #\(tag)" }
            .onLinkTap { url in lastTappedItem = "Link: \(url.host ?? url.absoluteString)" }
            .onImageTap { url in lastTappedItem = "Image: \(url.lastPathComponent)" }
            .onEventTap { event in lastTappedItem = "Event: \(event.id.prefix(8))..." }

        case .pill:
            PillStyleRichText(content: event.content)
            .ndk(ndk)
            .onMentionTap { pubkey in lastTappedItem = "Mention: @\(pubkey.prefix(8))..." }
            .onHashtagTap { tag in lastTappedItem = "Hashtag: #\(tag)" }
            .onLinkTap { url in lastTappedItem = "Link: \(url.host ?? url.absoluteString)" }
            .onImageTap { url in lastTappedItem = "Image: \(url.lastPathComponent)" }
            .onEventTap { event in lastTappedItem = "Event: \(event.id.prefix(8))..." }
        }
    }

    private var tappedItemBanner: some View {
        HStack {
            Image(systemName: "hand.tap.fill")
                .foregroundColor(.blue)
            Text(lastTappedItem)
                .font(.caption)
            Spacer()
            Button("Clear") {
                lastTappedItem = ""
            }
            .font(.caption)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private func updateEventSubscription(for followList: Set<String>?) {
        guard let followList = followList, !followList.isEmpty else {
            return
        }

        // Subscribe to kind:1 events from follows
        let filter = NDKFilter(
            authors: Array(followList),
            kinds: [EventKind.textNote]
        )

        eventDataSource = NDKEventDataSource(
            ndk: ndk,
            filter: filter,
            sortDescending: true
        )
    }
}

// MARK: - Articles Tab View (Kind:30023 from follows)

struct ArticlesTabView: View {
    let ndk: NDK
    let rendererStyle: RendererStyle

    @State private var followListDataSource: NDKUIFollowListDataSource?
    @State private var eventDataSource: NDKEventDataSource?
    @State private var selectedArticle: NDKEvent?

    var body: some View {
        NavigationStack {
            Group {
                if let eventDataSource = eventDataSource {
                    if eventDataSource.events.isEmpty && eventDataSource.isLoading {
                        ProgressView("Loading articles...")
                    } else if eventDataSource.events.isEmpty {
                        ContentUnavailableView(
                            "No Articles",
                            systemImage: "doc.text",
                            description: Text("No kind:30023 articles found from followed users")
                        )
                    } else {
                        articlesList(events: eventDataSource.events)
                    }
                } else if let followListDataSource = followListDataSource {
                    if followListDataSource.isLoading || followListDataSource.followList.isEmpty {
                        ProgressView("Loading follows...")
                    } else {
                        ProgressView("Subscribing to articles...")
                    }
                } else {
                    ProgressView("Initializing...")
                }
            }
            .navigationTitle("Articles (\(eventDataSource?.events.count ?? 0))")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $selectedArticle) { article in
                ArticleDetailView(ndk: ndk, event: article, rendererStyle: rendererStyle)
            }
        }
        .task {
            followListDataSource = NDKUIFollowListDataSource(ndk: ndk, pubkey: testPubkey)
        }
        .onChange(of: followListDataSource?.followList) { _, newFollowList in
            updateEventSubscription(for: newFollowList)
        }
    }

    @ViewBuilder
    private func articlesList(events: [NDKEvent]) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(events, id: \.id) { event in
                    articlePreviewCard(for: event)
                        .onTapGesture {
                            selectedArticle = event
                        }

                    if event.id != events.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func articlePreviewCard(for event: NDKEvent) -> some View {
        VStack(alignment: .leading, spacing: NDKEventViewStyles.verticalSpacing(for: .feed)) {
            // Author header
            NDKUIEventAuthorHeader(
                ndk: ndk,
                pubkey: event.pubkey,
                timestamp: event.createdAt,
                style: .standard
            )

            // Article preview
            VStack(alignment: .leading, spacing: NDKEventViewStyles.verticalSpacing(for: .feed)) {
                // Cover image
                if let imageURL = extractImageURL(from: event) {
                    CachedAsyncImage(url: imageURL) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                    }
                    .frame(height: NDKEventViewStyles.imageHeight(for: .feed))
                    .clipped()
                }

                // Title
                if let title = extractTitle(from: event) {
                    Text(title)
                        .font(NDKEventViewStyles.titleFont(for: .feed))
                        .fontWeight(.semibold)
                        .lineLimit(NDKEventViewStyles.titleLineLimit(for: .feed))
                }

                // Summary
                if let summary = extractSummary(from: event) {
                    Text(summary)
                        .font(NDKEventViewStyles.contentFont(for: .feed))
                        .foregroundStyle(.secondary)
                        .lineLimit(NDKEventViewStyles.contentLineLimit(for: .feed))
                }

                // Metadata
                HStack {
                    Image(systemName: "doc.text")
                        .font(NDKEventViewStyles.captionFont(for: .feed))
                        .foregroundStyle(.secondary)

                    Text("Article")
                        .font(NDKEventViewStyles.captionFont(for: .feed))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(NDKEventViewStyles.captionFont(for: .feed))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(NDKEventViewStyles.containerPadding(for: .feed))
    }

    private func updateEventSubscription(for followList: Set<String>?) {
        guard let followList = followList, !followList.isEmpty else {
            return
        }

        // Subscribe to kind:30023 events from follows
        let filter = NDKFilter(
            authors: Array(followList),
            kinds: [EventKind.longFormContent]
        )

        eventDataSource = NDKEventDataSource(
            ndk: ndk,
            filter: filter,
            sortDescending: true
        )
    }

    // MARK: - Helper Methods

    private func extractTitle(from event: NDKEvent) -> String? {
        event.tagValue("title")
    }

    private func extractSummary(from event: NDKEvent) -> String? {
        event.tagValue("summary") ?? event.tagValue("alt")
    }

    private func extractImageURL(from event: NDKEvent) -> URL? {
        if let imageTag = event.tagValue("image") {
            return URL(string: imageTag)
        }
        return nil
    }
}

// MARK: - Article Detail View

struct ArticleDetailView: View {
    let ndk: NDK
    let event: NDKEvent
    let rendererStyle: RendererStyle

    @State private var lastTappedItem = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Cover image
                if let imageURL = extractImageURL() {
                    CachedAsyncImage(url: imageURL) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                    }
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                // Title
                if let title = extractTitle() {
                    Text(title)
                        .font(.title)
                        .fontWeight(.bold)
                }

                // Author
                NDKUIEventAuthorHeader(
                    ndk: ndk,
                    pubkey: event.pubkey,
                    timestamp: event.createdAt,
                    style: .standard
                )

                Divider()

                // Full article content using markdown renderer
                markdownContent
            }
            .padding()
        }
        .navigationTitle("Article")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if !lastTappedItem.isEmpty {
                tappedItemBanner
            }
        }
    }

    @ViewBuilder
    private var markdownContent: some View {
        switch rendererStyle {
        case .default:
            DefaultStyleMarkdown(
                content: event.content,
                blockConfig: .default
            )
            .ndk(ndk)
            .onMentionTap { pubkey in lastTappedItem = "Mention: @\(pubkey.prefix(8))..." }
            .onHashtagTap { tag in lastTappedItem = "Hashtag: #\(tag)" }
            .onLinkTap { url in lastTappedItem = "Link: \(url.host ?? url.absoluteString)" }

        case .compact:
            CompactStyleMarkdown(
                content: event.content,
                blockConfig: .default
            )
            .ndk(ndk)
            .onMentionTap { pubkey in lastTappedItem = "Mention: @\(pubkey.prefix(8))..." }
            .onHashtagTap { tag in lastTappedItem = "Hashtag: #\(tag)" }
            .onLinkTap { url in lastTappedItem = "Link: \(url.host ?? url.absoluteString)" }

        case .pill:
            PillStyleMarkdown(
                content: event.content,
                blockConfig: .default
            )
            .ndk(ndk)
            .onMentionTap { pubkey in lastTappedItem = "Mention: @\(pubkey.prefix(8))..." }
            .onHashtagTap { tag in lastTappedItem = "Hashtag: #\(tag)" }
            .onLinkTap { url in lastTappedItem = "Link: \(url.host ?? url.absoluteString)" }
        }
    }

    private var tappedItemBanner: some View {
        HStack {
            Image(systemName: "hand.tap.fill")
                .foregroundColor(.blue)
            Text(lastTappedItem)
                .font(.caption)
            Spacer()
            Button("Clear") {
                lastTappedItem = ""
            }
            .font(.caption)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    // MARK: - Helper Methods

    private func extractTitle() -> String? {
        event.tagValue("title")
    }

    private func extractImageURL() -> URL? {
        if let imageTag = event.tagValue("image") {
            return URL(string: imageTag)
        }
        return nil
    }
}

