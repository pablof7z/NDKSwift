import SwiftUI
import NDKSwift

@main
struct PostaApp: App {
    @State private var authManager = NDKAuthManager.shared
    @StateObject private var ndkManager = NDKManager.shared
    @StateObject private var relayManager = RelayManager()
    @StateObject private var subscriptionManager = SubscriptionManager()
    @StateObject private var themeManager = ThemeManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authManager)
                .environmentObject(ndkManager)
                .environmentObject(relayManager)
                .environmentObject(subscriptionManager)
                .environmentObject(themeManager)
                .preferredColorScheme(themeManager.currentTheme.colorScheme)
                .onAppear {
                    setupNDK()
                }
        }
    }
    
    private func setupNDK() {
        // Create NDK instance with relay URLs from RelayManager
        let activeRelayUrls = relayManager.relays
            .filter { $0.isActive }
            .map { $0.url }
        
        let ndkInstance = NDK(relayUrls: activeRelayUrls.isEmpty ? [
            "wss://relay.damus.io",
            "wss://nos.lol",
            "wss://relay.snort.social"
        ] : activeRelayUrls)
        
        // Set NDK on managers
        ndkManager.setNDK(ndkInstance)
        authManager.setNDK(ndkInstance)
        relayManager.setNDK(ndkInstance)
        
        // If we have an active session, initialize subscription manager
        Task {
            if let activeSession = authManager.activeSession {
                await subscriptionManager.initialize(ndk: ndkInstance, userPubkey: activeSession.pubkey)
            }
        }
    }
}