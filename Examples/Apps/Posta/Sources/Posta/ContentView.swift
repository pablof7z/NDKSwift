import SwiftUI
import NDKSwift

struct ContentView: View {
    @Environment(NDKAuthManager.self) var authManager
    @EnvironmentObject var ndkManager: NDKManager
    
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
        .environmentObject(NDKManager.shared)
        .environmentObject(RelayManager())
}