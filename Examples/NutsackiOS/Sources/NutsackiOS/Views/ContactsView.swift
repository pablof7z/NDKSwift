import SwiftUI
import NDKSwift

struct ContactsView: View {
    @Environment(NostrManager.self) private var nostrManager
    @Environment(WalletManager.self) private var walletManager
    @State private var contacts: [NDKUser] = []
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var showSettings = false
    
    var filteredContacts: [NDKUser] {
        if searchText.isEmpty {
            return contacts
        }
        return contacts.filter { user in
            // Since profile is async, we'll filter by npub only for now
            let npub = NostrIdentifier.npub(fromHex: user.pubkey) ?? user.pubkey
            return npub.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding()
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                } else if contacts.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "person.2.slash")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        
                        Text("No contacts yet")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        
                        Text("Follow people on Nostr to see them here")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(filteredContacts, id: \.self) { user in
                        ContactRow(user: user)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search contacts")
            .navigationTitle("Contacts")
            .platformNavigationBarTitleDisplayMode(inline: true)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "person.circle.fill")
                            .font(.title3)
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environment(nostrManager)
                    .environment(walletManager)
            }
            .refreshable {
                await loadContacts()
            }
            .task {
                await loadContacts()
            }
        }
    }
    
    private func loadContacts() async {
        isLoading = true
        
        guard let currentUser = await nostrManager.currentUser,
              let ndk = nostrManager.ndk else {
            await MainActor.run {
                isLoading = false
            }
            return
        }
        
        do {
            // Fetch contact list
            let filter = NDKFilter(
                authors: [currentUser.pubkey],
                kinds: [3],  // Contact list
                limit: 1
            )
            
            if let contactListEvent = try await ndk.fetchEvent(filter) {
                // Extract pubkeys from tags
                let pTags = contactListEvent.tags.filter { $0.first == "p" }
                let pubkeys = pTags.compactMap { $0.count > 1 ? $0[1] : nil }
                
                // Create NDKUser objects for contacts
                let users = pubkeys.map { NDKUser(pubkey: $0) }
                
                // For now, just show contacts in the order they appear
                // Individual ContactRow views will handle loading profiles reactively
                await MainActor.run {
                    self.contacts = users
                    isLoading = false
                }
            } else {
                await MainActor.run {
                    isLoading = false
                }
            }
        } catch {
            print("Failed to load contacts: \(error)")
            await MainActor.run {
                isLoading = false
            }
        }
    }
}

struct ContactRow: View {
    let user: NDKUser
    @State private var showNutzapView = false
    @State private var profile: NDKUserProfile?
    @State private var profileTask: Task<Void, Never>?
    @Environment(NostrManager.self) private var nostrManager
    
    var displayName: String {
        profile?.displayName ?? profile?.name ?? "Nostr User"
    }
    
    var npub: String {
        NostrIdentifier.npub(fromHex: user.pubkey) ?? user.pubkey
    }
    
    var body: some View {
        HStack {
            // Profile picture
            if let pictureURL = profile?.picture,
               let url = URL(string: pictureURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle()
                        .fill(Color.secondary.opacity(0.3))
                        .overlay(
                            Text(displayName.prefix(1).uppercased())
                                .font(.headline)
                                .foregroundColor(.white)
                        )
                }
                .frame(width: 50, height: 50)
                .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.secondary.opacity(0.3))
                    .overlay(
                        Text(displayName.prefix(1).uppercased())
                            .font(.headline)
                            .foregroundColor(.white)
                    )
                    .frame(width: 50, height: 50)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.headline)
                    .lineLimit(1)
                
                Text(npub)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Button(action: { showNutzapView = true }) {
                Image(systemName: "bolt.heart.fill")
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showNutzapView) {
            // TODO: Implement quick nutzap view
            Text("Nutzap to \(displayName)")
                .presentationDetents([.medium])
        }
        .task {
            guard let ndk = nostrManager.ndk else { return }
            
            profileTask = Task {
                let profileStream = await ndk.observeProfile(for: user.pubkey, closeOnEose: true)
                
                for await profileUpdate in profileStream {
                    if let profile = profileUpdate {
                        await MainActor.run {
                            self.profile = profile
                        }
                        break // We only need the first profile for display
                    }
                }
            }
        }
        .onDisappear {
            profileTask?.cancel()
        }
    }
}