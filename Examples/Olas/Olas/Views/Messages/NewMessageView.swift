import SwiftUI
import NDKSwift

struct NewMessageView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(NostrManager.self) private var nostrManager
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = NewMessageViewModel()
    @State private var searchText = ""
    @State private var selectedUsers: Set<String> = []
    @FocusState private var isSearchFocused: Bool
    
    var body: some View {
        NavigationStack {
            ZStack {
                OlasDesign.Colors.background
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Selected users chips
                    if !selectedUsers.isEmpty {
                        selectedUsersView
                            .padding(.horizontal, OlasDesign.Spacing.md)
                            .padding(.vertical, OlasDesign.Spacing.sm)
                    }
                    
                    // Search bar
                    searchBar
                        .padding(.horizontal, OlasDesign.Spacing.md)
                        .padding(.vertical, OlasDesign.Spacing.sm)
                    
                    // Search results / Suggested users
                    ScrollView {
                        VStack(alignment: .leading, spacing: OlasDesign.Spacing.md) {
                            if !searchText.isEmpty && viewModel.searchResults.isEmpty && viewModel.isSearching {
                                // Loading
                                ForEach(0..<5) { _ in
                                    UserRowSkeletonView()
                                }
                                .padding(.horizontal, OlasDesign.Spacing.md)
                            } else if !searchText.isEmpty && viewModel.searchResults.isEmpty {
                                // No results
                                noResultsView
                            } else if !viewModel.searchResults.isEmpty {
                                // Search results
                                ForEach(viewModel.searchResults) { user in
                                    UserRowView(
                                        user: user,
                                        isSelected: selectedUsers.contains(user.pubkey)
                                    ) {
                                        toggleUserSelection(user.pubkey)
                                    }
                                }
                                .padding(.horizontal, OlasDesign.Spacing.md)
                            } else {
                                // Suggested users
                                if !viewModel.suggestedUsers.isEmpty {
                                    Text("Suggested")
                                        .font(OlasDesign.Typography.caption)
                                        .foregroundColor(OlasDesign.Colors.textSecondary)
                                        .padding(.horizontal, OlasDesign.Spacing.md)
                                    
                                    ForEach(viewModel.suggestedUsers) { user in
                                        UserRowView(
                                            user: user,
                                            isSelected: selectedUsers.contains(user.pubkey)
                                        ) {
                                            toggleUserSelection(user.pubkey)
                                        }
                                    }
                                    .padding(.horizontal, OlasDesign.Spacing.md)
                                }
                                
                                // Recent conversations
                                if !viewModel.recentUsers.isEmpty {
                                    Text("Recent")
                                        .font(OlasDesign.Typography.caption)
                                        .foregroundColor(OlasDesign.Colors.textSecondary)
                                        .padding(.horizontal, OlasDesign.Spacing.md)
                                        .padding(.top, OlasDesign.Spacing.lg)
                                    
                                    ForEach(viewModel.recentUsers) { user in
                                        UserRowView(
                                            user: user,
                                            isSelected: selectedUsers.contains(user.pubkey)
                                        ) {
                                            toggleUserSelection(user.pubkey)
                                        }
                                    }
                                    .padding(.horizontal, OlasDesign.Spacing.md)
                                }
                            }
                        }
                        .padding(.vertical, OlasDesign.Spacing.sm)
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
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Chat") {
                        startConversations()
                    }
                    .font(OlasDesign.Typography.bodyBold)
                    .disabled(selectedUsers.isEmpty)
                }
            }
            .onAppear {
                isSearchFocused = true
                if let ndk = nostrManager.ndk {
                    Task {
                        await viewModel.loadInitialData(ndk: ndk)
                    }
                }
            }
            .onChange(of: searchText) { _, newValue in
                Task {
                    await viewModel.searchUsers(query: newValue)
                }
            }
        }
    }
    
    private var selectedUsersView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: OlasDesign.Spacing.sm) {
                ForEach(Array(selectedUsers), id: \.self) { pubkey in
                    if let user = viewModel.getUserInfo(for: pubkey) {
                        UserChipView(user: user) {
                            toggleUserSelection(pubkey)
                        }
                    }
                }
            }
        }
    }
    
    private var searchBar: some View {
        HStack(spacing: OlasDesign.Spacing.sm) {
            Text("To:")
                .font(OlasDesign.Typography.body)
                .foregroundColor(OlasDesign.Colors.textSecondary)
            
            TextField("Search", text: $searchText)
                .textFieldStyle(PlainTextFieldStyle())
                .font(OlasDesign.Typography.body)
                .foregroundColor(OlasDesign.Colors.text)
                .focused($isSearchFocused)
                .autocapitalization(.none)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, OlasDesign.Spacing.md)
        .padding(.vertical, OlasDesign.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.md)
                .fill(OlasDesign.Colors.surface)
        )
    }
    
    private var noResultsView: some View {
        VStack(spacing: OlasDesign.Spacing.md) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(OlasDesign.Colors.textTertiary)
            
            Text("No users found")
                .font(OlasDesign.Typography.body)
                .foregroundColor(OlasDesign.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, OlasDesign.Spacing.xxl)
    }
    
    private func toggleUserSelection(_ pubkey: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            if selectedUsers.contains(pubkey) {
                selectedUsers.remove(pubkey)
            } else {
                selectedUsers.insert(pubkey)
            }
        }
        OlasDesign.Haptic.selection()
    }
    
    private func startConversations() {
        // TODO: Navigate to conversation view with selected users
        // For now, just dismiss
        dismiss()
    }
}

