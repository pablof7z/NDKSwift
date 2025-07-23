# Thread Reconstruction Usage Examples

## Real-World App Implementation

Here's how apps like Olas, Posta, or any Nostr client would use the thread reconstruction API:

## 1. Thread View Component

```swift
import SwiftUI
import NDKSwift

struct ThreadView: View {
    let rootEvent: NDKEvent
    @EnvironmentObject var appState: AppState
    
    @State private var thread: NDKThread?
    @State private var isLoading = true
    @State private var error: Error?
    @State private var expandedNodes: Set<String> = []
    
    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView("Loading thread...")
                    .padding()
            } else if let thread = thread {
                ThreadNodeView(
                    node: thread.root,
                    thread: thread,
                    expandedNodes: $expandedNodes
                )
                .padding()
            } else if let error = error {
                ErrorView(error: error) {
                    Task { await loadThread() }
                }
            }
        }
        .navigationTitle("Thread")
        .task {
            await loadThread()
        }
        .refreshable {
            await loadThread()
        }
        .onReceive(NotificationCenter.default.publisher(for: .eventPublished)) { _ in
            Task { await refreshThread() }
        }
    }
    
    private func loadThread() async {
        isLoading = true
        error = nil
        
        do {
            guard let ndk = appState.ndk else { return }
            
            // Load complete thread with options
            let options = ThreadOptions(
                maxDepth: 10, // Limit depth for performance
                cachePolicy: .cacheWithNetwork,
                timeout: 15
            )
            
            thread = try await ndk.reconstructThread(
                from: rootEvent,
                options: options
            )
            
            // Auto-expand first few levels
            if let thread = thread {
                expandInitialLevels(thread.root, maxDepth: 2)
            }
            
            // Start observing thread updates
            observeThreadUpdates()
            
        } catch {
            self.error = error
        }
        
        isLoading = false
    }
    
    private func observeThreadUpdates() {
        guard let ndk = appState.ndk, let thread = thread else { return }
        
        Task {
            for await update in ndk.observeThread(thread) {
                switch update {
                case .newReply(let reply, let parent):
                    // Update UI with new reply
                    await MainActor.run {
                        withAnimation {
                            // Thread will auto-update via SwiftUI
                            expandedNodes.insert(parent.id)
                        }
                    }
                    
                case .eventDeleted(let eventId):
                    // Handle deletion
                    await MainActor.run {
                        // Refresh thread to remove deleted event
                        await refreshThread()
                    }
                    
                case .eventUpdated(let event):
                    // Handle updates (e.g., edit via NIP-16)
                    break
                }
            }
        }
    }
    
    private func expandInitialLevels(_ node: NDKThreadNode, maxDepth: Int) {
        guard node.depth < maxDepth else { return }
        expandedNodes.insert(node.event.id)
        node.children.forEach { expandInitialLevels($0, maxDepth: maxDepth) }
    }
    
    private func refreshThread() async {
        // Lighter refresh without full loading state
        do {
            guard let ndk = appState.ndk else { return }
            thread = try await ndk.reconstructThread(from: rootEvent)
        } catch {
            // Handle silently or show toast
        }
    }
}

// MARK: - Thread Node View
struct ThreadNodeView: View {
    let node: NDKThreadNode
    let thread: NDKThread
    @Binding var expandedNodes: Set<String>
    @EnvironmentObject var appState: AppState
    
    @State private var showReplyComposer = false
    
    private var isExpanded: Bool {
        expandedNodes.contains(node.event.id)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Event content
            EventCard(
                event: node.event,
                isThreadView: true,
                depth: node.depth,
                onReply: { showReplyComposer = true }
            )
            
            // Child count and expand button
            if !node.children.isEmpty {
                Button(action: toggleExpanded) {
                    HStack {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption)
                        
                        Text("\(node.replyCount) \(node.replyCount == 1 ? "reply" : "replies")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if node.totalDescendants > node.replyCount {
                            Text("(\(node.totalDescendants) total)")
                                .font(.caption2)
                                .foregroundColor(.tertiary)
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.leading, CGFloat(node.depth) * 20)
            }
            
            // Child nodes (animated)
            if isExpanded {
                ForEach(node.children, id: \.event.id) { childNode in
                    ThreadNodeView(
                        node: childNode,
                        thread: thread,
                        expandedNodes: $expandedNodes
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity
                    ))
                }
            }
        }
        .sheet(isPresented: $showReplyComposer) {
            ReplyComposer(parentEvent: node.event)
                .environmentObject(appState)
        }
    }
    
    private func toggleExpanded() {
        withAnimation(.spring(response: 0.3)) {
            if isExpanded {
                expandedNodes.remove(node.event.id)
            } else {
                expandedNodes.insert(node.event.id)
            }
        }
    }
}
```

