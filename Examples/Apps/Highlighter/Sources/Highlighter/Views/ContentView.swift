import SwiftUI
import NDKSwift

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var authManager = NDKAuthManager.shared
    @State private var selectedTab = Tab.home
    @State private var tabBarVisible = true
    @State private var showCreateHighlight = false
    @State private var fabScale: CGFloat = 1.0
    @State private var fabRotation: Double = 0
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    
    enum Tab: CaseIterable {
        case home, feed, discover, library, profile
    }
    
    var body: some View {
        if !hasCompletedOnboarding {
            OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                .transition(.asymmetric(
                    insertion: .opacity,
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
        } else if authManager.isAuthenticated {
            ZStack(alignment: .bottom) {
                Group {
                    switch selectedTab {
                    case .home:
                        ModernHomeView(tabBarVisible: $tabBarVisible)
                    case .feed:
                        SimplifiedHybridFeedView()
                    case .discover:
                        SearchView()
                    case .library:
                        LibraryView()
                    case .profile:
                        EnhancedProfileView()
                    }
                }
                .animation(DesignSystem.Animation.quick, value: selectedTab)
                
                if tabBarVisible {
                    VStack(spacing: 0) {
                        // Floating Action Button
                        HStack {
                            Spacer()
                            
                            Button(action: {
                                HapticManager.shared.impact(.medium)
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                    fabScale = 1.2
                                    fabRotation += 180
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                        fabScale = 1.0
                                    }
                                }
                                showCreateHighlight = true
                            }) {
                                ZStack {
                                    // Gradient background
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: [Color.orange, Color.orange.opacity(0.8)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 56, height: 56)
                                    
                                    // Shadow layers for depth
                                    Circle()
                                        .fill(Color.orange.opacity(0.2))
                                        .frame(width: 56, height: 56)
                                        .blur(radius: 8)
                                        .offset(y: 4)
                                    
                                    // Icon
                                    Image(systemName: "highlighter")
                                        .font(.system(size: 24, weight: .semibold))
                                        .foregroundColor(.white)
                                        .rotationEffect(.degrees(fabRotation))
                                }
                                .scaleEffect(fabScale)
                            }
                            .padding(.trailing, 20)
                            .padding(.bottom, 16)
                            .shadow(color: Color.orange.opacity(0.4), radius: 12, y: 6)
                        }
                        
                        ModernTabBar(selectedTab: $selectedTab)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(DesignSystem.Animation.springSnappy, value: tabBarVisible)
                }
            }
            .background(DesignSystem.Colors.background)
            .fullScreenCover(isPresented: $showCreateHighlight) {
                CreateHighlightView()
            }
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
        case .library: return "books.vertical"
        case .profile: return "person"
        }
    }
    
    var filledIcon: String {
        switch self {
        case .home: return "house.fill"
        case .feed: return "play.rectangle.fill"
        case .discover: return "magnifyingglass"
        case .library: return "books.vertical.fill"
        case .profile: return "person.fill"
        }
    }
    
    var title: String {
        switch self {
        case .home: return "Home"
        case .feed: return "Feed"
        case .discover: return "Discover"
        case .library: return "Library"
        case .profile: return "Profile"
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
