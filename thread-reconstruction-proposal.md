# Thread Reconstruction Proposal for NDKSwift

## Overview

This proposal outlines a unified thread reconstruction API for NDKSwift that handles the three different threading patterns in Nostr:
- **NIP-10**: Threading for kind:1 text notes
- **NIP-22**: Comments on non-kind:1 events  
- **NIP-7D**: Dedicated thread discussions

## Core Design Principles

1. **Automatic Detection**: The API automatically detects which threading pattern to use based on event kinds
2. **Unified Interface**: Single API surface regardless of underlying thread type
3. **Performance**: Lazy loading and caching for large threads
4. **Real-time Updates**: Subscribe to thread changes
5. **Graceful Degradation**: Handle missing events and broken references

## Proposed API

### Thread Structure

```swift
// Core thread node structure
public struct NDKThreadNode {
    public let event: NDKEvent
    public let depth: Int
    public let parent: NDKThreadNode?
    public private(set) var children: [NDKThreadNode]
    
    // Thread metadata
    public var isRoot: Bool { parent == nil }
    public var isLeaf: Bool { children.isEmpty }
    public var replyCount: Int { children.count }
    public var totalDescendants: Int // Recursive count
    
    // Thread type detection
    public var threadType: ThreadType
    
    public enum ThreadType {
        case nip10      // kind:1 → kind:1
        case nip22      // any → kind:1111
        case nip7d      // kind:11 → kind:1111
        case unknown
    }
}

// Thread reconstruction result
public struct NDKThread {
    public let root: NDKThreadNode
    public let allEvents: [NDKEvent]
    public let orphanedEvents: [NDKEvent] // Events with missing parents
    public let threadType: NDKThreadNode.ThreadType
    
    // Thread statistics
    public var totalEvents: Int { allEvents.count }
    public var maxDepth: Int
    public var participants: Set<String> // All unique pubkeys
    
    // Navigation helpers
    public func find(eventId: String) -> NDKThreadNode?
    public func path(to eventId: String) -> [NDKThreadNode]?
    public func flatten() -> [NDKThreadNode] // Pre-order traversal
}
```

### Thread Reconstruction API

```swift
extension NDK {
    // MARK: - Full Thread Reconstruction
    
    /// Reconstructs a complete thread from any event in the thread
    /// - Parameters:
    ///   - event: Any event in the thread (root, reply, or comment)
    ///   - options: Configuration for thread loading
    /// - Returns: Complete thread structure
    public func reconstructThread(
        from event: NDKEvent,
        options: ThreadOptions = .default
    ) async throws -> NDKThread
    
    /// Reconstructs a thread starting from a specific event ID
    public func reconstructThread(
        from eventId: String,
        options: ThreadOptions = .default
    ) async throws -> NDKThread
    
    // MARK: - Incremental Thread Loading
    
    /// Loads only direct replies to an event
    public func loadReplies(
        to event: NDKEvent,
        options: ThreadOptions = .default
    ) async throws -> [NDKEvent]
    
    /// Loads thread ancestors (path to root)
    public func loadAncestors(
        of event: NDKEvent,
        options: ThreadOptions = .default
    ) async throws -> [NDKEvent]
    
    // MARK: - Real-time Thread Updates
    
    /// Subscribe to new replies/comments on a thread
    public func observeThread(
        _ thread: NDKThread,
        options: ThreadOptions = .default
    ) -> AsyncStream<ThreadUpdate>
    
    /// Subscribe to replies to a specific event
    public func observeReplies(
        to event: NDKEvent,
        options: ThreadOptions = .default
    ) -> AsyncStream<NDKEvent>
}

// Thread reconstruction options
public struct ThreadOptions {
    /// Maximum depth to traverse (nil = unlimited)
    public var maxDepth: Int?
    
    /// Whether to include deleted events (kind:5)
    public var includeDeleted: Bool = false
    
    /// Cache policy for thread data
    public var cachePolicy: NDKCachePolicy = .cacheWithNetwork
    
    /// Timeout for thread reconstruction
    public var timeout: TimeInterval = 30
    
    /// Whether to validate event signatures
    public var validateSignatures: Bool = true
    
    /// Filter for which events to include
    public var eventFilter: ((NDKEvent) -> Bool)?
    
    public static let `default` = ThreadOptions()
}

// Thread update notifications
public enum ThreadUpdate {
    case newReply(NDKEvent, parent: NDKEvent)
    case eventDeleted(eventId: String)
    case eventUpdated(NDKEvent)
}
```

