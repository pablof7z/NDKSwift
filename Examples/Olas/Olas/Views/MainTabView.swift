import SwiftUI
import NDKSwift

struct MainTabView: View {
    @Environment(NostrManager.self) private var nostrManager
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0
    @State private var previousTab = 0
    @State private var showCreatePost = false
    @State private var tabBarOpacity = 1.0
    @State private var tabBarOffset: CGFloat = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            FeedView()
                .tabItem {
                    Label("Feed", systemImage: "photo.stack")
                }
                .tag(0)
            
            ExploreView()
                .tabItem {
                    Label("Explore", systemImage: "magnifyingglass")
                }
                .tag(1)
            
            // Create Post - presented as sheet
            Color.clear
                .tabItem {
                    Label("Create", systemImage: "plus.app")
                }
                .tag(2)
                .onAppear {
                    if selectedTab == 2 {
                        showCreatePost = true
                        // Reset to previous tab
                        selectedTab = previousTab
                    }
                }
            
            // Wallet Tab
            OlasWalletView(nostrManager: nostrManager)
                .tabItem {
                    Label("Wallet", systemImage: "bolt.circle")
                }
                .tag(3)
            
            // Profile Tab
            Group {
                if let session = nostrManager.authManager.activeSession {
                    NavigationStack {
                        ProfileView(pubkey: session.pubkey)
                    }
                } else {
                    Text("Profile")
                }
            }
            .tabItem {
                Label("Profile", systemImage: "person.circle")
            }
            .tag(4)
            
            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
            .tag(5)
        }
        .tint(OlasDesign.Colors.primary)
        .onChange(of: selectedTab) { oldValue, newValue in
            if newValue != 2 {
                previousTab = oldValue
            }
        }
        .sheet(isPresented: $showCreatePost) {
            CreatePostView()
                .environmentObject(appState)
                .environment(nostrManager)
        }
    }
}