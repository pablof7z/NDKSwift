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
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Gradient background
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: Color(.systemBackground), location: 0),
                        .init(color: Color(.systemBackground).opacity(0.97), location: 0.1),
                        .init(color: Color(.secondarySystemBackground).opacity(0.4), location: 1)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Thread content
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 0) {
                                // Root event
                                ThreadEventView(
                                    event: rootEvent,
                                    isRoot: true,
                                    onAvatarTap: {
                                        selectedProfile = rootEvent.pubkey
                                    }
                                )
                                .id("root")
                                
                                Divider()
                                    .padding(.leading, 20)
                                
                                // Replies
                                ForEach(replies.sorted(by: { $0.createdAt < $1.createdAt }), id: \.id) { reply in
                                    ThreadReplyView(
                                        event: reply,
                                        isReplyingTo: replyingTo?.id == reply.id,
                                        subReplies: subThreads[reply.id] ?? [],
                                        onTap: {
                                            withAnimation {
                                                replyingTo = replyingTo?.id == reply.id ? nil : reply
                                            }
                                        },
                                        onAvatarTap: {
                                            selectedProfile = reply.pubkey
                                        },
                                        onSubThreadTap: {
                                            // TODO: Navigate to sub-thread view
                                        }
                                    )
                                    .id(reply.id)
                                    
                                    if reply.id != replies.last?.id {
                                        Divider()
                                            .padding(.leading, 72)
                                    }
                                }
                                
                                // Loading indicator
                                if isLoadingReplies {
                                    ProgressView()
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
                    Text("Thread")
                        .font(.headline)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(item: $selectedProfile) { pubkey in
            ProfileView(pubkey: pubkey)
        }
        .onAppear {
            loadThread()
        }
        .onDisappear {
            subscriptionTask?.cancel()
        }
    }
    
    private var replyComposer: some View {
        VStack(spacing: 0) {
            // Reply target indicator
            if let target = replyingTo {
                HStack {
                    ProfileLoader(pubkey: target.pubkey) { profile in
                        Text("Replying to \(profile?.displayName ?? "Unknown")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        withAnimation {
                            replyingTo = nil
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(.tertiarySystemFill))
            }
            
            // Reply input
            HStack(spacing: 12) {
                TextField("Reply to thread...", text: $replyText, axis: .vertical)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .lineLimit(1...5)
                
                Button(action: sendReply) {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(replyText.isEmpty ? .secondary : .accentColor)
                }
                .disabled(replyText.isEmpty)
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
                
                let replyEvent = try await ndk.event()
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
                    // Avatar
                    Button(action: onAvatarTap) {
                        if let avatarURL = profile?.picture, let url = URL(string: avatarURL) {
                            AsyncImage(url: url) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Circle()
                                    .fill(Color(.tertiarySystemFill))
                            }
                            .frame(width: 48, height: 48)
                            .clipShape(Circle())
                        } else {
                            Circle()
                                .fill(Color(.tertiarySystemFill))
                                .frame(width: 48, height: 48)
                                .overlay(
                                    Text(String(profile?.name?.prefix(1) ?? "?").uppercased())
                                        .font(.system(size: 20, weight: .medium))
                                        .foregroundColor(.secondary)
                                )
                        }
                    }
                    
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
                
                // Content
                RichTextView(
                    content: event.content,
                    tags: event.tags,
                    currentUser: nil
                )
                .font(.system(size: 15))
                .textSelection(.enabled)
            }
            .padding()
            .background(isRoot ? Color(.secondarySystemBackground).opacity(0.3) : Color.clear)
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
    
    var body: some View {
        ProfileLoader(pubkey: event.pubkey) { profile in
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    // Avatar
                    Button(action: onAvatarTap) {
                        if let avatarURL = profile?.picture, let url = URL(string: avatarURL) {
                            AsyncImage(url: url) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Circle()
                                    .fill(Color(.tertiarySystemFill))
                            }
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())
                        } else {
                            Circle()
                                .fill(Color(.tertiarySystemFill))
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Text(String(profile?.name?.prefix(1) ?? "?").uppercased())
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.secondary)
                                )
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
                .background(isReplyingTo ? Color.accentColor.opacity(0.1) : Color.clear)
                .contentShape(Rectangle())
                .onTapGesture(perform: onTap)
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
            let profileStream = await ndk.profileManager.observe(for: pubkey)
            
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