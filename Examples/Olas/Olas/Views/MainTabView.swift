import SwiftUI

struct MainTabView: View {
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
            
            Text("Profile")
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
        .tint(Color(hex: "667eea"))
    }
}