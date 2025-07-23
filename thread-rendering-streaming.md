# Streaming Thread Rendering for NDKSwift

## Real-Time Thread Rendering Without Loading States

Nostr data arrives asynchronously and incrementally. Apps must render threads as events stream in, not wait for complete loading.

## 1. Streaming Linear Thread (Twitter/X Style)

```swift
struct StreamingLinearThreadView: View {
    let eventId: String
    @EnvironmentObject var appState: AppState
    
    // Thread builds incrementally as events arrive
    @State private var threadNodes: [String: NDKThreadNode] = [:]
    @State private var rootEventId: String?
    @State private var visibleEventIds: [String] = []
    
    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(visibleEventIds, id: \.self) { eventId in
                    if let node = threadNodes[eventId] {
                        VStack(spacing: 0) {
                            // Thread connector
                            if node.depth > 0 {
                                ThreadConnectorView(depth: node.depth)
                            }
                            
                            // Event content
                            ThreadEventCell(
                                event: node.event,
                                isHighlighted: node.event.id == self.eventId,
                                depth: node.depth,
                                replyCount: node.children.count
                            )
                            .transition(.asymmetric(
                                insertion: .slide.combined(with: .opacity),
                                removal: .opacity
                            ))
                        }
                        .listRowInsets(EdgeInsets())
                    }
                }
            }
            .listStyle(.plain)
            .animation(.default, value: visibleEventIds)
        }
        .task {
            await startThreadStreaming()
        }
    }
    
    private func startThreadStreaming() async {
        guard let ndk = appState.ndk else { return }
        
        // Start observing the selected event
        let selectedFilter = NDKFilter(ids: [eventId])
        let selectedSub = ndk.observe(filter: selectedFilter)
        
        Task {
            for await event in selectedSub.events {
                await processEvent(event, depth: 0)
                break // Only need first match
            }
        }
        
        // Stream ancestors (working backwards)
        Task {
            await streamAncestors(of: eventId)
        }
        
        // Stream descendants (replies)
        Task {
            await streamDescendants(of: eventId)
        }
    }
    
    private func streamAncestors(of eventId: String) async {
        guard let ndk = appState.ndk else { return }
        
        var currentId = eventId
        var depth = -1
        
        while true {
            // Find parent references from what we have
            guard let event = threadNodes[currentId]?.event else {
                // Need to observe this event first
                let filter = NDKFilter(ids: [currentId])
                let sub = ndk.observe(filter: filter)
                
                for await evt in sub.events {
                    if let parentId = evt.parentEventId {
                        currentId = parentId
                        depth -= 1
                        await streamAncestors(of: parentId)
                    }
                    break
                }
                break
            }
            
            guard let parentId = event.parentEventId else { break }
            
            // Subscribe to parent event
            let parentFilter = NDKFilter(ids: [parentId])
            let parentSub = ndk.observe(filter: parentFilter)
            
            var foundParent = false
            for await parentEvent in parentSub.events {
                await processEvent(parentEvent, depth: depth)
                currentId = parentId
                depth -= 1
                foundParent = true
                
                // Update root
                await MainActor.run {
                    rootEventId = parentId
                    rebuildVisibleList()
                }
                break // Found it, continue outer loop
            }
            
            if !foundParent {
                // Wait a bit for parent to arrive
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                break // Give up on this ancestor chain
            }
        }
    }
    
    private func streamDescendants(of eventId: String) async {
        guard let ndk = appState.ndk else { return }
        
        // Subscribe to all replies
        let replyFilter = NDKFilter(
            kinds: [EventKind.text],
            tags: ["e": Set([eventId])]
        )
        
        let subscription = ndk.observe(filter: replyFilter)
        
        for await event in subscription.events {
            // Determine if this is a direct reply
            if event.parentEventId == eventId {
                await processEvent(event, depth: (threadNodes[eventId]?.depth ?? 0) + 1)
                await MainActor.run {
                    rebuildVisibleList()
                }
            }
        }
    }
    
    private func processEvent(_ event: NDKEvent, depth: Int) async {
        await MainActor.run {
            let node = NDKThreadNode(
                event: event,
                depth: depth,
                parent: nil,
                children: [],
                threadType: .nip10
            )
            threadNodes[event.id] = node
            
            // Update parent-child relationships
            if let parentId = event.parentEventId,
               var parentNode = threadNodes[parentId] {
                parentNode.children.append(node)
                threadNodes[parentId] = parentNode
            }
        }
    }
    
    private func rebuildVisibleList() {
        // Build linear list: ancestors → selected → direct replies
        var visible: [String] = []
        
        // Add ancestors
        if let rootId = rootEventId {
            visible.append(rootId)
            // Walk down to selected event
            var current = rootId
            while current != eventId {
                if let node = threadNodes[current],
                   let child = node.children.first(where: { isOnPathToSelected($0) }) {
                    visible.append(child.event.id)
                    current = child.event.id
                } else {
                    break
                }
            }
        }
        
        // Add selected event if not already included
        if !visible.contains(eventId) {
            visible.append(eventId)
        }
        
        // Add direct replies
        if let node = threadNodes[eventId] {
            visible.append(contentsOf: node.children.map { $0.event.id })
        }
        
        withAnimation {
            visibleEventIds = visible
        }
    }
    
    private func isOnPathToSelected(_ node: NDKThreadNode) -> Bool {
        // Check if this node leads to the selected event
        if node.event.id == eventId {
            return true
        }
        return node.children.contains { isOnPathToSelected($0) }
    }
}
```

