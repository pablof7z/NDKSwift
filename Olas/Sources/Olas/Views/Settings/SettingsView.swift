import SwiftUI
import NDKSwift

public struct SettingsView: View {
    let ndk: NDK
    @EnvironmentObject private var authViewModel: AuthViewModel
    @StateObject private var blossomManager: NDKBlossomServerManager

    public init(ndk: NDK) {
        self.ndk = ndk
        self._blossomManager = StateObject(wrappedValue: NDKBlossomServerManager(ndk: ndk))
    }

    public var body: some View {
        List {
            Section("Account") {
                NavigationLink(destination: AccountSettingsView()) {
                    SettingsRow(icon: "person.circle", title: "Account", color: .blue)
                }
            }

            Section("Wallet") {
                NavigationLink(destination: SparkWalletSettingsView(ndk: ndk)) {
                    SettingsRow(icon: "bolt.fill", title: "Spark Wallet", color: OlasTheme.Colors.zapGold)
                }
            }

            Section("App") {
                NavigationLink(destination: AppearanceSettingsView()) {
                    SettingsRow(icon: "paintbrush", title: "Appearance", color: .purple)
                }
                NavigationLink(destination: VideoSettingsView()) {
                    SettingsRow(icon: "video", title: "Video", color: .red)
                }
                NavigationLink(destination: RelaySettingsView(ndk: ndk)) {
                    SettingsRow(icon: "network", title: "Relays", color: .green)
                }
                NavigationLink(destination: BlossomSettingsView(manager: blossomManager)) {
                    SettingsRow(icon: "externaldrive.badge.icloud", title: "Media Servers", color: .teal)
                }
            }

            Section("Privacy & Security") {
                NavigationLink(destination: PrivacySettingsView()) {
                    SettingsRow(icon: "lock.shield", title: "Privacy", color: .orange)
                }
            }

            Section {
                Button(role: .destructive) {
                    Task { await authViewModel.logout() }
                } label: {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text("Logout")
                    }
                }
            }
        }
        .navigationTitle("Settings")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

struct SettingsRow: View {
    let icon: String
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(color)
                .cornerRadius(6)
            Text(title)
        }
    }
}
