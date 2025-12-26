import SwiftUI
import NDKSwiftCore
import NDKSwiftUI

public struct ThreadView: View {
    @Environment(ChirpState.self) private var state

    let event: NDKEvent
    @State private var ancestors: [NDKEvent] = []
    @State private var replies: [NDKEvent] = []
    @State private var isLoadingAncestors = true
    @State private var isLoadingReplies = true

    public init(event: NDKEvent) {
        self.event = event
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // Ancestors (parent posts)
                    ForEach(Array(ancestors.enumerated()), id: \.element.id) { index, ancestor in
                        NavigationLink(value: ancestor) {
                            ThreadedPostRow(
                                ndk: state.ndk,
                                event: ancestor,
                                position: .ancestor,
                                hasConnectionAbove: index > 0,
                                hasConnectionBelow: true
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    // Active post (emphasized)
                    ActivePostView(
                        ndk: state.ndk,
                        event: event,
                        hasConnectionAbove: !ancestors.isEmpty,
                        hasConnectionBelow: !replies.isEmpty
                    )
                    .id("activePost")

                    // Replies
                    ForEach(Array(replies.enumerated()), id: \.element.id) { index, reply in
                        NavigationLink(value: reply) {
                            ThreadedPostRow(
                                ndk: state.ndk,
                                event: reply,
                                position: .reply,
                                hasConnectionAbove: index == 0,
                                hasConnectionBelow: false
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if replies.isEmpty && !isLoadingReplies {
                        HStack {
                            Spacer()
                            Text("No replies yet")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding()
                    }
                }
            }
            .onChange(of: ancestors) { _, _ in
                withAnimation {
                    proxy.scrollTo("activePost", anchor: .top)
                }
            }
        }
        .navigationTitle("Thread")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: NDKEvent.self) { event in
            ThreadView(event: event)
        }
        .task {
            await loadAncestors()
            isLoadingAncestors = false
        }
        .task {
            await loadReplies()
            isLoadingReplies = false
        }
    }

    private func loadAncestors() async {
        var loadedAncestors: [NDKEvent] = []
        var currentEvent = event

        // Walk up the reply chain
        while let parentId = findParentEventId(event: currentEvent) {
            let filter = NDKFilter(ids: [parentId])
            let subscription = state.ndk.subscribe(
                filter: filter,
                cachePolicy: .cacheWithNetwork,
                closeOnEose: true
            )

            var foundParent: NDKEvent?
            for await batch in subscription.events {
                if let first = batch.first {
                    foundParent = first
                    break
                }
            }

            guard let parent = foundParent else { break }

            loadedAncestors.insert(parent, at: 0)
            currentEvent = parent
        }

        ancestors = loadedAncestors
    }

    private func findParentEventId(event: NDKEvent) -> String? {
        // First check for explicit "reply" marker (direct parent)
        if let replyTag = event.tags.first(where: { tag in
            tag.count > 3 && tag.first == "e" && tag[safe: 3] == "reply"
        }) {
            return replyTag[safe: 1]
        }

        // If no reply marker, check for root marker (for direct replies to root)
        if let rootTag = event.tags.first(where: { tag in
            tag.count > 3 && tag.first == "e" && tag[safe: 3] == "root"
        }) {
            return rootTag[safe: 1]
        }

        // Legacy: if there's only one e-tag without markers, it's the parent
        let eTags = event.tags.filter { $0.first == "e" }
        if eTags.count == 1 {
            return eTags.first?[safe: 1]
        }

        return nil
    }

    private func loadReplies() async {
        let filter = NDKFilter(
            kinds: [1, 1111], // text notes + generic replies
            limit: 100,
            tags: ["e": [event.id]]
        )

        let subscription = state.ndk.subscribe(
            filter: filter,
            cachePolicy: .cacheWithNetwork,
            closeOnEose: true
        )

        for await batch in subscription.events {
            let newReplies = batch.filter { replyEvent in
                replyEvent.id != event.id && !replies.contains(where: { $0.id == replyEvent.id })
            }
            if !newReplies.isEmpty {
                replies.append(contentsOf: newReplies)
                replies.sort { $0.createdAt < $1.createdAt }
            }
        }
    }
}