## 2. Streaming Tree Thread (Reddit Style)

```swift
struct StreamingTreeThreadView: View {
    let rootEventId: String
    @EnvironmentObject var appState: AppState
    
    // Events stream in and get added to tree dynamically
    @State private var events: [String: NDKEvent] = [:]
    @State private var children: [String: Set<String>] = [:]
    @State private var collapsedNodes: Set<String> = []
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let rootEvent = events[rootEventId] {
                    StreamingTreeNode(
                        event: rootEvent,
                        events: events,
                        children: children,
                        collapsedNodes: $collapsedNodes,
                        depth: 0
                    )
                } else {
                    // Root hasn't loaded yet, but we can still show replies as they come
                    ForEach(Array(events.values), id: \.id) { event in
                        if event.parentEventId == nil || event.parentEventId == rootEventId {
                            StreamingTreeNode(
                                event: event,
                                events: events,
                                children: children,
                                collapsedNodes: $collapsedNodes,
                                depth: 0
                            )
                        }
                    }
                }
            }
            .padding()
        }
        .task {
            await streamThread()
        }
    }
    
    private func streamThread() async {
        guard let ndk = appState.ndk else { return }
        
        // Start multiple concurrent streams
        await withTaskGroup(of: Void.self) { group in
            // Stream the root event
            group.addTask {
                let rootFilter = NDKFilter(ids: [self.rootEventId])
                let rootSub = ndk.observe(filter: rootFilter)
                
                for await event in rootSub.events {
                    await self.addEvent(event)
                    break // Only need first match
                }
            }
            
            // Stream all events in thread
            group.addTask {
                await self.streamAllReplies()
            }
        }
    }
    
    private func streamAllReplies() async {
        guard let ndk = appState.ndk else { return }
        
        // Subscribe to all replies in the thread
        let filter = NDKFilter(
            kinds: [EventKind.text, EventKind.comment],
            tags: ["e": Set([rootEventId])] // Any event referencing root
        )
        
        let subscription = ndk.observe(filter: filter)
        
        for await event in subscription.events {
            await addEvent(event)
            
            // Also subscribe to replies to this event
            Task {
                await streamRepliesTo(event.id)
            }
        }
    }
    
    private func streamRepliesTo(_ eventId: String) async {
        guard let ndk = appState.ndk else { return }
        
        let filter = NDKFilter(
            kinds: [EventKind.text, EventKind.comment],
            tags: ["e": Set([eventId])]
        )
        
        let subscription = ndk.observe(filter: filter)
        
        for await event in subscription.events {
            if event.parentEventId == eventId {
                await addEvent(event)
            }
        }
    }
    
    private func addEvent(_ event: NDKEvent) async {
        await MainActor.run {
            // Add event
            events[event.id] = event
            
            // Update parent-child relationships
            if let parentId = event.parentEventId {
                var siblings = children[parentId] ?? []
                siblings.insert(event.id)
                children[parentId] = siblings
            }
            
            // Initialize children set for this event
            if children[event.id] == nil {
                children[event.id] = []
            }
        }
    }
}

struct StreamingTreeNode: View {
    let event: NDKEvent
    let events: [String: NDKEvent]
    let children: [String: Set<String>]
    @Binding var collapsedNodes: Set<String>
    let depth: Int
    
    @State private var profile: NDKUserProfile?
    
    private var isCollapsed: Bool {
        collapsedNodes.contains(event.id)
    }
    
    private var childEventIds: [String] {
        Array(children[event.id] ?? []).sorted { id1, id2 in
            guard let e1 = events[id1], let e2 = events[id2] else { return false }
            return e1.createdAt > e2.createdAt
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Node content
            HStack(alignment: .top, spacing: 8) {
                // Collapse button
                if !childEventIds.isEmpty {
                    Button(action: toggleCollapse) {
                        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .transition(.opacity)
                } else {
                    Color.clear.frame(width: 16, height: 16)
                }
                
                // Event content
                VStack(alignment: .leading, spacing: 4) {
                    // Author info
                    HStack(spacing: 4) {
                        Text(profile?.displayName ?? String(event.pubkey.prefix(8)))
                            .font(.caption)
                            .fontWeight(.medium)
                        
                        if !childEventIds.isEmpty {
                            Text("[\(childEventIds.count)]")
                                .font(.caption2)
                                .foregroundColor(.blue)
                                .transition(.opacity)
                        }
                    }
                    
                    Text(event.content)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer()
            }
            
            // Children (animated as they appear)
            if !isCollapsed {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(childEventIds, id: \.self) { childId in
                        if let childEvent = events[childId] {
                            StreamingTreeNode(
                                event: childEvent,
                                events: events,
                                children: children,
                                collapsedNodes: $collapsedNodes,
                                depth: depth + 1
                            )
                            .transition(.asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .opacity
                            ))
                        }
                    }
                }
                .padding(.leading, 20)
                .animation(.default, value: childEventIds)
            }
        }
        .task {
            // Load profile asynchronously
            if let profileManager = appState.ndk?.profileManager {
                profile = await profileManager.fetchProfile(for: event.pubkey)
            }
        }
    }
    
    private func toggleCollapse() {
        withAnimation {
            if isCollapsed {
                collapsedNodes.remove(event.id)
            } else {
                collapsedNodes.insert(event.id)
            }
        }
    }
}
```

