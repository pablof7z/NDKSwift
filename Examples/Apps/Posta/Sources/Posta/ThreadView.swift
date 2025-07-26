import SwiftUI
import NDKSwift

struct ThreadView: View {
    let rootEvent: NDKEvent
    
    @Environment(NDKManager.self) var ndkManager
    @Environment(NDKAuthManager.self) var authManager
    @Environment(\.dismiss) var dismiss
    
    @State private var replies: [NDKEvent] = []
    @State private var replyingTo: NDKEvent?
    @State private var replyText: String = ""
    @State private var isLoadingReplies = true
    @State private var threadDataSource: NDKDataSource<NDKEvent>?
    @State private var subscriptionTask: Task<Void, Never>?
    @State private var selectedProfile: String?
    @State private var subThreads: [String: [NDKEvent]] = [:] // eventId -> replies
    @State private var showContent = false
    @State private var keyboardHeight: CGFloat = 0
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Animated gradient background
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(.systemBackground),
                        Color.purple.opacity(0.02),
                        Color(.systemBackground)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Thread content
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 0) {
                                // Root event with animation
                                ThreadEventView(
                                    event: rootEvent,
                                    isRoot: true,
                                    onAvatarTap: {
                                        selectedProfile = rootEvent.pubkey
                                    }
                                )
                                .id("root")
                                .opacity(showContent ? 1 : 0)
                                .scaleEffect(showContent ? 1 : 0.95)
                                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: showContent)
                                
                                Divider()
                                    .padding(.leading, 20)
                                
                                // Replies with staggered animation
                                ForEach(Array(replies.sorted(by: { $0.createdAt < $1.createdAt }).enumerated()), id: \.element.id) { index, reply in
                                    ThreadReplyView(
                                        event: reply,
                                        isReplyingTo: replyingTo?.id == reply.id,
                                        subReplies: subThreads[reply.id] ?? [],
                                        onTap: {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                                replyingTo = replyingTo?.id == reply.id ? nil : reply
                                                HapticFeedback.selection()
                                            }
                                        },
                                        onAvatarTap: {
                                            selectedProfile = reply.pubkey
                                        },
                                        onSubThreadTap: {
                                            HapticFeedback.impact(.light)
                                            // TODO: Navigate to sub-thread view
                                        }
                                    )
                                    .id(reply.id)
                                    .opacity(showContent ? 1 : 0)
                                    .offset(y: showContent ? 0 : 20)
                                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(Double(index) * 0.05), value: showContent)
                                    
                                    if reply.id != replies.last?.id {
                                        Divider()
                                            .padding(.leading, 72)
                                    }
                                }
                                
                                // Loading indicator
                                if isLoadingReplies {
                                    LoadingDots(dotSize: 10, color: .purple)
                                        .padding()
                                }
                            }
                        }
                    }
                    
                    // Reply composition
                    replyComposer
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 16))
                            .foregroundColor(.purple)
                        Text("Thread")
                            .font(.headline)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        HapticFeedback.impact(.light)
                        dismiss()
                    }) {
                        Text("Done")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.purple)
                    }
                }
            }
        }
        .sheet(item: $selectedProfile) { pubkey in
            ProfileView(pubkey: pubkey)
        }
        .onAppear {
            loadThread()
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.1)) {
                showContent = true
            }
        }
        .onDisappear {
            subscriptionTask?.cancel()
        }
    }
    
    private var replyComposer: some View {
        VStack(spacing: 0) {
            // Reply target indicator with animation
            if let target = replyingTo {
                HStack {
                    ProfileLoader(pubkey: target.pubkey) { profile in
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.turn.up.right")
                                .font(.system(size: 12))
                                .foregroundColor(.purple)
                            Text("Replying to \(profile?.displayName ?? "Unknown")")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.primary)
                        }
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            replyingTo = nil
                            HapticFeedback.impact(.light)
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 16))
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.purple.opacity(0.1),
                            Color.purple.opacity(0.05)
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .transition(.asymmetric(
                    insertion: .push(from: .top).combined(with: .opacity),
                    removal: .push(from: .bottom).combined(with: .opacity)
                ))
            }
            
            // Reply input with modern styling
            HStack(spacing: 12) {
                TextField("Reply to thread...", text: $replyText, axis: .vertical)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color(.systemGray6))
                    )
                    .lineLimit(1...5)
                
                Button(action: {
                    sendReply()
                    HapticFeedback.notification(.success)
                }) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: replyText.isEmpty ? 
                                        [Color(.systemGray5), Color(.systemGray5)] :
                                        [Color.purple, Color.purple.opacity(0.8)]
                                    ),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 36, height: 36)
                        
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                            .rotationEffect(.degrees(45))
                    }
                }
                .disabled(replyText.isEmpty)
                .scaleEffect(replyText.isEmpty ? 1 : 1.1)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: replyText.isEmpty)
            }
            .padding()
            .background(
                VisualEffectBlur(blurStyle: .systemUltraThinMaterial)
                    .ignoresSafeArea()
            )
        }
    }
    
    private func loadThread() {
        guard let ndk = ndkManager.ndk else { return }
        
        // Subscribe to replies
        subscriptionTask = Task {
            let replyFilter = NDKFilter(
                kinds: [EventKind.textNote],
                tags: ["e": Set([rootEvent.id])]
            )
            
            threadDataSource = ndk.observe(filter: replyFilter)
            
            guard let dataSource = threadDataSource else { return }
            
            for await reply in dataSource.events {
                await MainActor.run {
                    // Add reply if it's new
                    if !replies.contains(where: { $0.id == reply.id }) {
                        replies.append(reply)
                        
                        // Check for sub-replies (replies to this reply)
                        loadSubReplies(for: reply.id)
                    }
                }
            }
            
            await MainActor.run {
                isLoadingReplies = false
            }
        }
    }
    private func loadSubReplies(for eventId: String) {
        guard let ndk = ndkManager.ndk else { return }
        
        Task {
            let subReplyFilter = NDKFilter(
                kinds: [EventKind.textNote],
                tags: ["e": Set([eventId])]
            )
            
            // Use observe with maxAge > 0 to fetch and close after EOSE
            let dataSource = ndk.observe(filter: subReplyFilter, maxAge: 60)
            var events: [NDKEvent] = []
            
            for await event in dataSource.events {
                events.append(event)
            }
            
            await MainActor.run {
                var subReplies: [NDKEvent] = []
                
                for event in events {
                    // Check if this is a direct reply to the target event
                    let eTags = event.tags.filter { $0.count >= 2 && $0[0] == "e" }
                    if let lastETag = eTags.last, lastETag[1] == eventId {
                        subReplies.append(event)
                    }
                }
                
                if !subReplies.isEmpty {
                    self.subThreads[eventId] = subReplies
                }
            }
        }
    }
    
    private func sendReply() {
        guard let ndk = ndkManager.ndk,
              let signer = authManager.activeSigner,
              !replyText.isEmpty else { return }
        
        Task {
            do {
                let targetEvent = replyingTo ?? rootEvent
                
                // Build NIP-10 compliant tags
                var tags: [Tag] = []
                
                // Add root tag if we're replying to a reply
                if targetEvent.id != rootEvent.id {
                    tags.append(["e", rootEvent.id, "", "root"])
                }
                
                // Add reply tag
                tags.append(["e", targetEvent.id, "", "reply"])
                
                // Add p tags for mentioned users
                tags.append(["p", targetEvent.pubkey])
                if targetEvent.id != rootEvent.id {
                    tags.append(["p", rootEvent.pubkey])
                }
                
                let replyEvent = try await NDKEventBuilder(ndk: ndk)
                    .kind(EventKind.textNote)
                    .content(replyText)
                    .tags(tags)
                    .build(signer: signer)
                
                try await ndk.publish(replyEvent)
                
                await MainActor.run {
                    replyText = ""
                    replyingTo = nil
                }
            } catch {
                print("Failed to send reply: \(error)")
            }
        }
    }
}

