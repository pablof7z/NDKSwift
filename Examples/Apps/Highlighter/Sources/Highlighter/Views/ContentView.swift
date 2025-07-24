import SwiftUI
import NDKSwift

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var authManager = NDKAuthManager.shared
    @State private var selectedTab = Tab.home
    @State private var tabBarVisible = true
    
    enum Tab: CaseIterable {
        case home, feed, discover, create, library, profile
    }
    
    var body: some View {
        if authManager.isAuthenticated {
            ZStack(alignment: .bottom) {
                Group {
                    switch selectedTab {
                    case .home:
                        ModernHomeView(tabBarVisible: $tabBarVisible)
                    case .feed:
                        HighlightsFeedView(tabBarVisible: $tabBarVisible)
                    case .discover:
                        SearchView()
                    case .create:
                        CreateHighlightView()
                    case .library:
                        LibraryView()
                    case .profile:
                        ProfileView()
                    }
                }
                .animation(DesignSystem.Animation.quick, value: selectedTab)
                
                if tabBarVisible {
                    ModernTabBar(selectedTab: $selectedTab)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(DesignSystem.Animation.springSnappy, value: tabBarVisible)
                }
            }
            .background(DesignSystem.Colors.background)
        } else {
            ModernAuthenticationView()
                .transition(.opacity)
        }
    }
}

// MARK: - Tab Extensions

extension ContentView.Tab {
    var icon: String {
        switch self {
        case .home: return "house"
        case .feed: return "play.rectangle"
        case .discover: return "magnifyingglass"
        case .create: return "highlighter"
        case .library: return "books.vertical"
        case .profile: return "person"
        }
    }
    
    var filledIcon: String {
        switch self {
        case .home: return "house.fill"
        case .feed: return "play.rectangle.fill"
        case .discover: return "magnifyingglass"
        case .create: return "highlighter"
        case .library: return "books.vertical.fill"
        case .profile: return "person.fill"
        }
    }
    
    var title: String {
        switch self {
        case .home: return "Home"
        case .feed: return "Feed"
        case .discover: return "Discover"
        case .create: return "Create"
        case .library: return "Library"
        case .profile: return "Profile"
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}