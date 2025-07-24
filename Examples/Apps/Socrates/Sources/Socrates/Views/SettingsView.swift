import SwiftUI
import NDKSwift

struct SettingsView: View {
    @EnvironmentObject var nostrManager: NostrManager
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    @State private var currentUser: NDKUser?
    @State private var userProfile: NDKUserProfile?
    @State private var copiedNpub = false
    
    var body: some View {
        List {
                // Account section
                Section {
                    if let currentUser = currentUser {
                        HStack {
                            // Profile picture placeholder
                            Circle()
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color.purple,
                                            Color.blue
                                        ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .overlay(
                                    Text((userProfile?.displayName ?? userProfile?.name ?? "User").prefix(1).uppercased())
                                        .font(.headline)
                                        .foregroundColor(.white)
                                )
                                .frame(width: 50, height: 50)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(userProfile?.displayName ?? userProfile?.name ?? "Nostr User")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                
                                HStack(spacing: 4) {
                                    Text(String(currentUser.npub.prefix(16)) + "...")
                                        .font(.caption)
                                        .foregroundStyle(Color.white.opacity(0.6))
                                    
                                    Button(action: { copyNpub(currentUser.npub) }) {
                                        Image(systemName: copiedNpub ? "checkmark.circle.fill" : "doc.on.doc")
                                            .font(.caption)
                                            .foregroundColor(copiedNpub ? .green : Color.white.opacity(0.6))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            
                            Spacer()
                        }
                    } else {
                        Text("No user logged in")
                            .foregroundStyle(Color.white.opacity(0.6))
                    }
                } header: {
                    Text("Account")
                        .foregroundColor(Color.white.opacity(0.8))
                }
                .listRowBackground(Color.white.opacity(0.05))
                
                // Preferences
                Section {
                    NavigationLink(destination: RelayManagementView()) {
                        Label {
                            Text("Relays")
                                .foregroundColor(.white)
                        } icon: {
                            Image(systemName: "network")
                                .foregroundColor(.purple)
                        }
                    }
                    
                    NavigationLink(destination: MuteListView()) {
                        Label {
                            Text("Muted Users")
                                .foregroundColor(.white)
                        } icon: {
                            Image(systemName: "speaker.slash")
                                .foregroundColor(.purple)
                        }
                    }
                } header: {
                    Text("Preferences")
                        .foregroundColor(Color.white.opacity(0.8))
                }
                .listRowBackground(Color.white.opacity(0.05))
                
                // App Info
                Section {
                    LabeledContent {
                        Text("1.0.0")
                            .foregroundColor(Color.white.opacity(0.6))
                    } label: {
                        Text("Version")
                            .foregroundColor(.white)
                    }
                    
                    Link(destination: URL(string: "https://github.com/nostr-dev-kit/ndk-swift")!) {
                        Label {
                            Text("Source Code")
                                .foregroundColor(.white)
                        } icon: {
                            Image(systemName: "chevron.left.forwardslash.chevron.right")
                                .foregroundColor(.purple)
                        }
                    }
                } header: {
                    Text("App")
                        .foregroundColor(Color.white.opacity(0.8))
                }
                .listRowBackground(Color.white.opacity(0.05))
                
                // Danger zone
                Section {
                    Button(role: .destructive, action: logout) {
                        Label {
                            Text("Sign Out")
                                .foregroundColor(.red)
                        } icon: {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .foregroundColor(.red)
                        }
                    }
                }
                .listRowBackground(Color.white.opacity(0.05))
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.05, green: 0.02, blue: 0.08),
                        Color(red: 0.02, green: 0.01, blue: 0.03),
                        Color.black
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.purple)
                }
            }
            .task {
                await loadUserData()
            }
        .preferredColorScheme(.dark)
    }
    
    private func loadUserData() async {
        guard let ndk = nostrManager.ndk else { return }
        
        if let pubkey = await ndk.sessionData?.pubkey {
            currentUser = NDKUser(pubkey: pubkey)
            appState.currentUser = currentUser
            // Fetch profile using NDKProfileManager
            for await profile in await ndk.profileManager.observe(for: pubkey, maxAge: 3600) {
                userProfile = profile
                break // Take first profile
            }
        }
    }
    
    private func copyNpub(_ npub: String) {
        #if os(iOS)
        UIPasteboard.general.string = npub
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(npub, forType: .string)
        #endif
        withAnimation {
            copiedNpub = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                copiedNpub = false
            }
        }
    }
    
    private func logout() {
        nostrManager.logout()
        appState.reset()
        dismiss()
    }
}

// MARK: - Mute List View (Placeholder)
struct MuteListView: View {
    @EnvironmentObject var nostrManager: NostrManager
    @State private var mutedUsers: Set<String> = []
    
    var body: some View {
        List {
            if mutedUsers.isEmpty {
                Text("No muted users")
                    .foregroundStyle(Color.white.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(Array(mutedUsers), id: \.self) { pubkey in
                    HStack {
                        Text(String(pubkey.prefix(16)) + "...")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .listRowBackground(Color.white.opacity(0.05))
                }
            }
        }
        .navigationTitle("Muted Users")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.05, green: 0.02, blue: 0.08),
                    Color(red: 0.02, green: 0.01, blue: 0.03),
                    Color.black
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .task {
            await loadMutedUsers()
        }
    }
    
    private func loadMutedUsers() async {
        guard let ndk = nostrManager.ndk,
              let sessionData = ndk.sessionData else { return }
        
        mutedUsers = sessionData.muteList
    }
}