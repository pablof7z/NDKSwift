import SwiftUI
import ChirpFeature

@main
struct ChirpApp: App {
    var body: some Scene {
        WindowGroup {
            ChirpRootView()
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
        }
    }

    private func handleIncomingURL(_ url: URL) {
        guard url.scheme == "chirp" else { return }

        switch url.host {
        case "nip46":
            // NIP-46 callback - signer app returned to Chirp
            // The actual connection is handled via relays in LoginView
            print("[Chirp] NIP-46 signer returned via callback")
        default:
            break
        }
    }
}
