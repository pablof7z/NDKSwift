import SwiftUI
import SwiftData
import NDKSwift

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var nostrManager: NostrManager
    @EnvironmentObject private var walletManager: WalletManager
    
    @State private var userProfile: NDKUserProfile?
    
    var body: some View {
        NavigationStack {
            List {
                // Account section
                Section {
                    if let currentUser = nostrManager.currentUser {
                        NavigationLink(destination: AccountDetailView(user: currentUser, profile: userProfile)) {
                            HStack {
                                // Profile picture placeholder
                                Circle()
                                    .fill(Color.secondary.opacity(0.3))
                                    .overlay(
                                        Text((userProfile?.displayName ?? userProfile?.name ?? "User").prefix(1).uppercased())
                                            .font(.headline)
                                            .foregroundColor(.white)
                                    )
                                    .frame(width: 50, height: 50)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(userProfile?.displayName ?? userProfile?.name ?? "Nostr User")
                                        .font(.headline)
                                    
                                    if let npub = currentUser.npub {
                                        Text(String(npub.prefix(16)) + "...")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    } else {
                        Text("No user logged in")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Account")
                }
                
                // Preferences
                Section {
                    Picker("Currency", selection: $appState.preferredConversionUnit) {
                        ForEach(CurrencyUnit.allCases, id: \.self) { unit in
                            Text(unit.symbol).tag(unit)
                        }
                    }
                    
                    NavigationLink(destination: RelayManagementView()) {
                        Label("Relays", systemImage: "network")
                    }
                    
                    NavigationLink(destination: BackupView()) {
                        Label("Backup", systemImage: "lock.shield")
                    }
                } header: {
                    Text("Preferences")
                }
                
                // Nutzap Settings
                Section {
                    NavigationLink(destination: NutzapSettingsView()) {
                        Label("Nutzap Settings", systemImage: "bolt.heart")
                    }
                } header: {
                    Text("Wallet")
                } footer: {
                    Text("Configure how others can send nutzaps to your wallet")
                }
                
                
                // App Info
                Section {
                    LabeledContent("Version", value: "1.0.0")
                    
                    Link(destination: URL(string: "https://github.com/yourusername/nutsack")!) {
                        Label("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    
                    NavigationLink(destination: AboutView()) {
                        Label("About", systemImage: "info.circle")
                    }
                } header: {
                    Text("App")
                }
                
                // Danger zone
                Section {
                    Button(role: .destructive, action: logout) {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .onAppear {
                loadUserProfile()
            }
            .onChange(of: nostrManager.currentUser) { _, _ in
                loadUserProfile()
            }
        }
    }
    
    private func loadUserProfile() {
        guard let currentUser = nostrManager.currentUser else {
            userProfile = nil
            return
        }
        
        Task {
            do {
                let profile = try await currentUser.profile
                await MainActor.run {
                    userProfile = profile
                }
            } catch {
                print("Failed to load user profile: \(error)")
            }
        }
    }
    
    private func logout() {
        nostrManager.logout()
        userProfile = nil
    }
}

// MARK: - Account Detail View
struct AccountDetailView: View {
    let user: NDKUser
    let profile: NDKUserProfile?
    @EnvironmentObject private var nostrManager: NostrManager
    @State private var showPrivateKey = false
    @State private var copiedKey = false
    @State private var nsecKey: String?
    
    var npub: String {
        user.npub ?? user.pubkey
    }
    
    var body: some View {
        List {
            Section {
                LabeledContent("Display Name", value: profile?.displayName ?? profile?.name ?? "Nostr User")
                
                if let about = profile?.about {
                    LabeledContent("About") {
                        Text(about)
                            .font(.caption)
                    }
                }
                
                if let nip05 = profile?.nip05 {
                    LabeledContent("NIP-05", value: nip05)
                }
            } header: {
                Text("Profile")
            }
            
            Section {
                LabeledContent("Public Key (npub)") {
                    Text(npub)
                        .font(.caption)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
                
                if let nsecKey = nsecKey {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Private Key (nsec)")
                            Spacer()
                            Button(action: togglePrivateKey) {
                                Image(systemName: showPrivateKey ? "eye.slash" : "eye")
                            }
                            .buttonStyle(.plain)
                        }
                        
                        if showPrivateKey {
                            Text(nsecKey)
                                .font(.caption)
                                .textSelection(.enabled)
                            
                            Button(action: copyPrivateKey) {
                                Label(
                                    copiedKey ? "Copied!" : "Copy Private Key",
                                    systemImage: copiedKey ? "checkmark.circle.fill" : "doc.on.doc"
                                )
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(copiedKey ? .green : .orange)
                        }
                    }
                } else {
                    Text("Private key access through secure authentication")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Keys")
            } footer: {
                Text("Keep your private key secure. Anyone with this key can access your account.")
                    .foregroundStyle(.red)
            }
        }
        .navigationTitle("Account")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            loadPrivateKey()
        }
    }
    
    private func loadPrivateKey() {
        guard let signer = nostrManager.authManager.activeSigner as? NDKPrivateKeySigner else {
            nsecKey = nil
            return
        }
        
        Task {
            do {
                let nsec = try signer.nsec
                await MainActor.run {
                    nsecKey = nsec
                }
            } catch {
                print("Failed to load private key: \(error)")
                await MainActor.run {
                    nsecKey = nil
                }
            }
        }
    }
    
    private func togglePrivateKey() {
        withAnimation {
            showPrivateKey.toggle()
        }
    }
    
    private func copyPrivateKey() {
        guard let nsec = nsecKey else { return }
        #if os(iOS)
        UIPasteboard.general.string = nsec
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(nsec, forType: .string)
        #endif
        withAnimation {
            copiedKey = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                copiedKey = false
            }
        }
    }
}


// MARK: - Backup View
struct BackupView: View {
    var body: some View {
        List {
            Section {
                Text("Backup features coming soon")
                    .foregroundStyle(.secondary)
            } header: {
                Text("Wallet Backup")
            } footer: {
                Text("Your wallets are automatically backed up to Nostr using NIP-60")
            }
        }
        .navigationTitle("Backup")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - About View
struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                // Logo
                Image(systemName: "banknote.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.orange.gradient)
                    .padding(.top, 40)
                
                Text("Nutsack")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Lightning-fast payments with Nostr")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                // Description
                VStack(alignment: .leading, spacing: 16) {
                    Text("About")
                        .font(.headline)
                    
                    Text("""
                    Nutsack is a Cashu ecash wallet that integrates seamlessly with Nostr. It implements NIP-60 for wallet backup and NIP-61 for nutzaps.
                    
                    Built with NDKSwift, this wallet showcases the power of combining ecash with the Nostr protocol for a truly decentralized payment experience.
                    """)
                    .font(.body)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                
                Spacer(minLength: 40)
            }
        }
        .navigationTitle("About")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}