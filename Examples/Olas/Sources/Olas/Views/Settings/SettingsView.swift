import SwiftUI
import NDKSwift

struct SettingsView: View {
    @Environment(NostrManager.self) private var nostrManager
    @EnvironmentObject var appState: AppState
    @State private var showingLogoutAlert = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                OlasDesign.Colors.background
                    .ignoresSafeArea()
                
                List {
                    // Account Section
                    Section {
                        NavigationLink(destination: AccountSettingsView()) {
                            settingRow(
                                icon: "person.circle",
                                title: "Account Settings",
                                color: OlasDesign.Colors.primary
                            )
                        }
                    }
                    
                    // Relay Section
                    Section {
                        NavigationLink(destination: RelayManagementView()) {
                            HStack {
                                Image(systemName: "server.rack")
                                    .font(.body)
                                    .foregroundColor(.blue)
                                    .frame(width: 30)
                                
                                Text("Relay Configuration")
                                    .font(OlasDesign.Typography.body)
                                
                                Spacer()
                                
                                Text("\(nostrManager.ndk?.relayPool.relays.count ?? 0)")
                                    .font(OlasDesign.Typography.caption)
                                    .foregroundColor(OlasDesign.Colors.textSecondary)
                            }
                        }
                    }
                    
                    // Appearance & Notifications
                    Section {
                        NavigationLink(destination: ThemeSettingsView()) {
                            settingRow(
                                icon: "paintbrush",
                                title: "Theme",
                                color: .purple
                            )
                        }
                        
                        NavigationLink(destination: NotificationSettingsView()) {
                            settingRow(
                                icon: "bell",
                                title: "Notifications",
                                color: .orange
                            )
                        }
                    }
                    
                    // Blossom Section
                    Section {
                        NavigationLink(destination: Text("Blossom Server Management")) {
                            settingRow(
                                icon: "cloud",
                                title: "Blossom Servers",
                                color: .green
                            )
                        }
                    }
                    
                    // Privacy Section
                    Section {
                        NavigationLink(destination: Text("Blocked Users")) {
                            settingRow(
                                icon: "eye.slash",
                                title: "Blocked Users",
                                color: .red
                            )
                        }
                        
                        NavigationLink(destination: Text("Content Filtering")) {
                            settingRow(
                                icon: "hand.raised",
                                title: "Content Filtering",
                                color: .orange
                            )
                        }
                    }
                    
                    // About Section
                    Section {
                        NavigationLink(destination: Text("About Olas")) {
                            settingRow(
                                icon: "info.circle",
                                title: "About Olas",
                                color: .blue
                            )
                        }
                        
                        NavigationLink(destination: Text("Help & Support")) {
                            settingRow(
                                icon: "questionmark.circle",
                                title: "Help & Support",
                                color: .green
                            )
                        }
                    }
                    
                    // Logout
                    Section {
                        Button(action: { showingLogoutAlert = true }) {
                            HStack {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                    .font(.body)
                                    .foregroundColor(.red)
                                    .frame(width: 30)
                                
                                Text("Logout")
                                    .font(OlasDesign.Typography.body)
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
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
    
    @ViewBuilder
    private func settingRow(icon: String, title: String, color: Color) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(color)
                .frame(width: 30)
            
            Text(title)
                .font(OlasDesign.Typography.body)
                .foregroundColor(OlasDesign.Colors.text)
        }
    }
    
    private func logout() {
        appState.isAuthenticated = false
        appState.currentUser = nil
        Task {
            await nostrManager.disconnect()
        }
        NDKAuthManager.shared.signOut()
    }
}