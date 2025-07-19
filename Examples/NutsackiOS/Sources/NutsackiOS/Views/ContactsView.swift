import SwiftUI
import NDKSwift

struct ContactsView: View {
    @Environment(NostrManager.self) private var nostrManager
    @Environment(WalletManager.self) private var walletManager
    @Binding var navigationDestination: WalletView.WalletDestination?
    @State private var contacts: [NDKUser] = []
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var showSettings = false
    @State private var resolvedUser: NDKUser?
    @State private var isResolving = false
    @State private var showQRScanner = false
    
    var filteredContacts: [NDKUser] {
        if searchText.isEmpty {
            return contacts
        }
        return contacts.filter { user in
            // Since profile is async, we'll filter by npub only for now
            let npub = (try? Bech32.npub(from: user.pubkey)) ?? user.pubkey
            return npub.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search input section
                VStack(spacing: 12) {
                    HStack {
                        TextField("npub, NIP-05, or hex pubkey", text: $searchText)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                            .autocorrectionDisabled()
                        
                        #if os(iOS)
                        Button(action: { showQRScanner = true }) {
                            Image(systemName: "qrcode.viewfinder")
                                .font(.title2)
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .background(Color.orange)
                                .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                        #endif
                    }
                    .padding(.horizontal)
                    
                    if isResolving {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Resolving...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)
                    } else if let user = resolvedUser {
                        Button(action: {
                            navigationDestination = .nutzap(pubkey: user.pubkey)
                        }) {
                            HStack {
                                // Profile picture
                                UserProfilePicture(user: user)
                                
                                VStack(alignment: .leading) {
                                    UserDisplayName(user: user)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    
                                    UserNIP05(user: user)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "bolt.heart.fill")
                                    .foregroundStyle(.orange)
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 8)
                .background(Color(.systemGroupedBackground))
                
                // Contacts list
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
                            ContactRow(user: user, navigationDestination: $navigationDestination)
                        }
                    }
                }
            }
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
            .onChange(of: searchText) { _, _ in
                resolveSearchInput()
            }
            #if os(iOS)
            .sheet(isPresented: $showQRScanner) {
                QRScannerView { scannedCode in
                    searchText = scannedCode
                    showQRScanner = false
                }
            }
            #endif
        }
    }
    
    private func resolveSearchInput() {
        // Clear previous resolution if search text is empty or too short
        guard !searchText.isEmpty else {
            resolvedUser = nil
            return
        }
        
        // Only resolve if it looks like a pubkey, npub, or NIP-05
        guard searchText.starts(with: "npub1") || 
              searchText.count == 64 || 
              searchText.contains("@") else {
            resolvedUser = nil
            return
        }
        
        isResolving = true
        
        Task {
            do {
                guard let ndk = nostrManager.ndk else {
                    throw NostrError.ndkNotInitialized
                }
                
                var pubkey: String?
                
                // Try to parse as npub
                if searchText.starts(with: "npub1") {
                    pubkey = try? Bech32.pubkey(from: searchText)
                }
                // Try as hex pubkey
                else if searchText.count == 64 {
                    pubkey = searchText
                }
                // Try as NIP-05
                else if searchText.contains("@") {
                    let user = try await NDKUser.fromNip05(searchText, ndk: ndk)
                    pubkey = user.pubkey
                }
                
                if let pubkey = pubkey {
                    let user = NDKUser(pubkey: pubkey)
                    
                    await MainActor.run {
                        resolvedUser = user
                        isResolving = false
                    }
                } else {
                    await MainActor.run {
                        resolvedUser = nil
                        isResolving = false
                    }
                }
            } catch {
                await MainActor.run {
                    resolvedUser = nil
                    isResolving = false
                }
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
    @Binding var navigationDestination: WalletView.WalletDestination?
    @State private var profile: NDKUserProfile?
    @State private var profileTask: Task<Void, Never>?
    @Environment(NostrManager.self) private var nostrManager
    @Environment(\.dismiss) private var dismiss
    
    var displayName: String {
        profile?.displayName ?? profile?.name ?? "Nostr User"
    }
    
    var npub: String {
        (try? Bech32.npub(from: user.pubkey)) ?? user.pubkey
    }
    
    var body: some View {
        Button(action: {
            navigationDestination = .nutzap(pubkey: user.pubkey)
            dismiss()
        }) {
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
                
                Image(systemName: "bolt.heart.fill")
                    .foregroundStyle(.orange)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
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