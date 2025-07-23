import SwiftUI
import NDKSwift

struct SettingsView: View {
    @Environment(NDKAuthManager.self) var authManager
    @Environment(NDKManager.self) var ndkManager
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(RelayManager.self) var relayManager
    
    @State private var showingAbout = false
    @State private var showingProfile = false
    
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
                                if let session = authManager.activeSession {
                                    Text(String(session.pubkey.prefix(8)) + "...")
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
                    
                    NavigationLink(destination: AccountSettingsView()) {
                        HStack {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.title2)
                                .foregroundColor(.blue)
                            VStack(alignment: .leading) {
                                Text("Accounts")
                                    .font(.headline)
                                if authManager.availableSessions.count > 1 {
                                    Text("\(authManager.availableSessions.count) accounts")
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
                    NavigationLink(destination: RelaySettingsView()) {
                        HStack {
                            Image(systemName: "network")
                                .font(.title2)
                                .foregroundColor(.green)
                            VStack(alignment: .leading) {
                                Text("Relays")
                                    .font(.headline)
                                if let ndk = ndkManager.ndk {
                                    RelayCountView(ndk: ndk)
                                } else {
                                    Text("Not connected")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
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
                ProfileView(pubkey: nil)
                    .environment(authManager)
                    .environment(NDKManager.shared)
            }
        }
        .preferredColorScheme(themeManager.currentTheme.colorScheme)
        .onAppear {
            // NDK is now managed centrally
        }
    }
}

// Helper view to show relay connection count
struct RelayCountView: View {
    let ndk: NDK
    @StateObject private var relayCollection: NDKRelayCollection
    
    init(ndk: NDK) {
        self.ndk = ndk
        self._relayCollection = StateObject(wrappedValue: ndk.createRelayCollection())
    }
    
    var body: some View {
        Text("\(relayCollection.connectedCount) connected")
            .font(.caption)
            .foregroundColor(.secondary)
    }
}