import SwiftUI
import NDKSwift

struct MainTabView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            FeedView()
                .tabItem {
                    Label("Feed", systemImage: "photo.stack")
                }
                .tag(0)
            
            Text("Explore")
                .tabItem {
                    Label("Explore", systemImage: "magnifyingglass")
                }
                .tag(1)
            
            Text("Create")
                .tabItem {
                    Label("Create", systemImage: "plus.square")
                }
                .tag(2)
            
            // Profile Tab
            Group {
                if let currentUserPubkey = appState.currentUser?.pubkey {
                    NavigationStack {
                        ProfileView(pubkey: currentUserPubkey)
                    }
                } else {
                    Text("Profile")
                }
            }
            .tabItem {
                Label("Profile", systemImage: "person.circle")
            }
            .tag(3)
            
            Text("Settings")
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(4)
        }
        .tint(OlasDesign.Colors.primary)
    }
}