import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var nostrManager: NostrManager
    @EnvironmentObject private var walletManager: WalletManager
    
    @Query private var accounts: [NostrAccount]
    
    var activeAccount: NostrAccount? {
        accounts.first { $0.accountID.uuidString == appState.activeAccountID }
    }
    
    var body: some View {
        NavigationStack {
            List {
                // Account section
                Section {
                    if let account = activeAccount {
                        NavigationLink(destination: AccountDetailView(account: account)) {
                            HStack {
                                // Profile picture placeholder
                                Circle()
                                    .fill(Color.secondary.opacity(0.3))
                                    .overlay(
                                        Text(account.displayName.prefix(1).uppercased())
                                            .font(.headline)
                                            .foregroundColor(.white)
                                    )
                                    .frame(width: 50, height: 50)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(account.displayName)
                                        .font(.headline)
                                    
                                    if let npub = NostrIdentifier.npub(fromHex: account.publicKey) {
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
                    
                    NavigationLink(destination: RelaySettingsView()) {
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
        }
    }
    
    private func logout() {
        // Clear active account
        appState.activeAccountID = nil
        nostrManager.logout()
    }
}

// MARK: - Account Detail View
struct AccountDetailView: View {
    let account: NostrAccount
    @State private var showPrivateKey = false
    @State private var copiedKey = false
    
    var npub: String {
        NostrIdentifier.npub(fromHex: account.publicKey) ?? account.publicKey
    }
    
    var nsec: String? {
        guard let privateKey = account.privateKey else { return nil }
        return NostrIdentifier.nsec(fromHex: privateKey)
    }
    
    var body: some View {
        List {
            Section {
                LabeledContent("Display Name", value: account.displayName)
                
                if let about = account.about {
                    LabeledContent("About") {
                        Text(about)
                            .font(.caption)
                    }
                }
                
                if let nip05 = account.nip05 {
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
                
                if let nsec = nsec {
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
                            Text(nsec)
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
    }
    
    private func togglePrivateKey() {
        withAnimation {
            showPrivateKey.toggle()
        }
    }
    
    private func copyPrivateKey() {
        guard let nsec = nsec else { return }
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

// MARK: - Relay Settings View
struct RelaySettingsView: View {
    @EnvironmentObject private var nostrManager: NostrManager
    
    var body: some View {
        List {
            Section {
                ForEach(nostrManager.defaultRelays, id: \.self) { relay in
                    HStack {
                        Text(relay)
                            .font(.caption)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        Image(systemName: "circle.fill")
                            .font(.caption2)
                            .foregroundStyle(nostrManager.relayStatus[relay] == true ? .green : .red)
                    }
                }
            } header: {
                Text("Connected Relays")
            } footer: {
                Text("These are the default relays. Custom relay management coming soon.")
            }
        }
        .navigationTitle("Relays")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
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