import SwiftUI
import NDKSwift

struct ReplyView: View {
    let parentEvent: NDKEvent
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = ReplyViewModel()
    @State private var replyText = ""
    @State private var isReplying = false
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Parent post context
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Parent post header
                        ParentPostHeader(event: parentEvent, profile: viewModel.parentProfile)
                            .padding(OlasDesign.Spacing.md)
                            .background(OlasDesign.Colors.surface)
                        
                        Divider()
                            .background(OlasDesign.Colors.border)
                        
                        // Replies list
                        if viewModel.replies.isEmpty && !viewModel.isLoading {
                            EmptyRepliesView()
                                .padding(.vertical, OlasDesign.Spacing.xl)
                        } else {
                            LazyVStack(spacing: 0) {
                                ForEach(viewModel.replies) { reply in
                                    ReplyItemView(reply: reply)
                                    
                                    if reply.id != viewModel.replies.last?.id {
                                        Divider()
                                            .background(OlasDesign.Colors.border)
                                            .padding(.leading, 60)
                                    }
                                }
                            }
                        }
                        
                        if viewModel.isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, OlasDesign.Spacing.xl)
                        }
                    }
                }
                
                // Reply input
                VStack(spacing: 0) {
                    Divider()
                        .background(OlasDesign.Colors.border)
                    
                    HStack(alignment: .bottom, spacing: OlasDesign.Spacing.sm) {
                        // User avatar
                        if let currentUser = appState.currentUserProfile {
                            OlasAvatar(
                                url: currentUser.picture,
                                size: 32,
                                pubkey: appState.currentUser?.pubkey ?? ""
                            )
                        }
                        
                        // Reply field
                        VStack(alignment: .leading, spacing: 4) {
                            if isReplying {
                                Text("Replying to @\(viewModel.parentProfile?.name ?? "...")")
                                    .font(OlasDesign.Typography.caption)
                                    .foregroundColor(OlasDesign.Colors.textSecondary)
                            }
                            
                            HStack(alignment: .bottom) {
                                TextField("Add a reply...", text: $replyText, axis: .vertical)
                                    .textFieldStyle(PlainTextFieldStyle())
                                    .font(OlasDesign.Typography.body)
                                    .foregroundColor(OlasDesign.Colors.text)
                                    .lineLimit(1...5)
                                    .onSubmit {
                                        if !replyText.isEmpty {
                                            sendReply()
                                        }
                                    }
                                
                                if !replyText.isEmpty {
                                    Button(action: sendReply) {
                                        Image(systemName: "arrow.up.circle.fill")
                                            .font(.title2)
                                            .foregroundStyle(
                                                LinearGradient(
                                                    colors: [OlasDesign.Colors.primary, OlasDesign.Colors.secondary],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                    }
                                    .disabled(isReplying)
                                }
                            }
                        }
                        .padding(.horizontal, OlasDesign.Spacing.sm)
                        .padding(.vertical, OlasDesign.Spacing.xs)
                        .background(OlasDesign.Colors.surface)
                        .cornerRadius(20)
                    }
                    .padding(OlasDesign.Spacing.md)
                }
                .background(OlasDesign.Colors.background)
            }
            .background(OlasDesign.Colors.background)
            .navigationTitle("Replies")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                if let ndk = appState.ndk {
                    viewModel.loadReplies(for: parentEvent, ndk: ndk)
                }
            }
        }
    }
    
    private func sendReply() {
        guard let ndk = appState.ndk,
              let signer = NDKAuthManager.shared.activeSigner,
              !replyText.isEmpty else { return }
        
        isReplying = true
        OlasDesign.Haptic.selection()
        
        Task { @MainActor in
            do {
                // Build reply tags
                let tags = buildReplyTags(for: parentEvent)
                
                // Create reply event using builder
                let reply = try await ndk.event()
                    .kind(1)
                    .content(replyText)
                    .tags(tags)
                    .build(signer: signer)
                
                _ = try await ndk.publish(reply)
                
                await MainActor.run {
                    replyText = ""
                    isReplying = false
                    OlasDesign.Haptic.success()
                }
            } catch {
                print("Error sending reply: \(error)")
                await MainActor.run {
                    isReplying = false
                    OlasDesign.Haptic.error()
                }
            }
        }
    }
    
    private func buildReplyTags(for parentEvent: NDKEvent) -> [[String]] {
        var tags: [[String]] = [
            ["e", parentEvent.id, "", "reply"],
            ["p", parentEvent.pubkey]
        ]
        
        // Add root reference if this is a nested reply
        if let rootTag = parentEvent.tags.first(where: { tag in
            tag.count >= 4 && tag[0] == "e" && tag[3] == "root"
        }) {
            tags.insert(["e", rootTag[1], "", "root"], at: 0)
        } else if !parentEvent.tags.filter({ tag in
            tag.count >= 2 && tag[0] == "e"
        }).isEmpty {
            // Parent is already a reply, use its parent as root
            if let parentRef = parentEvent.tags.first(where: { tag in
                tag.count >= 2 && tag[0] == "e"
            }) {
                tags.insert(["e", parentRef[1], "", "root"], at: 0)
            }
        } else {
            // Parent is the root
            tags.insert(["e", parentEvent.id, "", "root"], at: 0)
        }
        
        return tags
    }
}

