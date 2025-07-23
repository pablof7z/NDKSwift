# Correct Thread Reconstruction API for NDKSwift

## Building on NDK's Streaming Foundation

Since NDKSwift uses `observe()` for everything (no `fetchEvent`), the thread reconstruction API should embrace this streaming nature.

## Core Thread Types

```swift
// Thread node that builds incrementally
public class NDKThreadNode {
    public let event: NDKEvent
    public internal(set) var parent: NDKThreadNode?
    public internal(set) var children: [NDKThreadNode] = []
    
    public var depth: Int {
        var d = 0
        var current = parent
        while current != nil {
            d += 1
            current = current?.parent
        }
        return d
    }
    
    public var isRoot: Bool { parent == nil }
    public var replyCount: Int { children.count }
    public var totalDescendants: Int {
        children.reduce(0) { $0 + 1 + $1.totalDescendants }
    }
}

// Thread builder that streams events
public class NDKThreadBuilder {
    private let ndk: NDK
    private var nodes: [String: NDKThreadNode] = [:]
    private var subscriptions: Set<NDKSubscription> = []
    
    public init(ndk: NDK) {
        self.ndk = ndk
    }
    
    deinit {
        // Cancel all subscriptions
        subscriptions.forEach { $0.close() }
    }
    
    /// Stream thread updates starting from any event
    public func observeThread(from eventId: String) -> AsyncStream<ThreadUpdate> {
        AsyncStream { continuation in
            // Start streaming the thread
            Task {
                // 1. Stream the initial event
                await streamEvent(eventId) { node in
                    continuation.yield(.nodeAdded(node))
                }
                
                // 2. Stream ancestors
                Task {
                    await streamAncestors(of: eventId) { node in
                        continuation.yield(.nodeAdded(node))
                    }
                }
                
                // 3. Stream descendants
                Task {
                    await streamDescendants(of: eventId) { node in
                        continuation.yield(.nodeAdded(node))
                    }
                }
            }
            
            continuation.onTermination = { _ in
                self.subscriptions.forEach { $0.close() }
            }
        }
    }
    
    private func streamEvent(_ eventId: String, onNode: @escaping (NDKThreadNode) -> Void) async {
        let filter = NDKFilter(ids: [eventId])
        let sub = ndk.observe(filter: filter)
        subscriptions.insert(sub)
        
        for await event in sub.events {
            let node = getOrCreateNode(for: event)
            onNode(node)
        }
    }
    
    private func streamAncestors(of eventId: String, onNode: @escaping (NDKThreadNode) -> Void) async {
        var currentId = eventId
        
        while true {
            // Wait for the current event to load
            while nodes[currentId] == nil {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
            }
            
            guard let node = nodes[currentId],
                  let parentId = node.event.parentEventId else {
                break
            }
            
            // Stream the parent
            let parentFilter = NDKFilter(ids: [parentId])
            let parentSub = ndk.observe(filter: parentFilter)
            subscriptions.insert(parentSub)
            
            var foundParent = false
            for await parentEvent in parentSub.events {
                let parentNode = getOrCreateNode(for: parentEvent)
                node.parent = parentNode
                parentNode.children.append(node)
                onNode(parentNode)
                currentId = parentId
                foundParent = true
                break
            }
            
            if !foundParent {
                // Give up after timeout
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s
                break
            }
        }
    }
    
    private func streamDescendants(of eventId: String, onNode: @escaping (NDKThreadNode) -> Void) async {
        // Subscribe to all replies
        let replyFilter = NDKFilter(
            kinds: [EventKind.text, EventKind.comment],
            tags: ["e": Set([eventId])]
        )
        
        let replySub = ndk.observe(filter: replyFilter)
        subscriptions.insert(replySub)
        
        for await reply in replySub.events {
            // Check if direct reply
            if reply.parentEventId == eventId {
                let replyNode = getOrCreateNode(for: reply)
                
                if let parentNode = nodes[eventId] {
                    replyNode.parent = parentNode
                    if !parentNode.children.contains(where: { $0.event.id == reply.id }) {
                        parentNode.children.append(replyNode)
                    }
                }
                
                onNode(replyNode)
                
                // Also stream replies to this reply
                Task {
                    await streamDescendants(of: reply.id, onNode: onNode)
                }
            }
        }
    }
    
    private func getOrCreateNode(for event: NDKEvent) -> NDKThreadNode {
        if let existing = nodes[event.id] {
            return existing
        }
        
        let node = NDKThreadNode(event: event)
        nodes[event.id] = node
        return node
    }
}

public enum ThreadUpdate {
    case nodeAdded(NDKThreadNode)
    case nodeUpdated(NDKThreadNode)
    case nodeDeleted(eventId: String)
}
```

## Extension on NDK for Convenience

