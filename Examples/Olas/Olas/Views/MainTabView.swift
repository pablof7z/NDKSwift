import SwiftUI
import NDKSwift

struct MainTabView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0
    @State private var previousTab = 0
    @State private var showCreatePost = false
    
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
                    Label("Create", systemImage: "plus.square")
                }
                .tag(2)
                .onAppear {
                    if selectedTab == 2 {
                        showCreatePost = true
                        // Reset to previous tab
                        selectedTab = previousTab
                    }
                }
            
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
        .onChange(of: selectedTab) { oldValue, newValue in
            if newValue != 2 {
                previousTab = oldValue
            }
        }
        .sheet(isPresented: $showCreatePost) {
            CreatePostView()
                .environmentObject(appState)
        }
    }
}