struct ThreadEventView: View {
    let event: NDKEvent
    let isRoot: Bool
    let onAvatarTap: () -> Void
    
    @Environment(NDKManager.self) var ndkManager
    
    var body: some View {
        ProfileLoader(pubkey: event.pubkey) { profile in
            VStack(alignment: .leading, spacing: 12) {
                // Author info
                HStack(alignment: .top, spacing: 12) {
                    // Avatar with enhanced styling
                    Button(action: {
                        onAvatarTap()
                        HapticFeedback.impact(.light)
                    }) {
                        EnhancedAvatarView(
                            url: profile?.picture.flatMap { URL(string: $0) },
                            size: 52,
                            fallbackText: String(profile?.name?.prefix(1) ?? "?").uppercased(),
                            showOnlineIndicator: false
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // Name and time
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile?.displayName ?? profile?.name ?? "Unknown")
                            .font(.system(size: 16, weight: .semibold))
                        
                        Text(event.createdAt.formatted)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                
                // Content with enhanced typography
                RichTextView(
                    content: event.content,
                    tags: event.tags,
                    currentUser: nil
                )
                .font(.system(size: isRoot ? 16 : 15))
                .textSelection(.enabled)
                
                // Engagement stats for root event
                if isRoot {
                    HStack(spacing: 20) {
                        HStack(spacing: 4) {
                            Image(systemName: "bubble.left")
                                .font(.system(size: 14))
                            Text("0")
                                .font(.system(size: 14))
                        }
                        .foregroundColor(.secondary)
                        
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.2.squarepath")
                                .font(.system(size: 14))
                            Text("0")
                                .font(.system(size: 14))
                        }
                        .foregroundColor(.secondary)
                        
                        HStack(spacing: 4) {
                            Image(systemName: "heart")
                                .font(.system(size: 14))
                            Text("0")
                                .font(.system(size: 14))
                        }
                        .foregroundColor(.secondary)
                        
                        Spacer()
                    }
                    .padding(.top, 8)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: isRoot ? 16 : 0)
                    .fill(isRoot ? 
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.purple.opacity(0.05),
                                Color.purple.opacity(0.02)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ) : 
                        LinearGradient(
                            gradient: Gradient(colors: [Color.clear, Color.clear]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .padding(.horizontal, isRoot ? 12 : 0)
        }
    }
}

struct ThreadReplyView: View {
    let event: NDKEvent
    let isReplyingTo: Bool
    let subReplies: [NDKEvent]
    let onTap: () -> Void
    let onAvatarTap: () -> Void
    let onSubThreadTap: () -> Void
    
    @Environment(NDKManager.self) var ndkManager
    @State private var isPressed = false
    
    var body: some View {
        ProfileLoader(pubkey: event.pubkey) { profile in
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    // Thread line and avatar
                    VStack(spacing: 4) {
                        Button(action: {
                            onAvatarTap()
                            HapticFeedback.impact(.light)
                        }) {
                            EnhancedAvatarView(
                                url: profile?.picture.flatMap { URL(string: $0) },
                                size: 40,
                                fallbackText: String(profile?.name?.prefix(1) ?? "?").uppercased(),
                                showOnlineIndicator: false
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // Thread line
                        if !subReplies.isEmpty {
                            Rectangle()
                                .fill(Color.purple.opacity(0.2))
                                .frame(width: 2)
                                .frame(maxHeight: .infinity)
                        }
                    }
                    .padding(.leading, 20)
                    
                    // Content
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(profile?.displayName ?? profile?.name ?? "Unknown")
                                .font(.system(size: 15, weight: .medium))
                            
                            Text("·")
                                .foregroundColor(.secondary)
                            
                            Text(event.createdAt.formatted)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                        }
                        
                        RichTextView(
                            content: event.content,
                            tags: event.tags,
                            currentUser: nil
                        )
                        .font(.system(size: 15))
                        .foregroundColor(.primary.opacity(0.9))
                    
                        // Sub-thread indicator
                        if !subReplies.isEmpty {
                            SubThreadIndicator(
                                subReplies: subReplies,
                                onTap: onSubThreadTap
                            )
                            .padding(.top, 8)
                        }
                    }
                    .padding(.trailing, 20)
                }
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isReplyingTo ? 
                            Color.purple.opacity(0.1) : 
                            (isPressed ? Color.purple.opacity(0.05) : Color.clear)
                        )
                        .padding(.horizontal, 12)
                )
                .contentShape(Rectangle())
                .scaleEffect(isPressed ? 0.98 : 1)
                .onLongPressGesture(
                    minimumDuration: 0,
                    maximumDistance: .infinity,
                    pressing: { pressing in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            isPressed = pressing
                        }
                    },
                    perform: onTap
                )
            }
        }
    }
}