### Helper Extensions

```swift
// Convenience methods on NDKEvent
extension NDKEvent {
    /// Detects the threading pattern this event uses
    public var threadingPattern: ThreadingPattern {
        switch kind {
        case EventKind.text:
            return .nip10
        case EventKind.comment:
            return .nip22
        case EventKind.thread:
            return .nip7d
        default:
            return detectFromTags()
        }
    }
    
    /// Gets the root event ID for this thread
    public var threadRootId: String? {
        switch threadingPattern {
        case .nip10:
            return tags.first { $0.marker == "root" }?.eventId
        case .nip22:
            // Find uppercase E tag for root
            return tags.first { $0.type == "E" }?.value
        case .nip7d:
            return tags.first { $0.type == "E" && $0.kind == "11" }?.value
        default:
            return nil
        }
    }
    
    /// Gets the direct parent event ID
    public var parentEventId: String? {
        switch threadingPattern {
        case .nip10:
            return tags.first { $0.marker == "reply" }?.eventId
                ?? tags.last { $0.type == "e" }?.eventId
        case .nip22:
            // Find lowercase e tag for parent
            return tags.first { $0.type == "e" }?.value
        default:
            return nil
        }
    }
    
    /// Creates a properly formatted reply to this event
    public func createReply(
        content: String,
        additionalTags: [[String]] = []
    ) -> NDKEventBuilder {
        switch kind {
        case EventKind.text:
            // Use NIP-10 for kind:1
            return createNip10Reply(content: content, additionalTags: additionalTags)
        case EventKind.thread:
            // Use NIP-22 for kind:11 threads
            return createNip22Comment(content: content, additionalTags: additionalTags)
        default:
            // Use NIP-22 for everything else
            return createNip22Comment(content: content, additionalTags: additionalTags)
        }
    }
}
```

### Implementation Details

