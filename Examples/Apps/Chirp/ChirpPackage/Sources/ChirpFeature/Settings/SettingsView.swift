import SwiftUI
import NDKSwiftCore

struct SettingsView: View {
    @Environment(ChirpState.self) private var state
    @State private var walletState: WalletState?

    var body: some View {
        List {
            Section("Account") {
                NavigationLink {
                    AccountSwitcher()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Manage Accounts")
                            Text("Switch between accounts")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "person.2.fill")
                            .foregroundStyle(.blue)
                    }
                }
            }

            Section("Wallet") {
                if let walletState = walletState {
                    NavigationLink {
                        WalletSettingsView(walletState: walletState)
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Wallet Settings")
                                Text(walletState.walletType.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "wallet.bifold.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                } else {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Wallet Settings")
                            Text("Loading...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "wallet.bifold.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Content") {
                NavigationLink {
                    UnpublishedEventsView()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Unpublished Events")
                            Text("View pending events")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }

            Section("Network") {
                NavigationLink {
                    RelayManagerView()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Relay Manager")
                            Text("Manage your relay connections")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .foregroundStyle(.purple)
                    }
                }
            }

            Section("Developer") {
                NavigationLink {
                    DeveloperToolsView()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Developer Tools")
                            Text("Debug and diagnostics")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "hammer.fill")
                            .foregroundStyle(.gray)
                    }
                }
            }

            Section("About") {
                LabeledContent {
                    Text("1.0.0")
                        .foregroundStyle(.secondary)
                } label: {
                    Label("Version", systemImage: "info.circle.fill")
                }

                LabeledContent {
                    Text("NDKSwift")
                        .foregroundStyle(.secondary)
                } label: {
                    Label("Built with", systemImage: "swift")
                }
            }

            Section {
                Button(role: .destructive) {
                    Task {
                        await state.logout()
                    }
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
        .navigationTitle("Settings")
        .task {
            if walletState == nil {
                walletState = WalletState(ndk: state.ndk)
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