// Simplified sub-thread indicator view
struct SubThreadIndicator: View {
    let subReplies: [NDKEvent]
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                // Avatar stack - show first 3 unique reply authors
                HStack(spacing: -6) {
                    ForEach(Array(Set(subReplies.prefix(3).map { $0.pubkey })).prefix(3), id: \.self) { pubkey in
                        MiniAvatar(pubkey: pubkey)
                    }
                }
                
                Text("\(subReplies.count) \(subReplies.count == 1 ? "reply" : "replies")")
                    .font(.caption)
                    .foregroundColor(.accentColor)
                
                Spacer()
            }
        }
    }
}

// Mini avatar for sub-thread indicator
struct MiniAvatar: View {
    let pubkey: String
    
    @Environment(NDKManager.self) var ndkManager
    @State private var profile: NDKUserProfile?
    @State private var profileTask: Task<Void, Never>?
    
    var body: some View {
        Group {
            if let avatarURL = profile?.picture, let url = URL(string: avatarURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle()
                        .fill(Color(.tertiarySystemFill))
                }
                .frame(width: 20, height: 20)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color(.systemBackground), lineWidth: 1.5)
                )
            } else {
                Circle()
                    .fill(Color(.tertiarySystemFill))
                    .frame(width: 20, height: 20)
                    .overlay(
                        Circle()
                            .stroke(Color(.systemBackground), lineWidth: 1.5)
                    )
            }
        }
        .onAppear {
            loadProfile()
        }
        .onDisappear {
            profileTask?.cancel()
        }
    }
    
    private func loadProfile() {
        guard let ndk = ndkManager.ndk else { return }
        
        profileTask = Task {
            let profileStream = await ndk.profileManager.observe(for: pubkey, maxAge: TimeConstants.hour)
            
            for await profile in profileStream {
                if let profile = profile {
                    await MainActor.run {
                        self.profile = profile
                    }
                    break
                }
            }
        }
    }
}