```swift
// Internal thread builder
class NDKThreadBuilder {
    private let ndk: NDK
    private let options: ThreadOptions
    private var eventCache: [String: NDKEvent] = [:]
    private var nodeCache: [String: NDKThreadNode] = [:]
    
    func buildThread(from event: NDKEvent) async throws -> NDKThread {
        // 1. Detect thread type
        let threadType = detectThreadType(event)
        
        // 2. Find root event
        let root = try await findRoot(event, type: threadType)
        
        // 3. Build thread structure
        let rootNode = try await buildNode(
            event: root,
            parent: nil,
            depth: 0,
            threadType: threadType
        )
        
        // 4. Collect statistics
        let stats = calculateStats(rootNode)
        
        return NDKThread(
            root: rootNode,
            allEvents: Array(eventCache.values),
            orphanedEvents: findOrphans(),
            threadType: threadType,
            maxDepth: stats.maxDepth,
            participants: stats.participants
        )
    }
    
    private func buildNode(
        event: NDKEvent,
        parent: NDKThreadNode?,
        depth: Int,
        threadType: NDKThreadNode.ThreadType
    ) async throws -> NDKThreadNode {
        // Check depth limit
        if let maxDepth = options.maxDepth, depth >= maxDepth {
            return NDKThreadNode(
                event: event,
                depth: depth,
                parent: parent,
                children: [],
                threadType: threadType
            )
        }
        
        // Find children based on thread type
        let children = try await findChildren(
            of: event,
            threadType: threadType
        )
        
        // Recursively build child nodes
        var childNodes: [NDKThreadNode] = []
        for child in children {
            let childNode = try await buildNode(
                event: child,
                parent: nil, // Set after creation
                depth: depth + 1,
                threadType: threadType
            )
            childNodes.append(childNode)
        }
        
        let node = NDKThreadNode(
            event: event,
            depth: depth,
            parent: parent,
            children: childNodes,
            threadType: threadType
        )
        
        // Set parent reference on children
        childNodes.forEach { $0.parent = node }
        
        return node
    }
    
    private func findChildren(
        of event: NDKEvent,
        threadType: NDKThreadNode.ThreadType
    ) async throws -> [NDKEvent] {
        let filter: NDKFilter
        
        switch threadType {
        case .nip10:
            // Find kind:1 events with this event as parent
            filter = NDKFilter(
                kinds: [EventKind.text],
                tags: ["e": Set([event.id])]
            )
        case .nip22:
            // Find kind:1111 events with lowercase 'e' tag
            filter = NDKFilter(
                kinds: [EventKind.comment],
                tags: ["e": Set([event.id])]
            )
        case .nip7d:
            // For kind:11, find kind:1111 comments
            if event.kind == EventKind.thread {
                filter = NDKFilter(
                    kinds: [EventKind.comment],
                    tags: ["E": Set([event.id])]
                )
            } else {
                // For comments, find replies with lowercase 'e'
                filter = NDKFilter(
                    kinds: [EventKind.comment],
                    tags: ["e": Set([event.id])]
                )
            }
        case .unknown:
            return []
        }
        
        let dataSource = ndk.observe(
            filter: filter,
            cachePolicy: options.cachePolicy
        )
        
        return await dataSource.collect(timeout: options.timeout)
    }
}
```

### Usage Examples

```swift
// Example 1: Reconstruct entire thread
let thread = try await ndk.reconstructThread(from: someEvent)
print("Thread has \(thread.totalEvents) events with max depth \(thread.maxDepth)")

// Example 2: Load only direct replies
let directReplies = try await ndk.loadReplies(to: event)
print("Event has \(directReplies.count) direct replies")

// Example 3: Subscribe to thread updates
for await update in ndk.observeThread(thread) {
    switch update {
    case .newReply(let reply, let parent):
        print("New reply to \(parent.id)")
    case .eventDeleted(let eventId):
        print("Event \(eventId) was deleted")
    case .eventUpdated(let event):
        print("Event \(event.id) was updated")
    }
}

// Example 4: Create a reply with proper threading
let replyBuilder = originalEvent.createReply(
    content: "This is my reply!",
    additionalTags: [["emoji", "🚀"]]
)
let reply = try await replyBuilder.sign(using: signer)
try await ndk.publish(reply)

// Example 5: Navigate thread structure
if let node = thread.find(eventId: someId) {
    print("Event is at depth \(node.depth)")
    print("Has \(node.replyCount) direct replies")
    
    if let path = thread.path(to: someId) {
        print("Path from root: \(path.map { $0.event.id })")
    }
}
```

## Benefits of This Design

1. **Unified API**: Single interface handles all three threading patterns transparently
2. **Type Safety**: Strong typing prevents mixing incompatible thread types
3. **Performance**: Lazy loading and caching for large threads
4. **Flexibility**: Options allow customization of loading behavior
5. **Real-time**: Built-in support for thread updates via subscriptions
6. **Developer Experience**: Intuitive API with helpful extensions

## Migration Path

Existing NDKSwift users can adopt this gradually:
1. Current reply methods continue to work
2. New thread API is additive, not breaking
3. Deprecation warnings guide to new patterns
4. Examples and documentation show best practices

This design provides a solid foundation for thread support in NDKSwift while maintaining flexibility for future threading patterns in Nostr.