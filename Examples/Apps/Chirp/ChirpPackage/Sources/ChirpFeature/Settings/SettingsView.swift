import SwiftUI
import NDKSwiftCore

struct SettingsView: View {
    @Environment(ChirpState.self) private var state
    @State private var walletState: WalletState?
    @State private var connectedRelayCount: Int = 0

    var body: some View {
        List {
            Section("Account") {
                NavigationLink {
                    AccountSwitcher()
                } label: {
                    SettingsRow(
                        icon: "person.2.fill",
                        title: "Manage Accounts",
                        subtitle: "Switch between accounts",
                        color: .blue
                    )
                }
            }

            Section("Network") {
                NavigationLink {
                    RelayDashboardView()
                } label: {
                    SettingsRow(
                        icon: "antenna.radiowaves.left.and.right",
                        title: "Relay Monitor",
                        subtitle: "Connection states and message counts",
                        color: .green
                    )
                }
                .badge(connectedRelayCount)

                NavigationLink {
                    AppRelaysView()
                } label: {
                    SettingsRow(
                        icon: "square.grid.2x2",
                        title: "App Relays",
                        subtitle: "Default relays configured by the app",
                        color: .purple
                    )
                }

                NavigationLink {
                    DiscoveryRelaysView()
                } label: {
                    SettingsRow(
                        icon: "magnifyingglass",
                        title: "Discovery Relays",
                        subtitle: "purplepag.es for content discovery",
                        color: .purple
                    )
                }

                NavigationLink {
                    UserRelaysView()
                } label: {
                    SettingsRow(
                        icon: "person.text.rectangle",
                        title: "User Relays",
                        subtitle: "NIP-65 relay lists",
                        color: .purple
                    )
                }

                NavigationLink {
                    SearchRelaysView()
                } label: {
                    SettingsRow(
                        icon: "magnifyingglass.circle",
                        title: "Search Relays",
                        subtitle: "relay.nostr.band for search",
                        color: .purple
                    )
                }
            }

            Section("Wallet") {
                if let walletState = walletState {
                    NavigationLink {
                        WalletSettingsView(walletState: walletState)
                    } label: {
                        SettingsRow(
                            icon: "wallet.bifold.fill",
                            title: "Wallet Settings",
                            subtitle: walletState.walletType.displayName,
                            color: .orange
                        )
                    }
                } else {
                    SettingsRow(
                        icon: "wallet.bifold.fill",
                        title: "Wallet Settings",
                        subtitle: "Loading...",
                        color: .gray
                    )
                }
            }

            Section("Content") {
                NavigationLink {
                    UnpublishedEventsView()
                } label: {
                    SettingsRow(
                        icon: "exclamationmark.triangle.fill",
                        title: "Unpublished Events",
                        subtitle: "View pending events",
                        color: .orange
                    )
                }
            }

            Section("Developer") {
                NavigationLink {
                    DeveloperToolsView()
                } label: {
                    SettingsRow(
                        icon: "hammer.fill",
                        title: "Developer Tools",
                        subtitle: "Debug and diagnostics",
                        color: .gray
                    )
                }
            }

            Section("About") {
                HStack(spacing: 12) {
                    SettingsIcon(icon: "info.circle.fill", color: .blue)
                    Text("Version")
                    Spacer()
                    Text("1.0.0")
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    SettingsIcon(icon: "swift", color: .orange)
                    Text("Built with")
                    Spacer()
                    Text("NDKSwift")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button(role: .destructive) {
                    Task {
                        await state.logout()
                    }
                } label: {
                    HStack(spacing: 12) {
                        SettingsIcon(icon: "rectangle.portrait.and.arrow.right", color: .red)
                        Text("Sign Out")
                    }
                }
            }
        }
        .navigationTitle("Settings")
        .task {
            if walletState == nil {
                walletState = WalletState(ndk: state.ndk)
            }
            connectedRelayCount = state.ndk.connectedRelayCount
        }
    }
}

// MARK: - Supporting Views

private struct SettingsIcon: View {
    let icon: String
    let color: Color

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 16))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct SettingsRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(icon: icon, color: color)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    let ndk = NDK(relayURLs: [])
    let authManager = NDKAuthManager(ndk: ndk)
    let state = ChirpState(ndk: ndk, authManager: authManager)

    return NavigationStack {
        SettingsView()
            .environment(state)
    }
}