## 2. Reply Composer Using Thread API

```swift
struct ReplyComposer: View {
    let parentEvent: NDKEvent
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    
    @State private var replyText = ""
    @State private var isPosting = false
    @State private var selectedImages: [UIImage] = []
    
    // Thread context
    @State private var threadContext: ThreadContext?
    
    struct ThreadContext {
        let rootEvent: NDKEvent
        let participants: Set<String>
        let depth: Int
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Show thread context
                if let context = threadContext {
                    ThreadContextBar(context: context)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                }
                
                // Reply-to preview
                ReplyToPreview(event: parentEvent)
                    .padding()
                
                Divider()
                
                // Compose area
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Text editor
                        TextField("Write your reply...", text: $replyText, axis: .vertical)
                            .textFieldStyle(.plain)
                            .padding()
                            .focused($isTextFieldFocused)
                        
                        // Image attachments
                        if !selectedImages.isEmpty {
                            ImageAttachmentsView(images: $selectedImages)
                                .padding(.horizontal)
                        }
                    }
                }
                
                Divider()
                
                // Toolbar
                ComposeToolbar(
                    selectedImages: $selectedImages,
                    onPost: postReply
                )
            }
            .navigationTitle("Reply")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Post") {
                        Task { await postReply() }
                    }
                    .disabled(replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPosting)
                }
            }
        }
        .task {
            await loadThreadContext()
        }
    }
    
    private func loadThreadContext() async {
        guard let ndk = appState.ndk else { return }
        
        do {
            // Load ancestors to understand thread context
            let ancestors = try await ndk.loadAncestors(of: parentEvent)
            let rootEvent = ancestors.last ?? parentEvent
            
            // Get thread info for context
            let thread = try await ndk.reconstructThread(
                from: rootEvent,
                options: ThreadOptions(maxDepth: 1) // Just need participants
            )
            
            threadContext = ThreadContext(
                rootEvent: rootEvent,
                participants: thread.participants,
                depth: ancestors.count
            )
        } catch {
            // Continue without context
            print("Failed to load thread context: \(error)")
        }
    }
    
    private func postReply() async {
        isPosting = true
        
        do {
            guard let ndk = appState.ndk,
                  let signer = appState.signer else { return }
            
            // Upload images if any
            var additionalTags: [[String]] = []
            if !selectedImages.isEmpty {
                let imageUrls = try await uploadImages(selectedImages)
                // Add image tags (imeta for NIP-92)
                for url in imageUrls {
                    additionalTags.append(["imeta", url])
                }
            }
            
            // Create reply using the thread-aware API
            let replyBuilder = parentEvent.createReply(
                content: replyText,
                additionalTags: additionalTags
            )
            
            // Sign and publish
            let reply = try await replyBuilder.sign(using: signer)
            try await ndk.publish(reply)
            
            // Success
            await MainActor.run {
                dismiss()
                // Show success toast
                NotificationCenter.default.post(
                    name: .replyPosted,
                    object: nil,
                    userInfo: ["reply": reply, "parent": parentEvent]
                )
            }
            
        } catch {
            // Show error
            await MainActor.run {
                // Show error alert
            }
        }
        
        isPosting = false
    }
}
```

## 3. Feed Integration with Thread Previews

