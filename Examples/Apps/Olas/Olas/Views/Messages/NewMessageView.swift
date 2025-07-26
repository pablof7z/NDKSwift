import SwiftUI
import NDKSwift

struct NewMessageView: View {
    @ObservedObject var dmManager: DirectMessagesManager
    @Environment(NostrManager.self) private var nostrManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var searchText = ""
    @State private var selectedUser: UserSearchResult?
    @State private var searchResults: [UserSearchResult] = []
    @State private var isSearching = false
    @State private var recentContacts: [UserSearchResult] = []
    
    var body: some View {
        NavigationStack {
            ZStack {
                OlasDesign.Colors.background
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Search bar
                    searchBar
                    
                    Divider()
                    
                    if isSearching {
                        loadingView
                    } else if !searchText.isEmpty && searchResults.isEmpty {
                        noResultsView
                    } else if searchText.isEmpty {
                        recentContactsView
                    } else {
                        searchResultsView
                    }
                }
            }
            .navigationTitle("New Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(OlasDesign.Colors.textSecondary)
                }
            }
            .task {
                await loadRecentContacts()
            }
            .onChange(of: searchText) { _, newValue in
                Task {
                    await searchUsers(newValue)
                }
            }
            .navigationDestination(item: $selectedUser) { user in
                // Create or navigate to conversation
                if let conversation = findExistingConversation(with: user.pubkey) {
                    ConversationView(
                        conversation: conversation,
                        dmManager: dmManager
                    )
                    .environment(nostrManager)
                } else {
                    // Create new conversation view
                    NewConversationView(
                        recipient: user,
                        dmManager: dmManager
                    )
                    .environment(nostrManager)
                }
            }
        }
    }
    
    private var searchBar: some View {
        HStack(spacing: OlasDesign.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(OlasDesign.Colors.textSecondary)
            
            TextField("Search by name or npub", text: $searchText)
                .textFieldStyle(PlainTextFieldStyle())
                .font(OlasDesign.Typography.body)
                .foregroundColor(OlasDesign.Colors.text)
                .autocapitalization(.none)
                .disableAutocorrection(true)
            
            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(OlasDesign.Colors.textSecondary)
                }
            }
        }
        .padding()
        .background(OlasDesign.Colors.surface)
    }
    
    private var recentContactsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OlasDesign.Spacing.md) {
                Text("Recent")
                    .font(OlasDesign.Typography.caption)
                    .foregroundColor(OlasDesign.Colors.textSecondary)
                    .padding(.horizontal)
                    .padding(.top)
                
                LazyVStack(spacing: 0) {
                    ForEach(recentContacts) { contact in
                        UserRow(user: contact) {
                            selectedUser = contact
                        }
                        
                        if contact.id != recentContacts.last?.id {
                            Divider()
                                .padding(.leading, 72)
                        }
                    }
                }
            }
        }
    }
    
    private var searchResultsView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(searchResults) { user in
                    UserRow(user: user) {
                        selectedUser = user
                    }
                    
                    if user.id != searchResults.last?.id {
                        Divider()
                            .padding(.leading, 72)
                    }
                }
            }
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: OlasDesign.Spacing.lg) {
            Spacer()
            
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: OlasDesign.Colors.primary))
                .scaleEffect(1.5)
            
            Text("Searching...")
                .font(OlasDesign.Typography.body)
                .foregroundColor(OlasDesign.Colors.textSecondary)
            
            Spacer()
        }
    }
    
    private var noResultsView: some View {
        VStack(spacing: OlasDesign.Spacing.lg) {
            Spacer()
            
            Image(systemName: "magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(OlasDesign.Colors.textTertiary)
            
            Text("No users found")
                .font(OlasDesign.Typography.body)
                .foregroundColor(OlasDesign.Colors.textSecondary)
            
            Spacer()
        }
    }
    
    private func loadRecentContacts() async {
        // Load recent contacts from existing conversations
        var contacts: [UserSearchResult] = []
        
        for conversation in dmManager.conversations.prefix(10) {
            let contact = UserSearchResult(
                pubkey: conversation.otherParticipantPubkey,
                profile: conversation.otherParticipantProfile
            )
            contacts.append(contact)
        }
        
        recentContacts = contacts
    }
    
    private func searchUsers(_ query: String) async {
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        
        isSearching = true
        
        // If it's an npub, decode it
        if query.hasPrefix("npub") {
            // TODO: Decode npub to hex pubkey
            isSearching = false
            return
        }
        
        // Search by name using NDK
        guard let ndk = nostrManager.ndk else {
            isSearching = false
            return
        }
        
        // Create filter for user metadata
        let filter = NDKFilter(
            kinds: [0], // User metadata
            limit: 20
        )
        
        let dataSource = ndk.dataSource(filter: filter)
        var results: [UserSearchResult] = []
        
        for await event in dataSource.events {
            guard let profileData = event.content.data(using: .utf8),
                  let profile = try? JSONDecoder().decode(NDKUserProfile.self, from: profileData) else {
                continue
            }
            
            // Check if name matches search
            let searchLower = query.lowercased()
            if let name = profile.name?.lowercased(), name.contains(searchLower) ||
               profile.displayName?.lowercased().contains(searchLower) == true {
                
                let result = UserSearchResult(
                    pubkey: event.pubkey,
                    profile: profile
                )
                results.append(result)
                
                if results.count >= 10 {
                    break
                }
            }
        }
        
        searchResults = results
        isSearching = false
    }
    
    private func findExistingConversation(with pubkey: String) -> DMConversation? {
        dmManager.conversations.first { $0.otherParticipantPubkey == pubkey }
    }
}

