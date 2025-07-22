import SwiftUI
import NDKSwift

struct ContentView: View {
    @Environment(NDKAuthManager.self) var authManager
    @Environment(NDKManager.self) var ndkManager
    
    var body: some View {
        NDKAuthView(authManager: authManager, ndk: ndkManager.ndk, authenticatedContent: {
            // Authenticated content
            MainTabView()
        }, authenticationContent: {
            // Authentication content
            PostaAuthView()
        })
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