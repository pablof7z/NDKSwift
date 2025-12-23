import SwiftUI
import MarkdownDemoFeature
import NDKSwiftCore
import NDKSwiftSQLite
import NDKSwiftNostrDB

@main
struct MarkdownDemoApp: App {
    @AppStorage("selectedCacheType") private var selectedCacheTypeRaw: String = CacheType.sqlite.rawValue
    @State private var ndk: NDK?
    @State private var isInitializing = true
    @State private var initializationError: String?

    var body: some Scene {
        WindowGroup {
            Group {
                if isInitializing {
                    ProgressView("Initializing cache...")
                } else if let error = initializationError {
                    ContentUnavailableView(
                        "Initialization Failed",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                } else if let ndk = ndk {
                    EntityRendererDemoView(ndk: ndk)
                        .task {
                            await ndk.connect()
                        }
                }
            }
            .task {
                await initializeNDK()
            }
        }
    }

    private func initializeNDK() async {
        isInitializing = true
        initializationError = nil

        do {
            let cacheType = CacheType(rawValue: selectedCacheTypeRaw) ?? .sqlite

            guard cacheType.isAvailableOnCurrentPlatform else {
                throw CacheError.platformNotSupported
            }

            let cache = try await cacheType.createCache()

            // No explicit app relays - purplepag.es is configured via NDKOutboxConfig.default
            // Content relays will be discovered dynamically via NIP-65
            ndk = NDK(
                relayURLs: [],
                cache: cache,
                debugMode: true
            )

            print("✅ Initialized with \(cacheType.displayName) cache")
        } catch {
            initializationError = "Failed to initialize cache: \(error.localizedDescription)"
            print("❌ Cache initialization error: \(error)")
        }

        isInitializing = false
    }
}