struct UserRow: View {
    let user: UserSearchResult
    let onTap: () -> Void
    
    var body: some View {
        Button(action: {
            OlasDesign.Haptic.selection()
            onTap()
        }) {
            HStack(spacing: OlasDesign.Spacing.md) {
                OlasAvatar(
                    url: user.profile?.picture,
                    size: 48,
                    pubkey: user.pubkey
                )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(user.displayName)
                        .font(OlasDesign.Typography.bodyMedium)
                        .foregroundColor(OlasDesign.Colors.text)
                        .lineLimit(1)
                    
                    if let name = user.profile?.name {
                        Text("@\(name)")
                            .font(OlasDesign.Typography.caption)
                            .foregroundColor(OlasDesign.Colors.textSecondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(OlasDesign.Colors.textTertiary)
            }
            .padding(.horizontal)
            .padding(.vertical, OlasDesign.Spacing.sm)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct UserSearchResult: Identifiable {
    let id = UUID()
    let pubkey: String
    let profile: NDKUserProfile?
    
    var displayName: String {
        profile?.displayName ?? profile?.name ?? String(pubkey.prefix(8)) + "..."
    }
}

struct NewConversationView: View {
    let recipient: UserSearchResult
    @ObservedObject var dmManager: DirectMessagesManager
    @Environment(NostrManager.self) private var nostrManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var messageText = ""
    @FocusState private var isMessageFieldFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Empty conversation placeholder
            Spacer()
            
            VStack(spacing: OlasDesign.Spacing.md) {
                OlasAvatar(
                    url: recipient.profile?.picture,
                    size: 80,
                    pubkey: recipient.pubkey
                )
                
                Text(recipient.displayName)
                    .font(OlasDesign.Typography.title2)
                    .foregroundColor(OlasDesign.Colors.text)
                
                Text("Start a conversation")
                    .font(OlasDesign.Typography.body)
                    .foregroundColor(OlasDesign.Colors.textSecondary)
            }
            
            Spacer()
            
            // Message input
            HStack(spacing: OlasDesign.Spacing.sm) {
                TextField("Say hi 👋", text: $messageText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(OlasDesign.Typography.body)
                    .foregroundColor(OlasDesign.Colors.text)
                    .focused($isMessageFieldFocused)
                    .padding(.horizontal, OlasDesign.Spacing.md)
                    .padding(.vertical, OlasDesign.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(OlasDesign.Colors.surface)
                    )
                
                if !messageText.isEmpty {
                    Button(action: sendFirstMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundColor(OlasDesign.Colors.primary)
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding()
        }
        .navigationTitle(recipient.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            isMessageFieldFocused = true
        }
    }
    
    private func sendFirstMessage() {
        let trimmedMessage = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else { return }
        
        OlasDesign.Haptic.selection()
        
        Task {
            do {
                try await dmManager.sendMessage(
                    to: recipient.pubkey,
                    content: trimmedMessage
                )
                
                // Navigate back to main messages view
                dismiss()
            } catch {
                print("Failed to send message: \(error)")
                OlasDesign.Haptic.error()
            }
        }
    }
}