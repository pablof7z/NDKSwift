import SwiftUI
import NDKSwift

public struct SettingsView: View {
    let ndk: NDK
    @EnvironmentObject private var authViewModel: AuthViewModel

    public init(ndk: NDK) {
        self.ndk = ndk
    }

    public var body: some View {
        List {
            Section("Account") {
                NavigationLink(destination: AccountSettingsView()) {
                    SettingsRow(icon: "person.circle", title: "Account", color: .blue)
                }
            }

            Section("App") {
                NavigationLink(destination: AppearanceSettingsView()) {
                    SettingsRow(icon: "paintbrush", title: "Appearance", color: .purple)
                }
                NavigationLink(destination: RelaySettingsView(ndk: ndk)) {
                    SettingsRow(icon: "network", title: "Relays", color: .green)
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
