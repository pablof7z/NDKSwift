import SwiftUI
import NDKSwift

struct MessagesListView: View {
    @Environment(NostrManager.self) private var nostrManager
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = MessagesViewModel()
    @State private var searchText = ""
    @State private var showNewMessage = false
    @State private var selectedConversation: Conversation?
    
    var body: some View {
        NavigationStack {
            ZStack {
                OlasDesign.Colors.background
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 0) {
                        // Search bar
                        searchBar
                            .padding(.horizontal, OlasDesign.Spacing.md)
                            .padding(.vertical, OlasDesign.Spacing.sm)
                        
                        // Stories-like row for active users
                        if !viewModel.activeUsers.isEmpty {
                            activeUsersRow
                                .padding(.bottom, OlasDesign.Spacing.md)
                        }
                        
                        // Conversations list
                        if viewModel.conversations.isEmpty && viewModel.isLoading {
                            loadingView
                        } else if viewModel.conversations.isEmpty {
                            emptyStateView
                        } else {
                            conversationsList
                        }
                    }
                }
            }
            .navigationTitle("Messages")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                #else
                ToolbarItem(placement: .automatic) {
                #endif
                    Button {
                        showNewMessage = true
                        OlasDesign.Haptic.selection()
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .foregroundStyle(OlasDesign.Colors.primary)
                    }
                }
            }
            .sheet(isPresented: $showNewMessage) {
                NewMessageView()
                    .environment(nostrManager)
                    .environmentObject(appState)
            }
            .navigationDestination(item: $selectedConversation) { conversation in
                ConversationView(conversation: conversation)
                    .environment(nostrManager)
                    .environmentObject(appState)
            }
            .task {
                if let ndk = nostrManager.ndk {
                    await viewModel.startObserving(ndk: ndk)
                }
            }
        }
    }
    
    private var searchBar: some View {
        HStack(spacing: OlasDesign.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(OlasDesign.Colors.textSecondary)
                .font(.system(size: 16))
            
            TextField("Search", text: $searchText)
                .textFieldStyle(PlainTextFieldStyle())
                .font(OlasDesign.Typography.body)
                .foregroundColor(OlasDesign.Colors.text)
            
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    OlasDesign.Haptic.selection()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(OlasDesign.Colors.textSecondary)
                        .font(.system(size: 16))
                }
            }
        }
        .padding(.horizontal, OlasDesign.Spacing.md)
        .padding(.vertical, OlasDesign.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.full)
                .fill(OlasDesign.Colors.surface)
        )
    }
    
    private var activeUsersRow: some View {
        VStack(alignment: .leading, spacing: OlasDesign.Spacing.sm) {
            Text("Active Now")
                .font(OlasDesign.Typography.caption)
                .foregroundColor(OlasDesign.Colors.textSecondary)
                .padding(.horizontal, OlasDesign.Spacing.md)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: OlasDesign.Spacing.md) {
                    ForEach(viewModel.activeUsers) { user in
                        ActiveUserView(user: user) {
                            // Start conversation with user
                            viewModel.createConversation(with: user.pubkey)
                        }
                    }
                }
                .padding(.horizontal, OlasDesign.Spacing.md)
            }
        }
    }
    
    private var conversationsList: some View {
        LazyVStack(spacing: 0) {
            ForEach(filteredConversations) { conversation in
                ConversationRowView(conversation: conversation) {
                    selectedConversation = conversation
                }
                
                if conversation.id != filteredConversations.last?.id {
                    Divider()
                        .padding(.leading, 90)
                }
            }
        }
    }
    
    private var filteredConversations: [Conversation] {
        if searchText.isEmpty {
            return viewModel.conversations
        } else {
            return viewModel.conversations.filter { conversation in
                conversation.displayName.localizedCaseInsensitiveContains(searchText) ||
                conversation.lastMessage?.content.localizedCaseInsensitiveContains(searchText) ?? false
            }
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: OlasDesign.Spacing.lg) {
            ForEach(0..<5) { _ in
                ConversationSkeletonView()
            }
        }
        .padding(.horizontal, OlasDesign.Spacing.md)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: OlasDesign.Spacing.xl) {
            Spacer()
            
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 80))
                .foregroundStyle(
                    LinearGradient(
                        colors: OlasDesign.Colors.primaryGradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            VStack(spacing: OlasDesign.Spacing.sm) {
                Text("No Messages Yet")
                    .font(OlasDesign.Typography.title)
                    .foregroundColor(OlasDesign.Colors.text)
                
                Text("Start a conversation with someone")
                    .font(OlasDesign.Typography.body)
                    .foregroundColor(OlasDesign.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            
            Button {
                showNewMessage = true
                #if os(iOS)
                OlasDesign.Haptic.impact(.medium)
                #else
                OlasDesign.Haptic.impact(0)
                #endif
            } label: {
                Text("Send a Message")
                    .font(OlasDesign.Typography.bodyBold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, OlasDesign.Spacing.xl)
                    .padding(.vertical, OlasDesign.Spacing.md)
                    .background(
                        LinearGradient(
                            colors: OlasDesign.Colors.primaryGradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.full))
            }
            
            Spacer()
            Spacer()
        }
        .padding(.horizontal, OlasDesign.Spacing.xl)
    }
}

// MARK: - Active User View
struct ActiveUserView: View {
    let user: ActiveUser
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: OlasDesign.Spacing.xs) {
                ZStack(alignment: .bottomTrailing) {
                    OlasAvatar(
                        url: user.profile?.picture,
                        size: 60,
                        pubkey: user.pubkey
                    )
                    
                    // Active indicator
                    Circle()
                        .fill(Color.green)
                        .frame(width: 16, height: 16)
                        .overlay(
                            Circle()
                                .stroke(OlasDesign.Colors.background, lineWidth: 3)
                        )
                }
                
                Text(user.profile?.name ?? String(user.pubkey.prefix(8)))
                    .font(OlasDesign.Typography.caption)
                    .foregroundColor(OlasDesign.Colors.text)
                    .lineLimit(1)
                    .frame(width: 70)
            }
        }
    }
}

