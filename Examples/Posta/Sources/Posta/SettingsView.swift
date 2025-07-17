import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var themeManager: ThemeManager
    
    @State private var showingAbout = false
    @State private var showingProfile = false
    
    private var relayManager: RelayManager {
        authManager.getRelayManager()
    }
    
    private var accountManager: AccountManager {
        authManager.getAccountManager()
    }
    
    var body: some View {
        NavigationStack {
            List {
                // Account Section
                Section {
                    // Profile Button
                    Button(action: { showingProfile = true }) {
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .font(.title)
                                .foregroundColor(.accentColor)
                            VStack(alignment: .leading) {
                                Text("My Profile")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                if let user = authManager.currentUser {
                                    Text(String(user.pubkey.prefix(8)) + "...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    
                    NavigationLink(destination: AccountSettingsView(accountManager: accountManager, authManager: authManager)) {
                        HStack {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.title2)
                                .foregroundColor(.blue)
                            VStack(alignment: .leading) {
                                Text("Accounts")
                                    .font(.headline)
                                if let activeAccount = accountManager.activeAccount {
                                    Text(activeAccount.name ?? String(activeAccount.pubkey.prefix(8)) + "...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                // Relay Section
                Section {
                    NavigationLink(destination: RelaySettingsView(relayManager: relayManager, authManager: authManager)) {
                        HStack {
                            Image(systemName: "network")
                                .font(.title2)
                                .foregroundColor(.green)
                            VStack(alignment: .leading) {
                                Text("Relays")
                                    .font(.headline)
                                Text("\(relayManager.relays.filter { $0.isConnected }.count) connected")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                // Appearance Section
                Section {
                    NavigationLink(destination: AppearanceSettingsView(themeManager: themeManager)) {
                        HStack {
                            Image(systemName: "paintbrush.fill")
                                .font(.title2)
                                .foregroundColor(.purple)
                            VStack(alignment: .leading) {
                                Text("Appearance")
                                    .font(.headline)
                                Text(themeManager.currentTheme.rawValue)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                // Privacy & Security Section
                Section {
                    NavigationLink(destination: PrivacySettingsView()) {
                        HStack {
                            Image(systemName: "lock.fill")
                                .font(.title2)
                                .foregroundColor(.orange)
                            Text("Privacy & Security")
                                .font(.headline)
                        }
                        .padding(.vertical, 4)
                    }
                    
                    NavigationLink(destination: NotificationSettingsView()) {
                        HStack {
                            Image(systemName: "bell.fill")
                                .font(.title2)
                                .foregroundColor(.red)
                            Text("Notifications")
                                .font(.headline)
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                // Advanced Section
                Section {
                    NavigationLink(destination: AdvancedSettingsView()) {
                        HStack {
                            Image(systemName: "gearshape.2.fill")
                                .font(.title2)
                                .foregroundColor(.gray)
                            Text("Advanced")
                                .font(.headline)
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                // About Section
                Section {
                    Button(action: { showingAbout = true }) {
                        HStack {
                            Image(systemName: "info.circle.fill")
                                .font(.title2)
                                .foregroundColor(.blue)
                            VStack(alignment: .leading) {
                                Text("About Posta")
                                    .font(.headline)
                                Text("Version 1.0.0")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .foregroundColor(.primary)
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingAbout) {
                AboutView()
            }
            .sheet(isPresented: $showingProfile) {
                if let user = authManager.currentUser {
                    ProfileView(pubkey: user.pubkey)
                        .environmentObject(authManager)
                }
            }
        }
        .preferredColorScheme(themeManager.currentTheme.colorScheme)
        .onAppear {
            if let ndk = authManager.getNDK() {
                relayManager.setNDK(ndk)
            }
        }
    }
}