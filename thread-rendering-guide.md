# Thread Rendering Guide for NDKSwift

## How Apps Render Threads Using Thread Reconstruction

This guide shows specific rendering patterns for displaying Nostr threads in different UI contexts.

## 1. Linear Thread Rendering (Twitter/X Style)

```swift
struct LinearThreadView: View {
    let eventId: String
    @EnvironmentObject var appState: AppState
    @State private var thread: NDKThread?
    @State private var linearEvents: [LinearThreadItem] = []
    
    struct LinearThreadItem: Identifiable {
        let id: String
        let event: NDKEvent
        let depth: Int
        let isMainPath: Bool  // Is this on the path from root to selected event?
        let hasMoreReplies: Bool
        let replyCount: Int
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            List(linearEvents) { item in
                VStack(spacing: 0) {
                    // Thread connector line
                    if item.depth > 0 {
                        ThreadConnectorView(
                            depth: item.depth,
                            isMainPath: item.isMainPath
                        )
                    }
                    
                    // Event content
                    ThreadEventCell(
                        event: item.event,
                        isHighlighted: item.event.id == eventId,
                        depth: item.depth
                    )
                    .id(item.event.id)
                    
                    // "Show more replies" button
                    if item.hasMoreReplies {
                        ShowMoreRepliesButton(
                            count: item.replyCount,
                            onTap: {
                                expandReplies(for: item.event)
                            }
                        )
                        .padding(.leading, CGFloat(item.depth + 1) * 20)
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .onAppear {
                // Scroll to highlighted event
                proxy.scrollTo(eventId, anchor: .center)
            }
        }
        .task {
            await loadThreadLinear()
        }
    }
    
    private func loadThreadLinear() async {
        guard let ndk = appState.ndk else { return }
        
        do {
            // Load the thread
            thread = try await ndk.reconstructThread(from: eventId)
            
            guard let thread = thread else { return }
            
            // Find the selected event in the thread
            guard let selectedNode = thread.find(eventId: eventId) else { return }
            
            // Build linear representation
            var items: [LinearThreadItem] = []
            
            // 1. Add ancestors (path from root to selected)
            let pathToRoot = thread.path(to: eventId) ?? []
            for (index, node) in pathToRoot.enumerated() {
                items.append(LinearThreadItem(
                    id: node.event.id,
                    event: node.event,
                    depth: index,
                    isMainPath: true,
                    hasMoreReplies: node.children.count > 1, // Has siblings
                    replyCount: node.replyCount
                ))
            }
            
            // 2. Add direct replies to selected event
            for child in selectedNode.children {
                items.append(LinearThreadItem(
                    id: child.event.id,
                    event: child.event,
                    depth: selectedNode.depth + 1,
                    isMainPath: false,
                    hasMoreReplies: child.replyCount > 0,
                    replyCount: child.replyCount
                ))
            }
            
            await MainActor.run {
                linearEvents = items
            }
        } catch {
            // Handle error
        }
    }
}

struct ThreadConnectorView: View {
    let depth: Int
    let isMainPath: Bool
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<depth, id: \.self) { level in
                Rectangle()
                    .fill(level == depth - 1 ? Color.blue.opacity(0.3) : Color.clear)
                    .frame(width: 2)
                    .padding(.leading, 18)
            }
            Spacer()
        }
        .frame(height: 20)
    }
}
```

## 2. Tree-Style Thread Rendering (Reddit Style)

