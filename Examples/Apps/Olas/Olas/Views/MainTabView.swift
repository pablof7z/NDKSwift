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
    @StateObject private var dmManager: DirectMessagesManager
    
    init() {
        // Initialize managers
        let nostrManager = NostrManager()
        self._dmManager = StateObject(wrappedValue: DirectMessagesManager(nostrManager: nostrManager))
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Home Feed
            NavigationStack {
                FeedView()
            }
            .tabItem {
                Label("Home", systemImage: selectedTab == 0 ? "house.fill" : "house")
            }
            .tag(0)
            
            // Explore/Search
            NavigationStack {
                ExploreView()
            }
            .tabItem {
                Label("Explore", systemImage: selectedTab == 1 ? "magnifyingglass.circle.fill" : "magnifyingglass")
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
            
            // Messages Tab
            NavigationStack {
                MessagesListView(nostrManager: nostrManager)
            }
            .tabItem {
                Label("Messages", systemImage: selectedTab == 3 ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right")
            }
            .tag(3)
            .badge(dmManager.unreadCount > 0 ? "\(dmManager.unreadCount)" : nil)
            
            // Profile Tab with Wallet & Analytics Access
            Group {
                if let session = nostrManager.authManager.activeSession {
                    NavigationStack {
                        ProfileView(pubkey: session.pubkey)
                            .toolbar {
                                ToolbarItem(placement: .navigationBarTrailing) {
                                    HStack(spacing: 16) {
                                        // Analytics
                                        NavigationLink(destination: AnalyticsDashboardView().environment(nostrManager)) {
                                            Image(systemName: "chart.line.uptrend.xyaxis")
                                                .foregroundStyle(OlasDesign.Colors.primary)
                                        }
                                        
                                        // Wallet
                                        NavigationLink(destination: OlasWalletView(walletManager: OlasWalletManager(nostrManager: nostrManager), nostrManager: nostrManager)) {
                                            Image(systemName: "bolt.circle")
                                                .foregroundStyle(OlasDesign.Colors.primary)
                                        }
                                    }
                                }
                            }
                    }
                } else {
                    Text("Profile")
                }
            }
            .tabItem {
                Label("Profile", systemImage: selectedTab == 4 ? "person.circle.fill" : "person.circle")
            }
            .tag(4)
        }
        .tint(OlasDesign.Colors.primary)
        .onChange(of: selectedTab) { oldValue, newValue in
            if newValue != 2 {
                previousTab = oldValue
            }
        }
        .task {
            dmManager.startObservingMessages()
        }
        .sheet(isPresented: $showCreatePost) {
            CreatePostView()
                .environmentObject(appState)
                .environment(nostrManager)
        }
        .onAppear {
            setupTabBarAppearance()
        }
    }
    
    private func setupTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(OlasDesign.Colors.background)
        appearance.shadowColor = UIColor(OlasDesign.Colors.divider)
        
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}