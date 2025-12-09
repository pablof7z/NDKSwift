import SwiftUI
import NDKSwift

@main
struct OlasApp: App {
    @State private var ndk: NDK?
    @State private var isInitialized = false

    var body: some Scene {
        WindowGroup {
            Group {
                if let ndk = ndk, isInitialized {
                    MainTabView(ndk: ndk)
                } else {
                    ProgressView("Connecting...")
                        .task {
                            await initializeNDK()
                        }
                }
            }
        }
    }

    private func initializeNDK() async {
        let relayUrls = OlasConstants.defaultRelays
        let newNDK = NDK(relayUrls: relayUrls)

        // Initialize NostrDB cache
        let cachePath = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("olas_cache")
            .path

        do {
            let cache = try await NDKNostrDBCache(path: cachePath)
            newNDK.cache = cache
        } catch {
            print("Failed to initialize cache: \(error)")
        }

        await newNDK.connect()

        await MainActor.run {
            self.ndk = newNDK
            self.isInitialized = true
        }
    }
}