```swift
struct FeedView: View {
    @EnvironmentObject var appState: AppState
    @State private var feedItems: [FeedItem] = []
    @State private var threadPreviews: [String: ThreadPreview] = [:]
    
    struct ThreadPreview {
        let replyCount: Int
        let lastReplyTime: Date?
        let participants: [String]
    }
    
    var body: some View {
        List(feedItems) { item in
            VStack(spacing: 0) {
                // Main post
                PostCard(event: item.event)
                
                // Thread preview if has replies
                if let preview = threadPreviews[item.event.id], preview.replyCount > 0 {
                    ThreadPreviewBar(
                        preview: preview,
                        onTap: {
                            // Navigate to full thread
                            NavigationLink(
                                destination: ThreadView(rootEvent: item.event)
                            ) {
                                EmptyView()
                            }
                        }
                    )
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
            }
            .onAppear {
                // Load thread preview for visible items
                Task {
                    await loadThreadPreview(for: item.event)
                }
            }
        }
        .refreshable {
            await refreshFeed()
        }
    }
    
    private func loadThreadPreview(for event: NDKEvent) async {
        guard let ndk = appState.ndk,
              threadPreviews[event.id] == nil else { return }
        
        do {
            // Just load direct replies for preview
            let replies = try await ndk.loadReplies(
                to: event,
                options: ThreadOptions(
                    maxDepth: 1,
                    timeout: 5,
                    cachePolicy: .cacheOnly // Fast preview
                )
            )
            
            if !replies.isEmpty {
                let preview = ThreadPreview(
                    replyCount: replies.count,
                    lastReplyTime: replies.map { Date(timeIntervalSince1970: Double($0.createdAt)) }.max(),
                    participants: Array(Set(replies.map { $0.pubkey })).prefix(3).map { String($0) }
                )
                
                await MainActor.run {
                    threadPreviews[event.id] = preview
                }
            }
        } catch {
            // Ignore preview loading errors
        }
    }
}

struct ThreadPreviewBar: View {
    let preview: FeedView.ThreadPreview
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.caption)
                    .foregroundColor(.blue)
                
                Text("\(preview.replyCount) replies")
                    .font(.caption)
                    .foregroundColor(.primary)
                
                if let lastReply = preview.lastReplyTime {
                    Text("• Last reply \(lastReply, formatter: RelativeDateTimeFormatter())")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Participant avatars
                HStack(spacing: -8) {
                    ForEach(preview.participants.prefix(3), id: \.self) { pubkey in
                        MiniAvatar(pubkey: pubkey)
                            .frame(width: 20, height: 20)
                    }
                }
                
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.tertiary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
```

## 4. Real-time Thread Updates

```swift
struct LiveThreadView: View {
    let rootEvent: NDKEvent
    @EnvironmentObject var appState: AppState
    
    @State private var thread: NDKThread?
    @State private var liveUpdateCount = 0
    @State private var showNewRepliesButton = false
    
    var body: some View {
        ZStack(alignment: .top) {
            // Main thread view
            ScrollViewReader { proxy in
                ScrollView {
                    if let thread = thread {
                        LazyVStack(spacing: 0) {
                            ForEach(thread.flatten(), id: \.event.id) { node in
                                ThreadEventRow(
                                    node: node,
                                    isNew: isNewEvent(node.event.id)
                                )
                                .id(node.event.id)
                            }
                        }
                    }
                }
                .onChange(of: liveUpdateCount) { _, _ in
                    // Auto-scroll to new content
                    if let lastEvent = thread?.flatten().last {
                        withAnimation {
                            proxy.scrollTo(lastEvent.event.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            // New replies indicator
            if showNewRepliesButton {
                NewRepliesButton(count: liveUpdateCount) {
                    showNewRepliesButton = false
                    liveUpdateCount = 0
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .task {
            await startLiveUpdates()
        }
    }
    
    private func startLiveUpdates() async {
        guard let ndk = appState.ndk else { return }
        
        // Initial load
        thread = try? await ndk.reconstructThread(from: rootEvent)
        
        // Subscribe to updates
        for await update in ndk.observeThread(thread!) {
            switch update {
            case .newReply(let reply, _):
                await MainActor.run {
                    // Increment counter
                    liveUpdateCount += 1
                    showNewRepliesButton = true
                    
                    // Auto-hide after delay
                    Task {
                        try? await Task.sleep(nanoseconds: 5_000_000_000)
                        showNewRepliesButton = false
                    }
                }
            default:
                break
            }
        }
    }
}
```

## Key Benefits for Apps

1. **Simplified Code**: Apps don't need to understand NIP-10 vs NIP-22 differences
2. **Consistent UX**: Thread navigation works the same regardless of event types
3. **Performance**: Built-in caching and lazy loading
4. **Real-time**: Live updates without manual subscription management
5. **Type Safety**: Strongly typed thread structures prevent errors
6. **Flexibility**: Options for different loading strategies

The API handles all the complexity while apps focus on UI and user experience.