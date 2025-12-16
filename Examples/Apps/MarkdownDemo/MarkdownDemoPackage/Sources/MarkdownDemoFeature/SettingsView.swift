import SwiftUI
import NDKSwiftCore

public struct SettingsView: View {
    let ndk: NDK

    public init(ndk: NDK) {
        self.ndk = ndk
    }

    public var body: some View {
        NavigationView {
            List {
                Section("Developer") {
                    NavigationLink {
                        DeveloperToolsView(ndk: ndk)
                    } label: {
                        Label("Developer Tools", systemImage: "hammer")
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}