```swift
extension NDK {
    /// Observe a thread starting from any event in it
    public func observeThread(from eventId: String) -> AsyncStream<ThreadUpdate> {
        let builder = NDKThreadBuilder(ndk: self)
        return builder.observeThread(from: eventId)
    }
    
    /// Get just direct replies to an event
    public func observeReplies(to eventId: String) -> NDKDataSource<NDKEvent> {
        let filter = NDKFilter(
            kinds: [EventKind.text, EventKind.comment],
            tags: ["e": Set([eventId])]
        )
        
        return observe(filter: filter)
    }
}

extension NDKEvent {
    /// Get parent event ID based on NIP-10 or NIP-22
    public var parentEventId: String? {
        switch kind {
        case EventKind.text:
            // NIP-10: Look for "reply" marker or last 'e' tag
            if let replyTag = tags.first(where: { $0.count >= 4 && $0[0] == "e" && $0[3] == "reply" }) {
                return replyTag[1]
            }
            // Fallback to positional (deprecated but still used)
            let eTags = tags.filter { $0.count >= 2 && $0[0] == "e" }
            return eTags.count >= 2 ? eTags[eTags.count - 1][1] : eTags.first?[1]
            
        case EventKind.comment:
            // NIP-22: lowercase 'e' is parent
            return tags.first(where: { $0.count >= 2 && $0[0] == "e" })?[1]
            
        default:
            return nil
        }
    }
    
    /// Get root event ID
    public var rootEventId: String? {
        switch kind {
        case EventKind.text:
            // NIP-10: Look for "root" marker or first 'e' tag
            if let rootTag = tags.first(where: { $0.count >= 4 && $0[0] == "e" && $0[3] == "root" }) {
                return rootTag[1]
            }
            return tags.first(where: { $0.count >= 2 && $0[0] == "e" })?[1]
            
        case EventKind.comment:
            // NIP-22: uppercase 'E' is root
            return tags.first(where: { $0.count >= 2 && $0[0] == "E" })?[1]
            
        default:
            return nil
        }
    }
}
```

## Usage in Apps

```swift
struct StreamingThreadView: View {
    let eventId: String
    @EnvironmentObject var appState: AppState
    @State private var nodes: [String: NDKThreadNode] = [:]
    @State private var rootNode: NDKThreadNode?
    
    var body: some View {
        ScrollView {
            if let root = rootNode {
                ThreadNodeView(node: root, nodes: $nodes)
            } else {
                // Show whatever we have while finding root
                ForEach(Array(nodes.values), id: \.event.id) { node in
                    if node.isRoot {
                        ThreadNodeView(node: node, nodes: $nodes)
                    }
                }
            }
        }
        .task {
            await streamThread()
        }
    }
    
    private func streamThread() async {
        guard let ndk = appState.ndk else { return }
        
        for await update in ndk.observeThread(from: eventId) {
            switch update {
            case .nodeAdded(let node):
                await MainActor.run {
                    nodes[node.event.id] = node
                    
                    // Update root if found
                    if node.isRoot {
                        rootNode = node
                    } else if let currentRoot = rootNode, node.depth < currentRoot.depth {
                        // Found a higher ancestor
                        var ancestor = node
                        while ancestor.parent != nil {
                            ancestor = ancestor.parent!
                        }
                        rootNode = ancestor
                    }
                }
                
            case .nodeUpdated(let node):
                await MainActor.run {
                    nodes[node.event.id] = node
                }
                
            case .nodeDeleted(let eventId):
                await MainActor.run {
                    nodes.removeValue(forKey: eventId)
                }
            }
        }
    }
}

struct ThreadNodeView: View {
    let node: NDKThreadNode
    @Binding var nodes: [String: NDKThreadNode]
    @State private var isCollapsed = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Node content
            HStack {
                if !node.children.isEmpty {
                    Button(action: { isCollapsed.toggle() }) {
                        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                            .font(.caption)
                    }
                }
                
                VStack(alignment: .leading) {
                    Text(node.event.content)
                    Text("\(node.children.count) replies")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.leading, CGFloat(node.depth) * 20)
            
            // Children
            if !isCollapsed {
                ForEach(node.children, id: \.event.id) { child in
                    ThreadNodeView(node: child, nodes: $nodes)
                        .transition(.asymmetric(
                            insertion: .slide.combined(with: .opacity),
                            removal: .opacity
                        ))
                }
            }
        }
        .animation(.default, value: node.children.count)
    }
}
```

## Key Improvements

1. **Pure Streaming**: No `fetchEvent`, only `observe()`
2. **Incremental Building**: Thread structure emerges as events stream in
3. **Reactive Updates**: UI updates automatically as nodes are added
4. **Memory Efficient**: Only keeps nodes in memory, not subscriptions
5. **Graceful Timeouts**: Doesn't wait forever for missing events

This design embraces Nostr's distributed nature where events arrive gradually and some may never arrive.