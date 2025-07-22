import SwiftUI
import NDKSwift

@main
struct PostaApp: App {
    @State private var authManager = NDKAuthManager.shared
    @State private var ndkManager = NDKManager.shared
    @State private var relayManager = RelayManager()
    @State private var subscriptionManager = SubscriptionManager()
    @StateObject private var themeManager = ThemeManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authManager)
                .environment(ndkManager)
                .environment(relayManager)
                .environment(subscriptionManager)
                .environmentObject(themeManager)
                .preferredColorScheme(themeManager.currentTheme.colorScheme)
                .onAppear {
                    setupNDK()
                }
        }
    }
    
    private func setupNDK() {
        Task {
            // Create NDK instance with relay URLs from RelayManager
            let activeRelayUrls = relayManager.relays
                .filter { $0.isActive }
                .map { $0.url }
            
            let relayUrls = activeRelayUrls.isEmpty ? [
                "wss://relay.damus.io",
                "wss://nos.lol",
                "wss://relay.snort.social"
            ] : activeRelayUrls
            
            // Initialize with SQLite cache for better performance and negentropy sync support
            let ndkInstance: NDK
            do {
                let cache = try await NDKSQLiteCache()
                ndkInstance = NDK(relayUrls: relayUrls, cache: cache)
                print("PostaApp - NDK initialized with SQLite cache")
            } catch {
                print("PostaApp - Failed to initialize SQLite cache: \(error). Continuing without cache.")
                ndkInstance = NDK(relayUrls: relayUrls)
            }
            
            // Set NDK on managers
            await MainActor.run {
                let userPubkey = authManager.activeSession?.pubkey
                ndkManager.setNDK(ndkInstance, userPubkey: userPubkey)
                authManager.setNDK(ndkInstance)
                relayManager.setNDK(ndkInstance)
            }
            
            // Connect to relays
            await ndkInstance.connect()
            
            // If we have an active session, initialize subscription manager
            if let activeSession = authManager.activeSession {
                await subscriptionManager.initialize(ndk: ndkInstance, userPubkey: activeSession.pubkey)
            }
        }
    }
}