// MARK: - Conversation Row
struct ConversationRowView: View {
    let conversation: Conversation
    let onTap: () -> Void
    @State private var avatarAnimation = false
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: OlasDesign.Spacing.md) {
                // Avatar with unread indicator
                ZStack(alignment: .topTrailing) {
                    OlasAvatar(
                        url: conversation.profile?.picture,
                        size: 60,
                        pubkey: conversation.peerPubkey
                    )
                    .scaleEffect(avatarAnimation ? 1.05 : 1)
                    .animation(
                        .easeInOut(duration: 0.3),
                        value: avatarAnimation
                    )
                    
                    if conversation.unreadCount > 0 {
                        Circle()
                            .fill(OlasDesign.Colors.primary)
                            .frame(width: 20, height: 20)
                            .overlay(
                                Text("\(min(conversation.unreadCount, 99))")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                            )
                            .offset(x: 5, y: -5)
                    }
                }
                
                // Content
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(conversation.displayName)
                            .font(conversation.unreadCount > 0 ? OlasDesign.Typography.bodyBold : OlasDesign.Typography.bodyMedium)
                            .foregroundColor(OlasDesign.Colors.text)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        if let timestamp = conversation.lastMessage?.timestamp {
                            Text(RelativeTimeFormatter.format(timestamp))
                                .font(OlasDesign.Typography.caption)
                                .foregroundColor(OlasDesign.Colors.textSecondary)
                        }
                    }
                    
                    if let lastMessage = conversation.lastMessage {
                        HStack(spacing: 4) {
                            if lastMessage.isFromMe {
                                Image(systemName: "checkmark")
                                    .font(.caption)
                                    .foregroundColor(
                                        lastMessage.isRead ? OlasDesign.Colors.primary : OlasDesign.Colors.textSecondary
                                    )
                            }
                            
                            Text(lastMessage.content)
                                .font(OlasDesign.Typography.body)
                                .foregroundColor(
                                    conversation.unreadCount > 0 ? OlasDesign.Colors.text : OlasDesign.Colors.textSecondary
                                )
                                .lineLimit(1)
                        }
                    }
                }
                
                // Chevron
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(OlasDesign.Colors.textTertiary)
            }
            .padding(.horizontal, OlasDesign.Spacing.md)
            .padding(.vertical, OlasDesign.Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            avatarAnimation = hovering
        }
    }
}

// MARK: - Skeleton View
struct ConversationSkeletonView: View {
    @State private var shimmerAnimation = false
    
