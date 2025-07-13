import SwiftUI
import NDKSwift

struct ContactsView: View {
    @EnvironmentObject private var nostrManager: NostrManager
    @State private var contacts: [NDKUser] = []
    @State private var searchText = ""
    @State private var isLoading = true
    
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
        
        guard let currentUser = nostrManager.currentUser,
              let ndk = nostrManager.ndk else {
            isLoading = false
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
                
                // Fetch profiles for contacts
                var users: [NDKUser] = []
                for pubkey in pubkeys {
                    let user = NDKUser(pubkey: pubkey)
                    // Try to fetch profile
                    do {
                        let metadataFilter = NDKFilter(
                            authors: [pubkey],
                            kinds: [0],
                            limit: 1
                        )
                        if let event = try await ndk.fetchEvent(metadataFilter),
                           let contentData = event.content.data(using: .utf8),
                           let _ = try? JSONDecoder().decode(NDKUserProfile.self, from: contentData) {
                            // Profile metadata will be available via async property
                        }
                    } catch {
                        logger.error("Failed to fetch profile for \(pubkey): \(error)")
                    }
                    users.append(user)
                }
                
                // Sort users by name
                var sortedUsers: [(user: NDKUser, name: String)] = []
                for user in users {
                    let profile = await user.profile
                    let name = profile?.displayName ?? profile?.name ?? ""
                    sortedUsers.append((user: user, name: name))
                }
                
                sortedUsers.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                
                await MainActor.run {
                    self.contacts = sortedUsers.map { $0.user }
                    isLoading = false
                }
            } else {
                await MainActor.run {
                    isLoading = false
                }
            }
        } catch {
            logger.error("Failed to load contacts: \(error)")
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
            profile = await user.profile
        }
    }
}