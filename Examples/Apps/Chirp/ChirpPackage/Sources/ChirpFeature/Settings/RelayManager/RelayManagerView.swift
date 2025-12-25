import SwiftUI
import NDKSwiftCore

struct RelayManagerView: View {
    var body: some View {
        Form {
            Section {
                NavigationLink {
                    AppRelaysView()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("App Relays", systemImage: "square.grid.2x2")
                        Text("Default relays configured by the app")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                NavigationLink {
                    DiscoveryRelaysView()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Discovery Relays", systemImage: "magnifyingglass")
                        Text("purplepag.es for content discovery")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                NavigationLink {
                    UserRelaysView()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("User Relays", systemImage: "person.text.rectangle")
                        Text("NIP-65 relay lists")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                NavigationLink {
                    SearchRelaysView()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Search Relays", systemImage: "magnifyingglass.circle")
                        Text("relay.nostr.band for search")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Relay Manager")
    }
}

#Preview {
    let ndk = NDK(relayURLs: [])
    let authManager = NDKAuthManager(ndk: ndk)
    let relayCollection = NDKRelayCollection(ndk: ndk)
    let state = ChirpState(ndk: ndk, authManager: authManager, relayCollection: relayCollection)

    return NavigationStack {
        RelayManagerView()
            .environment(state)
    }
}
