import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var isShowingSplash = true
    
    var body: some View {
        ZStack {
            Group {
                if authManager.isAuthenticated {
                    MainTabView()
                } else {
                    AuthView()
                }
            }
            .opacity(isShowingSplash ? 0 : 1)
            .animation(.easeInOut(duration: 0.5), value: isShowingSplash)
            
            if isShowingSplash {
                SplashView(isShowingSplash: $isShowingSplash)
                    .transition(.opacity)
            }
        }
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
            
            Text("Profile")
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
        .environmentObject(AuthManager())
}