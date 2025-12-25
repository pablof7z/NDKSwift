import SwiftUI
import ChirpFeature

// Notification for NWC callback
extension Notification.Name {
    static let nwcCallbackReceived = Notification.Name("nwcCallbackReceived")
}

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
            print("[Chirp] NIP-46 signer returned via callback")

        case "nwc":
            handleNWCCallback(url)

        default:
            print("[Chirp] Unknown callback host: \(url.host ?? "nil")")
        }
    }

    private func handleNWCCallback(_ url: URL) {
        print("[Chirp] NWC callback received: \(url.absoluteString)")

        // Parse: chirp://nwc?value=nostr+walletconnect://...
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let valueParam = components.queryItems?.first(where: { $0.name == "value" })?.value,
              let decodedURI = valueParam.removingPercentEncoding
        else {
            print("[Chirp] Failed to parse NWC callback URL")
            return
        }

        // Validate it's a proper NWC URI
        guard decodedURI.hasPrefix("nostr+walletconnect://") || decodedURI.hasPrefix("nostrwalletconnect://") else {
            print("[Chirp] Invalid NWC URI format: \(decodedURI)")
            return
        }

        print("[Chirp] Received NWC URI: \(decodedURI)")

        // Post notification with the URI
        NotificationCenter.default.post(
            name: .nwcCallbackReceived,
            object: nil,
            userInfo: ["uri": decodedURI]
        )
    }
}