struct ParentPostHeader: View {
    let event: NDKEvent
    let profile: NDKUserProfile?
    
    var body: some View {
        VStack(alignment: .leading, spacing: OlasDesign.Spacing.sm) {
            HStack(spacing: OlasDesign.Spacing.sm) {
                OlasAvatar(
                    url: profile?.picture,
                    size: 40,
                    pubkey: event.pubkey
                )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile?.displayName ?? profile?.name ?? "Loading...")
                        .font(OlasDesign.Typography.bodyMedium)
                        .foregroundColor(OlasDesign.Colors.text)
                    
                    Text("@\(profile?.name ?? String(event.pubkey.prefix(8)))")
                        .font(OlasDesign.Typography.caption)
                        .foregroundColor(OlasDesign.Colors.textSecondary)
                }
                
                Spacer()
                
                Text(formatTimestamp(event.createdAt))
                    .font(OlasDesign.Typography.caption)
                    .foregroundColor(OlasDesign.Colors.textTertiary)
            }
            
            OlasRichText(
                content: event.content,
                tags: event.tags
            )
        }
    }
    
    private func formatTimestamp(_ timestamp: Timestamp) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct ReplyItemView: View {
    let reply: ReplyItem
    @EnvironmentObject var appState: AppState
    @State private var showingNestedReplies = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: OlasDesign.Spacing.sm) {
                OlasAvatar(
                    url: reply.profile?.picture,
                    size: 32,
                    pubkey: reply.event.pubkey
                )
                
                VStack(alignment: .leading, spacing: OlasDesign.Spacing.xs) {
                    HStack(spacing: OlasDesign.Spacing.xs) {
                        Text(reply.profile?.displayName ?? reply.profile?.name ?? "Loading...")
                            .font(OlasDesign.Typography.bodyMedium)
                            .foregroundColor(OlasDesign.Colors.text)
                        
                        Text("@\(reply.profile?.name ?? String(reply.event.pubkey.prefix(8)))")
                            .font(OlasDesign.Typography.caption)
                            .foregroundColor(OlasDesign.Colors.textSecondary)
                        
                        Text("·")
                            .font(OlasDesign.Typography.caption)
                            .foregroundColor(OlasDesign.Colors.textTertiary)
                        
                        Text(formatTimestamp(reply.event.createdAt))
                            .font(OlasDesign.Typography.caption)
                            .foregroundColor(OlasDesign.Colors.textTertiary)
                        
                        Spacer()
                    }
                    
                    OlasRichText(
                        content: reply.event.content,
                        tags: reply.event.tags
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    
                    // Reply actions
                    HStack(spacing: OlasDesign.Spacing.lg) {
                        Button(action: {
                            showingNestedReplies.toggle()
                            OlasDesign.Haptic.selection()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "bubble.left")
                                    .font(.caption)
                                if reply.replyCount > 0 {
                                    Text("\(reply.replyCount)")
                                        .font(OlasDesign.Typography.caption)
                                }
                            }
                            .foregroundColor(OlasDesign.Colors.textSecondary)
                        }
                        
                        Spacer()
                    }
                    .padding(.top, OlasDesign.Spacing.xs)
                }
            }
            .padding(OlasDesign.Spacing.md)
            
            if showingNestedReplies && reply.replyCount > 0 {
                // TODO: Show nested replies
                Text("Nested replies coming soon...")
                    .font(OlasDesign.Typography.caption)
                    .foregroundColor(OlasDesign.Colors.textTertiary)
                    .padding(.leading, 60)
                    .padding(.bottom, OlasDesign.Spacing.sm)
            }
        }
    }
    
    private func formatTimestamp(_ timestamp: Timestamp) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct EmptyRepliesView: View {
    var body: some View {
        VStack(spacing: OlasDesign.Spacing.md) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundColor(OlasDesign.Colors.textTertiary)
            
            Text("No replies yet")
                .font(OlasDesign.Typography.title3)
                .foregroundColor(OlasDesign.Colors.textSecondary)
            
            Text("Be the first to reply!")
                .font(OlasDesign.Typography.body)
                .foregroundColor(OlasDesign.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

@MainActor
class ReplyViewModel: ObservableObject {
    @Published var replies: [ReplyItem] = []
    @Published var parentProfile: NDKUserProfile?
    @Published var isLoading = false
    private var profileTasks: [String: Task<Void, Never>] = [:]
    
    func loadReplies(for event: NDKEvent, ndk: NDK) {
        isLoading = true
        
        Task {
            // Load parent profile
            if let profileManager = ndk.profileManager {
                for await profile in await profileManager.observe(for: event.pubkey, maxAge: 3600) {
                    if let profile = profile {
                        await MainActor.run {
                            self.parentProfile = profile
                        }
                        break
                    }
                }
            }
            
            // Load replies
            let filter = NDKFilter(
                kinds: [1],
                events: [event.id]
            )
            
            let dataSource = ndk.observe(filter: filter, cachePolicy: .cacheWithNetwork)
            
            for await replyEvent in dataSource.events {
                // Check if this is a direct reply to our event
                let isDirectReply = replyEvent.tags.contains { tag in
                    tag.count >= 4 && tag[0] == "e" && tag[1] == event.id && tag[3] == "reply"
                } || replyEvent.tags.contains { tag in
                    tag.count >= 2 && tag[0] == "e" && tag[1] == event.id
                }
                
                if isDirectReply {
                    let replyItem = ReplyItem(event: replyEvent)
                    
                    await MainActor.run {
                        if !replies.contains(where: { $0.id == replyItem.id }) {
                            replies.append(replyItem)
                            replies.sort { $0.event.createdAt < $1.event.createdAt }
                        }
                        isLoading = false
                    }
                    
                    // Load profile for reply author
                    loadProfileReactively(for: replyEvent.pubkey, ndk: ndk)
                    
                    // Count nested replies
                    countNestedReplies(for: replyEvent, ndk: ndk)
                }
            }
            
            await MainActor.run {
                isLoading = false
            }
        }
    }
    
    private func loadProfileReactively(for pubkey: String, ndk: NDK) {
        profileTasks[pubkey]?.cancel()
        
        profileTasks[pubkey] = Task {
            guard let profileManager = ndk.profileManager else { return }
            
            for await profile in await profileManager.observe(for: pubkey, maxAge: 3600) {
                if let profile = profile {
                    await MainActor.run {
                        updateRepliesWithProfile(pubkey: pubkey, profile: profile)
                    }
                }
            }
        }
    }
    
    private func updateRepliesWithProfile(pubkey: String, profile: NDKUserProfile) {
        for index in replies.indices {
            if replies[index].event.pubkey == pubkey {
                replies[index].profile = profile
            }
        }
    }
    
    private func countNestedReplies(for event: NDKEvent, ndk: NDK) {
        Task {
            let filter = NDKFilter(
                kinds: [1],
                events: [event.id]
            )
            
            let dataSource = ndk.observe(filter: filter, cachePolicy: .cacheOnly)
            let nestedReplies = await dataSource.collect(timeout: 1.0)
            let count = nestedReplies.filter { reply in
                reply.tags.contains { tag in
                    tag.count >= 4 && tag[0] == "e" && tag[1] == event.id && tag[3] == "reply"
                } || reply.tags.contains { tag in
                    tag.count >= 2 && tag[0] == "e" && tag[1] == event.id
                }
            }.count
            
            await MainActor.run {
                if let index = replies.firstIndex(where: { $0.id == event.id }) {
                    replies[index].replyCount = count
                }
            }
        }
    }
}

struct ReplyItem: Identifiable {
    let id: String
    let event: NDKEvent
    var profile: NDKUserProfile?
    var replyCount: Int = 0
    
    init(event: NDKEvent) {
        self.id = event.id
        self.event = event
    }
}