// MARK: - User Row View
struct UserRowView: View {
    let user: UserSearchResult
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: OlasDesign.Spacing.md) {
                OlasAvatar(
                    url: user.profile?.picture,
                    size: 50,
                    pubkey: user.pubkey
                )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(user.profile?.displayName ?? user.profile?.name ?? "User")
                        .font(OlasDesign.Typography.bodyMedium)
                        .foregroundColor(OlasDesign.Colors.text)
                        .lineLimit(1)
                    
                    Text("@\(user.profile?.name ?? String(user.pubkey.prefix(16)))")
                        .font(OlasDesign.Typography.caption)
                        .foregroundColor(OlasDesign.Colors.textSecondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(
                        isSelected ?
                        LinearGradient(
                            colors: OlasDesign.Colors.primaryGradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ) :
                        LinearGradient(
                            colors: [OlasDesign.Colors.textTertiary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelected)
            }
            .padding(.vertical, OlasDesign.Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - User Chip View
struct UserChipView: View {
    let user: UserSearchResult
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: OlasDesign.Spacing.xs) {
            OlasAvatar(
                url: user.profile?.picture,
                size: 24,
                pubkey: user.pubkey
            )
            
            Text(user.profile?.name ?? String(user.pubkey.prefix(8)))
                .font(OlasDesign.Typography.caption)
                .foregroundColor(OlasDesign.Colors.text)
                .lineLimit(1)
            
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(OlasDesign.Colors.textSecondary)
            }
        }
        .padding(.horizontal, OlasDesign.Spacing.sm)
        .padding(.vertical, OlasDesign.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.full)
                .fill(OlasDesign.Colors.surface)
        )
    }
}

// MARK: - Skeleton View
struct UserRowSkeletonView: View {
    @State private var shimmerAnimation = false
    
