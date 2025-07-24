import SwiftUI
import NDKSwift

struct ContentView: View {
    @Environment(NDKAuthManager.self) var authManager
    @Environment(NDKManager.self) var ndkManager
    
    var body: some View {
        Group {
            if authManager.isAuthenticated {
                // Authenticated content
                MainTabView()
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