import SwiftUI
import NDKSwift

struct ContactsView: View {
    @Environment(NostrManager.self) private var nostrManager
    @Environment(WalletManager.self) private var walletManager
    @Binding var navigationDestination: WalletView.WalletDestination?
    @State private var searchText = ""
    @State private var showSettings = false
    @State private var resolvedUser: NDKUser?
    @State private var isResolving = false
    @State private var showQRScanner = false
    
    // Get contacts from NostrManager's data source
    private var contacts: [String] {
        guard let contactListDataSource = nostrManager.contactListDataSource else {
            return []
        }
        return Array(contactListDataSource.contactPubkeys)
    }
    
    private var isLoading: Bool {
        nostrManager.contactListDataSource?.isLoading ?? true
    }
    
    var filteredContacts: [String] {
        if searchText.isEmpty {
            return contacts
        }
        
        return contacts.filter { pubkey in
            // Filter by pubkey/npub
            let npub = NDKUser(pubkey: pubkey).npub ?? pubkey
            if npub.localizedCaseInsensitiveContains(searchText) {
                return true
            }
            
            // Also check profile data if available
            if let profileDataSource = nostrManager.contactsMetadataDataSource,
               let profile = profileDataSource.profile(for: pubkey) {
                if let name = profile.name, name.localizedCaseInsensitiveContains(searchText) {
                    return true
                }
                if let displayName = profile.displayName, displayName.localizedCaseInsensitiveContains(searchText) {
                    return true
                }
                if let nip05 = profile.nip05, nip05.localizedCaseInsensitiveContains(searchText) {
                    return true
                }
            }
            
            return false
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
                        ForEach(filteredContacts, id: \.self) { pubkey in
                            ContactRow(pubkey: pubkey, navigationDestination: $navigationDestination)
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
                // Data sources handle refreshing automatically
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
}

struct ContactRow: View {
    let pubkey: String
    @Binding var navigationDestination: WalletView.WalletDestination?
    @Environment(NostrManager.self) private var nostrManager
    @Environment(\.dismiss) private var dismiss
    
    private var user: NDKUser {
        NDKUser(pubkey: pubkey)
    }
    
    private var profile: NDKUserProfile? {
        nostrManager.contactsMetadataDataSource?.profile(for: pubkey)
    }
    
    private var displayName: String {
        profile?.displayName ?? profile?.name ?? "Nostr User"
    }
    
    private var npub: String {
        user.npub ?? pubkey
    }
    
    var body: some View {
        Button(action: {
            navigationDestination = .nutzap(pubkey: pubkey)
            dismiss()
        }) {
            HStack {
                // Profile picture
                UserProfilePicture(pubkey: pubkey, size: 50)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(displayName)
                        .font(.headline)
                        .lineLimit(1)
                    
                    Text(npub.prefix(16) + "...")
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
    }
}