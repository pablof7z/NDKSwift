import SwiftUI
import NDKSwift
import NDKSwiftUI

struct ContentView: View {
    @Environment(NDKAuthManager.self) var authManager
    @Environment(NDKManager.self) var ndkManager
    @State private var hasCompletedWelcome = UserDefaults.standard.bool(forKey: "hasCompletedWelcome")
    
    var body: some View {
        Group {
            if authManager.isAuthenticated {
                // Authenticated content
                MainTabView()
            } else if !hasCompletedWelcome {
                // Show welcome screen for first-time users
                PostaWelcomeView()
                    .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WelcomeCompleted"))) { _ in
                        UserDefaults.standard.set(true, forKey: "hasCompletedWelcome")
                        hasCompletedWelcome = true
                    }
            } else {
                // Authentication content
                PostaAuthView()
            }
        }
        .environment(\.ndk, ndkManager.ndk)
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Image(systemName: "house")
                    Text("Home")
                }
            
            ProfileView(pubkey: nil)
                .tabItem {
                    Image(systemName: "person")
                    Text("Profile")
                }
            
            SettingsView()
                .tabItem {
                    Image(systemName: "gear")
                    Text("Settings")
                }
        }
    }
}

#Preview {
    ContentView()
        .environment(NDKAuthManager.shared)
        .environment(NDKManager.shared)
        .environment(RelayManager())
}