    var body: some View {
        HStack(spacing: OlasDesign.Spacing.md) {
            Circle()
                .fill(OlasDesign.Colors.surface)
                .overlay(shimmerGradient)
                .frame(width: 50, height: 50)
            
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.xs)
                    .fill(OlasDesign.Colors.surface)
                    .overlay(shimmerGradient)
                    .frame(width: 120, height: 16)
                
                RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.xs)
                    .fill(OlasDesign.Colors.surface)
                    .overlay(shimmerGradient)
                    .frame(width: 80, height: 14)
            }
            
            Spacer()
        }
        .padding(.vertical, OlasDesign.Spacing.sm)
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
class NewMessageViewModel: ObservableObject {
    @Published var searchResults: [UserSearchResult] = []
    @Published var suggestedUsers: [UserSearchResult] = []
    @Published var recentUsers: [UserSearchResult] = []
    @Published var isSearching = false
    
    private var ndk: NDK?
    private var searchTask: Task<Void, Never>?
    private var allUsers: [String: UserSearchResult] = [:]
    
    func loadInitialData(ndk: NDK) async {
        self.ndk = ndk
        
        // Load suggested users (could be based on follows of follows)
        await loadSuggestedUsers()
        
        // Load recent conversation partners
        await loadRecentUsers()
    }
    
    func searchUsers(query: String) async {
        searchTask?.cancel()
        
        guard !query.isEmpty else {
            await MainActor.run {
                searchResults = []
                isSearching = false
            }
            return
        }
        
        await MainActor.run {
            isSearching = true
        }
        
        searchTask = Task {
            // Simulate search delay
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
            
            guard !Task.isCancelled else { return }
            
            // Search by name or pubkey
            let results = await performSearch(query: query)
            
            await MainActor.run {
                self.searchResults = results
                self.isSearching = false
            }
        }
    }
    
    private func performSearch(query: String) async -> [UserSearchResult] {
        guard let ndk = ndk else { return [] }
        
        // Search in metadata events
        let filter = NDKFilter(
            kinds: [0], // Metadata
            limit: 50
        )
        
        do {
            let events = try await ndk.fetchEvents(filter: filter)
            
            var results: [UserSearchResult] = []
            
            for event in events {
                guard let metadata = try? JSONDecoder().decode(NDKUserProfile.self, from: Data(event.content.utf8)) else { continue }
                
                // Check if name or display name matches query
                let nameMatch = metadata.name?.localizedCaseInsensitiveContains(query) ?? false
                let displayNameMatch = metadata.displayName?.localizedCaseInsensitiveContains(query) ?? false
                let pubkeyMatch = event.pubkey.lowercased().starts(with: query.lowercased())
                
                if nameMatch || displayNameMatch || pubkeyMatch {
                    let user = UserSearchResult(
                        pubkey: event.pubkey,
                        profile: metadata
                    )
                    results.append(user)
                    allUsers[event.pubkey] = user
                }
            }
            
            return Array(results.prefix(20))
        } catch {
            print("Search failed: \(error)")
            return []
        }
    }
    
    private func loadSuggestedUsers() async {
        // TODO: Load follows of follows or other suggestions
        // For now, just load some random users
        guard let ndk = ndk else { return }
        
        let filter = NDKFilter(
            kinds: [0],
            limit: 10
        )
        
        do {
            let events = try await ndk.fetchEvents(filter: filter)
            
            let users = events.compactMap { event -> UserSearchResult? in
                guard let metadata = try? JSONDecoder().decode(NDKUserProfile.self, from: Data(event.content.utf8)) else { return nil }
                
                let user = UserSearchResult(
                    pubkey: event.pubkey,
                    profile: metadata
                )
                allUsers[event.pubkey] = user
                return user
            }
            
            await MainActor.run {
                self.suggestedUsers = Array(users.prefix(5))
            }
        } catch {
            print("Failed to load suggested users: \(error)")
        }
    }
    
    private func loadRecentUsers() async {
        // TODO: Load from recent DM conversations
        // For now, empty
        await MainActor.run {
            self.recentUsers = []
        }
    }
    
    func getUserInfo(for pubkey: String) -> UserSearchResult? {
        return allUsers[pubkey]
    }
}

// MARK: - Models
struct UserSearchResult: Identifiable {
    let id = UUID()
    let pubkey: String
    let profile: NDKUserProfile?
}