## 3. Streaming Feed with Thread Indicators

```swift
struct StreamingFeedView: View {
    @EnvironmentObject var appState: AppState
    @State private var feedEvents: [NDKEvent] = []
    @State private var threadInfo: [String: ThreadInfo] = [:]
    
    struct ThreadInfo {
        var replyCount: Int = 0
        var latestReplyTime: Date?
        var repliers: Set<String> = []
    }
    
    var body: some View {
        List(feedEvents, id: \.id) { event in
            VStack(spacing: 0) {
                // Main post
                PostCard(event: event)
                
                // Thread indicator updates in real-time
                if let info = threadInfo[event.id], info.replyCount > 0 {
                    ThreadIndicator(
                        info: info,
                        onTap: {
                            // Navigate to thread
                        }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .onAppear {
                // Start monitoring this event's replies
                Task {
                    await monitorReplies(to: event)
                }
            }
        }
        .task {
            await streamFeed()
        }
    }
    
    private func streamFeed() async {
        guard let ndk = appState.ndk else { return }
        
        // Stream main feed
        let feedFilter = NDKFilter(
            kinds: [EventKind.text],
            limit: 100
        )
        
        let subscription = ndk.observe(filter: feedFilter)
        
        for await event in subscription.events {
            // Only show root posts in feed
            if event.parentEventId == nil {
                await MainActor.run {
                    feedEvents.insert(event, at: 0)
                    threadInfo[event.id] = ThreadInfo()
                }
            }
        }
    }
    
    private func monitorReplies(to event: NDKEvent) async {
        guard let ndk = appState.ndk else { return }
        
        let replyFilter = NDKFilter(
            kinds: [EventKind.text],
            tags: ["e": Set([event.id])]
        )
        
        let subscription = ndk.observe(filter: replyFilter)
        
        for await reply in subscription.events {
            await MainActor.run {
                var info = threadInfo[event.id] ?? ThreadInfo()
                info.replyCount += 1
                info.latestReplyTime = Date(timeIntervalSince1970: Double(reply.createdAt))
                info.repliers.insert(reply.pubkey)
                threadInfo[event.id] = info
            }
        }
    }
}

struct ThreadIndicator: View {
    let info: StreamingFeedView.ThreadInfo
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.caption)
                
                Text("\(info.replyCount) \(info.replyCount == 1 ? "reply" : "replies")")
                    .font(.caption)
                
                if info.repliers.count > 0 {
                    Text("from \(info.repliers.count) \(info.repliers.count == 1 ? "person" : "people")")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.1))
        }
        .buttonStyle(.plain)
    }
}
```

## Key Principles for Streaming Threads

1. **No Loading States**: Data appears as it arrives
2. **Incremental Building**: Thread structure builds progressively
3. **Concurrent Streams**: Multiple subscriptions for different parts
4. **Graceful Degradation**: Show what's available, don't wait
5. **Real-time Updates**: New replies appear immediately
6. **Animation**: Smooth transitions as content arrives

## Benefits

- **Instant Feedback**: Users see content immediately
- **Resilient**: Works even if some relays are slow/offline  
- **Natural**: Matches Nostr's distributed nature
- **Performant**: No blocking operations
- **Live**: Real-time updates without polling