```swift
struct TreeThreadView: View {
    let rootEvent: NDKEvent
    @EnvironmentObject var appState: AppState
    @State private var thread: NDKThread?
    @State private var collapsedNodes: Set<String> = []
    
    var body: some View {
        ScrollView {
            if let thread = thread {
                VStack(alignment: .leading, spacing: 0) {
                    TreeNodeView(
                        node: thread.root,
                        collapsedNodes: $collapsedNodes
                    )
                }
                .padding()
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            await loadThread()
        }
    }
    
    private func loadThread() async {
        guard let ndk = appState.ndk else { return }
        thread = try? await ndk.reconstructThread(from: rootEvent)
    }
}

struct TreeNodeView: View {
    let node: NDKThreadNode
    @Binding var collapsedNodes: Set<String>
    @State private var profile: NDKUserProfile?
    
    private var isCollapsed: Bool {
        collapsedNodes.contains(node.event.id)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Node content with collapse control
            HStack(alignment: .top, spacing: 8) {
                // Collapse/expand button
                if !node.children.isEmpty {
                    Button(action: toggleCollapse) {
                        Image(systemName: isCollapsed ? "plus.square" : "minus.square")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                } else {
                    // Empty space for alignment
                    Color.clear
                        .frame(width: 16, height: 16)
                }
                
                // Event content
                VStack(alignment: .leading, spacing: 4) {
                    // Author info
                    HStack(spacing: 4) {
                        if let picture = profile?.picture, let url = URL(string: picture) {
                            AsyncImage(url: url) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                            } placeholder: {
                                Circle()
                                    .fill(Color.gray.opacity(0.3))
                            }
                            .frame(width: 20, height: 20)
                            .clipShape(Circle())
                        }
                        
                        Text(profile?.displayName ?? String(node.event.pubkey.prefix(8)))
                            .font(.caption)
                            .fontWeight(.medium)
                        
                        Text("•")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Text(RelativeDateTimeFormatter().localizedString(
                            for: Date(timeIntervalSince1970: Double(node.event.createdAt)),
                            relativeTo: Date()
                        ))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        
                        if !node.children.isEmpty {
                            Text("[\(node.totalDescendants) replies]")
                                .font(.caption2)
                                .foregroundColor(.blue)
                        }
                    }
                    
                    // Content
                    Text(node.event.content)
                        .font(.system(.body, design: .default))
                        .fixedSize(horizontal: false, vertical: true)
                    
                    // Engagement bar
                    HStack(spacing: 16) {
                        Button(action: {}) {
                            Label("\(node.replyCount)", systemImage: "bubble.left")
                                .font(.caption)
                        }
                        
                        Button(action: {}) {
                            Label("Like", systemImage: "heart")
                                .font(.caption)
                        }
                        
                        Button(action: {}) {
                            Label("Zap", systemImage: "bolt")
                                .font(.caption)
                        }
                    }
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
                }
                
                Spacer()
            }
            
            // Child nodes (indented)
            if !isCollapsed && !node.children.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(node.children, id: \.event.id) { child in
                        TreeNodeView(
                            node: child,
                            collapsedNodes: $collapsedNodes
                        )
                    }
                }
                .padding(.leading, 24)
                .overlay(
                    // Thread line
                    HStack {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 1)
                            .offset(x: 8)
                        Spacer()
                    }
                )
            }
        }
        .task {
            // Load profile
            if let profileManager = appState.ndk?.profileManager {
                profile = await profileManager.fetchProfile(for: node.event.pubkey)
            }
        }
    }
    
    private func toggleCollapse() {
        withAnimation(.spring(response: 0.3)) {
            if isCollapsed {
                collapsedNodes.remove(node.event.id)
            } else {
                collapsedNodes.insert(node.event.id)
            }
        }
    }
}
```

## 3. Conversation View (Messages App Style)

```swift
struct ConversationThreadView: View {
    let rootEvent: NDKEvent
    @EnvironmentObject var appState: AppState
    @State private var thread: NDKThread?
    @State private var flattenedEvents: [NDKEvent] = []
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(flattenedEvents, id: \.id) { event in
                        ConversationBubble(
                            event: event,
                            isCurrentUser: event.pubkey == appState.currentUser?.pubkey
                        )
                        .id(event.id)
                    }
                }
                .padding()
            }
        }
        .task {
            await loadConversation()
        }
    }
    
    private func loadConversation() async {
        guard let ndk = appState.ndk else { return }
        
        do {
            thread = try await ndk.reconstructThread(from: rootEvent)
            
            // Flatten thread in chronological order
            guard let thread = thread else { return }
            let flattened = flattenThread(thread.root).sorted { $0.createdAt < $1.createdAt }
            
            await MainActor.run {
                flattenedEvents = flattened
            }
        } catch {
            // Handle error
        }
    }
    
    private func flattenThread(_ node: NDKThreadNode) -> [NDKEvent] {
        var events = [node.event]
        for child in node.children {
            events.append(contentsOf: flattenThread(child))
        }
        return events
    }
}
```

## 4. Compact Thread Summary (Feed Preview)

