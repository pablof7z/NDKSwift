import SwiftUI
import NDKSwift

@main
struct PostaApp: App {
    @State private var authManager = NDKAuthManager.shared
    @State private var ndkManager = NDKManager.shared
    @State private var relayManager = RelayManager()
    @StateObject private var themeManager = ThemeManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authManager)
                .environment(ndkManager)
                .environment(relayManager)
                .environmentObject(themeManager)
                .preferredColorScheme(themeManager.currentTheme.colorScheme)
                .onAppear {
                    setupNDK()
                }
        }
    }
    
    private func setupNDK() {
        Task {
            // Get all relays (default + user added)
            let relayUrls = relayManager.getAllRelays()
            
            // Initialize with SQLite cache for better performance and negentropy sync support
            let ndkInstance: NDK
            do {
                // Initialize SQLite cache with debug mode for development
                let cache = try await NDKSQLiteCache(debugMode: false)
                ndkInstance = NDK(relayUrls: relayUrls, cache: cache)
                print("PostaApp - NDK initialized with SQLite cache")
            } catch {
                print("PostaApp - Failed to initialize SQLite cache: \(error). Continuing without cache.")
                ndkInstance = NDK(relayUrls: relayUrls)
            }
            
            // Configure client tag for Posta (NIP-89)
            ndkInstance.clientTagConfig = NDKClientTagConfig(
                name: "Posta",
                autoTag: true
            )
            
            // Set NDK on managers
            await MainActor.run {
                ndkManager.setNDK(ndkInstance)
                authManager.setNDK(ndkInstance)
                relayManager.setNDK(ndkInstance)
            }
            
            // Connect to relays
            await ndkInstance.connect()
        }
    }
}