import SwiftUI
import MarkdownDemoFeature
import NDKSwiftCore

@main
struct MarkdownDemoApp: App {
    @State private var ndk = NDK(
        relayURLs: [
            "wss://relay.damus.io",
            "wss://relay.primal.net",
            "wss://nos.lol",
            "wss://relay.nostr.band"
        ],
        debugMode: true
    )

    var body: some Scene {
        WindowGroup {
            EntityRendererDemoView(ndk: ndk)
                .task {
                    await ndk.connect()
                }
        }
    }
}