```swift
struct ThreadSummaryView: View {
    let rootEvent: NDKEvent
    @State private var summary: ThreadSummary?
    
    struct ThreadSummary {
        let totalReplies: Int
        let uniqueAuthors: Int
        let lastReplyTime: Date
        let topRepliers: [(pubkey: String, profile: NDKUserProfile?)]
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Root event preview
            EventPreviewCard(event: rootEvent)
            
            if let summary = summary, summary.totalReplies > 0 {
                Divider()
                
                HStack {
                    // Reply count
                    Label("\(summary.totalReplies) replies", systemImage: "bubble.left.and.bubble.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    // Top replier avatars
                    HStack(spacing: -8) {
                        ForEach(summary.topRepliers.prefix(3), id: \.pubkey) { replier in
                            if let profile = replier.profile,
                               let picture = profile.picture,
                               let url = URL(string: picture) {
                                AsyncImage(url: url) { image in
                                    image
                                        .resizable()
                                        .scaledToFill()
                                } placeholder: {
                                    Circle()
                                        .fill(Color.gray.opacity(0.3))
                                }
                                .frame(width: 24, height: 24)
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .stroke(Color.white, lineWidth: 2)
                                )
                            }
                        }
                    }
                    
                    if summary.uniqueAuthors > 3 {
                        Text("+\(summary.uniqueAuthors - 3)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
            }
        }
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .task {
            await loadSummary()
        }
    }
    
    private func loadSummary() async {
        guard let ndk = appState.ndk else { return }
        
        do {
            // Load just enough to show summary
            let options = ThreadOptions(
                maxDepth: 3,
                cachePolicy: .cacheOnly,
                timeout: 2
            )
            
            let thread = try await ndk.reconstructThread(
                from: rootEvent,
                options: options
            )
            
            // Calculate summary
            let allEvents = thread.flatten()
            let repliers = Set(allEvents.map { $0.event.pubkey }).subtracting([rootEvent.pubkey])
            
            // Load top replier profiles
            var topRepliers: [(String, NDKUserProfile?)] = []
            for pubkey in repliers.prefix(3) {
                let profile = await appState.ndk?.profileManager?.fetchProfile(for: pubkey)
                topRepliers.append((pubkey, profile))
            }
            
            summary = ThreadSummary(
                totalReplies: thread.totalEvents - 1,
                uniqueAuthors: repliers.count,
                lastReplyTime: allEvents.map { 
                    Date(timeIntervalSince1970: Double($0.event.createdAt)) 
                }.max() ?? Date(),
                topRepliers: topRepliers
            )
        } catch {
            // Silent fail for preview
        }
    }
}
```

## 5. Performance-Optimized Infinite Thread

```swift
struct InfiniteThreadView: View {
    let rootEvent: NDKEvent
    @State private var visibleNodes: [NDKThreadNode] = []
    @State private var loadedDepth = 2
    
    var body: some View {
        List {
            ForEach(visibleNodes, id: \.event.id) { node in
                VStack(alignment: .leading) {
                    // Indented content based on depth
                    HStack {
                        if node.depth > 0 {
                            Spacer()
                                .frame(width: CGFloat(node.depth) * 20)
                        }
                        
                        EventCell(event: node.event)
                    }
                    
                    // Load more button at depth boundaries
                    if node.depth == loadedDepth - 1 && !node.children.isEmpty {
                        Button("Load \(node.replyCount) more replies") {
                            Task {
                                await loadDeeperReplies(for: node)
                            }
                        }
                        .padding(.leading, CGFloat(node.depth + 1) * 20)
                    }
                }
            }
        }
        .task {
            await loadInitialThread()
        }
    }
    
    private func loadInitialThread() async {
        guard let ndk = appState.ndk else { return }
        
        let options = ThreadOptions(maxDepth: loadedDepth)
        if let thread = try? await ndk.reconstructThread(from: rootEvent, options: options) {
            visibleNodes = flattenToDepth(thread.root, maxDepth: loadedDepth)
        }
    }
    
    private func loadDeeperReplies(for node: NDKThreadNode) async {
        loadedDepth += 2
        // Re-load with increased depth
        await loadInitialThread()
    }
    
    private func flattenToDepth(_ node: NDKThreadNode, maxDepth: Int) -> [NDKThreadNode] {
        guard node.depth < maxDepth else { return [node] }
        
        var result = [node]
        for child in node.children {
            result.append(contentsOf: flattenToDepth(child, maxDepth: maxDepth))
        }
        return result
    }
}
```

## Key Rendering Strategies

1. **Linear (Twitter/X)**: Show ancestors → selected → direct replies
2. **Tree (Reddit)**: Full hierarchy with collapse/expand
3. **Conversation (Messages)**: Chronological flattened view
4. **Summary (Feed)**: Compact preview with participant info
5. **Infinite**: Progressive loading for deep threads

Each approach uses the same `NDKThread` data structure but renders it differently based on the UI context and performance requirements.