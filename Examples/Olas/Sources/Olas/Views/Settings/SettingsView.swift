import SwiftUI
import NDKSwift

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var showingLogoutAlert = false
    
    var body: some View {
        NavigationStack {
            List {
                // Account Section
                Section("Account") {
                    HStack {
                        Image(systemName: "person.circle")
                        Text("Account Details")
                    }
                    
                    HStack {
                        Image(systemName: "key")
                        Text("Backup Keys")
                    }
                    
                    HStack {
                        Image(systemName: "lock")
                        Text("Security")
                    }
                }
                
                // Relay Section
                Section("Relays") {
                    HStack {
                        Image(systemName: "server.rack")
                        Text("Relay Configuration")
                        Spacer()
                        Text("\(appState.ndk?.relayPool.relays.count ?? 0)")
                            .foregroundColor(.secondary)
                    }
                }
                
                // Blossom Section
                Section("Blossom Servers") {
                    HStack {
                        Image(systemName: "cloud")
                        Text("Server Management")
                    }
                }
                
                // Privacy Section
                Section("Privacy") {
                    HStack {
                        Image(systemName: "eye.slash")
                        Text("Blocked Users")
                    }
                    
                    HStack {
                        Image(systemName: "hand.raised")
                        Text("Content Filtering")
                    }
                }
                
                // About Section
                Section("About") {
                    HStack {
                        Image(systemName: "info.circle")
                        Text("About Olas")
                    }
                    
                    HStack {
                        Image(systemName: "questionmark.circle")
                        Text("Help & Support")
                    }
                }
                
                // Logout
                Section {
                    Button(action: { showingLogoutAlert = true }) {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .foregroundColor(.red)
                            Text("Logout")
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .alert("Logout", isPresented: $showingLogoutAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Logout", role: .destructive) {
                    logout()
                }
            } message: {
                Text("Are you sure you want to logout?")
            }
        }
    }
    
    private func logout() {
        appState.isAuthenticated = false
        appState.currentUser = nil
        appState.ndk?.signer = nil
    }
}