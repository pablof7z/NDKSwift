import SwiftUI
import NDKSwiftCore

struct DeveloperToolsView: View {
    let ndk: NDK

    var body: some View {
        List {
            Section {
                NavigationLink {
                    CacheSettingsView(currentCache: ndk.cache)
                } label: {
                    Label("Cache", systemImage: "internaldrive")
                }
            } header: {
                Text("Storage")
            }
        }
        .navigationTitle("Developer Tools")
    }
}