    var body: some View {
        HStack(spacing: OlasDesign.Spacing.md) {
            Circle()
                .fill(OlasDesign.Colors.surface)
                .overlay(shimmerGradient)
                .frame(width: 60, height: 60)
            
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.xs)
                    .fill(OlasDesign.Colors.surface)
                    .overlay(shimmerGradient)
                    .frame(width: 120, height: 16)
                
                RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.xs)
                    .fill(OlasDesign.Colors.surface)
                    .overlay(shimmerGradient)
                    .frame(width: 200, height: 14)
            }
            
            Spacer()
        }
        .padding(.vertical, OlasDesign.Spacing.md)
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                shimmerAnimation = true
            }
        }
    }
    
    private var shimmerGradient: some View {
        LinearGradient(
            colors: [
                Color.white.opacity(0),
                Color.white.opacity(0.1),
                Color.white.opacity(0)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .rotationEffect(.degrees(30))
        .offset(x: shimmerAnimation ? 300 : -300)
    }
}

// MARK: - View Model
@MainActor
class MessagesViewModel: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var activeUsers: [ActiveUser] = []
    @Published var isLoading = true
    
    private var ndk: NDK?
    private var conversationTasks: [String: Task<Void, Never>] = [:]
    
    func startObserving(ndk: NDK) async {
        self.ndk = ndk
        
        // Load conversations from encrypted DMs (NIP-04)
        await loadConversations()
        
        // Monitor for new messages
        await observeNewMessages()
    }
    
    private func loadConversations() async {
        guard let ndk = ndk,
              let signer = NDKAuthManager.shared.activeSigner,
              let myPubkey = try? await signer.pubkey else { return }
        
        isLoading = true
        
        // Fetch encrypted DMs (kind 4)
        let filter = NDKFilter(
            kinds: [4],
            limit: 100
        )
        
        do {
            let messages = try await ndk.fetchEvents(filter: filter)
            
            // Group messages by conversation
            var conversationMap: [String: [NDKEvent]] = [:]
            
            for message in messages {
                let peerPubkey = message.pubkey == myPubkey 
                    ? (message.tags.first(where: { $0.count >= 2 && $0[0] == "p" })?[1] ?? "")
                    : message.pubkey
                
                if !peerPubkey.isEmpty {
                    conversationMap[peerPubkey, default: []].append(message)
                }
            }
            
            // Create conversation objects
            var loadedConversations: [Conversation] = []
            
            for (peerPubkey, messages) in conversationMap {
                let sortedMessages = messages.sorted { $0.createdAt > $1.createdAt }
                
                let conversation = Conversation(
                    peerPubkey: peerPubkey,
                    messages: sortedMessages,
                    myPubkey: myPubkey
                )
                
                loadedConversations.append(conversation)
            }
            
            // Sort by most recent message
            loadedConversations.sort { 
                ($0.lastMessage?.timestamp ?? Date.distantPast) > ($1.lastMessage?.timestamp ?? Date.distantPast)
            }
            
            await MainActor.run {
                self.conversations = loadedConversations
                self.isLoading = false
            }
            
            // Load profiles
            await loadProfiles()
            
        } catch {
            print("Failed to load conversations: \(error)")
            await MainActor.run {
                self.isLoading = false
            }
        }
    }
    
    private func observeNewMessages() async {
        guard let ndk = ndk,
              let signer = NDKAuthManager.shared.activeSigner,
              let myPubkey = try? await signer.pubkey else { return }
        
        let filter = NDKFilter(
            kinds: [4],
            since: Timestamp(Date())
        )
        
        for await message in await ndk.observe(filters: [filter]) {
            // Check if message involves us
            let isForUs = message.tags.contains { tag in
                tag.count >= 2 && tag[0] == "p" && tag[1] == myPubkey
            }
            let isFromUs = message.pubkey == myPubkey
            
            if isForUs || isFromUs {
                await handleNewMessage(message, myPubkey: myPubkey)
            }
        }
    }
    
    private func handleNewMessage(_ message: NDKEvent, myPubkey: String) async {
        let peerPubkey = message.pubkey == myPubkey 
            ? (message.tags.first(where: { $0.count >= 2 && $0[0] == "p" })?[1] ?? "")
            : message.pubkey
        
        await MainActor.run {
            if let index = conversations.firstIndex(where: { $0.peerPubkey == peerPubkey }) {
                // Update existing conversation
                conversations[index].messages.insert(message, at: 0)
                conversations[index].updateLastMessage()
                
                // Move to top
                let conversation = conversations.remove(at: index)
                conversations.insert(conversation, at: 0)
            } else {
                // Create new conversation
                let conversation = Conversation(
                    peerPubkey: peerPubkey,
                    messages: [message],
                    myPubkey: myPubkey
                )
                conversations.insert(conversation, at: 0)
            }
        }
        
        // Haptic feedback for new message
        OlasDesign.Haptic.notification()
    }
    
    private func loadProfiles() async {
        guard let profileManager = ndk?.profileManager else { return }
        
        for conversation in conversations {
            Task {
                for await profile in await profileManager.observe(for: conversation.peerPubkey, maxAge: 3600) {
                    if let profile = profile {
                        await MainActor.run {
                            if let index = self.conversations.firstIndex(where: { $0.id == conversation.id }) {
                                self.conversations[index].profile = profile
                            }
                        }
                    }
                    break
                }
            }
        }
    }
    
    func createConversation(with pubkey: String) {
        guard !conversations.contains(where: { $0.peerPubkey == pubkey }),
              let myPubkey = try? NDKAuthManager.shared.activeSigner?.pubkey else { return }
        
        let conversation = Conversation(
            peerPubkey: pubkey,
            messages: [],
            myPubkey: myPubkey ?? ""
        )
        
        conversations.insert(conversation, at: 0)
    }
}}
