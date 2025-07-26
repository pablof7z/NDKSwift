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
    @State private var tabTransition: AnyTransition = .identity
    @State private var contentOffset: CGFloat = 0
    @State private var dragOffset: CGFloat = 0
    @State private var showTabSwitchAnimation = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    
    enum Tab: CaseIterable {
        case home, feed, discover, library, profile
    }
    
    var body: some View {
        if !hasCompletedOnboarding || !authManager.isAuthenticated {
            OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                .transition(.asymmetric(
                    insertion: .opacity,
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
        } else {
            ZStack(alignment: .bottom) {
                // Content with custom transitions
                ZStack {
                    ForEach(Tab.allCases, id: \.self) { tab in
                        Group {
                            switch tab {
                            case .home:
                                SimplifiedHybridFeedView()
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
                        .opacity(selectedTab == tab ? 1 : 0)
                        .scaleEffect(selectedTab == tab ? 1 : 0.95)
                        .offset(x: offsetForTab(tab))
                        .blur(radius: selectedTab == tab ? 0 : 2)
                        .allowsHitTesting(selectedTab == tab)
                        .transition(transitionForTab(tab))
                    }
                }
                .animation(.spring(response: 0.5, dampingFraction: 0.8, blendDuration: 0.2), value: selectedTab)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            dragOffset = value.translation.width
                        }
                        .onEnded { value in
                            let threshold: CGFloat = 50
                            if abs(value.translation.width) > threshold {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    if value.translation.width > 0 {
                                        // Swipe right - go to previous tab
                                        switchToPreviousTab()
                                    } else {
                                        // Swipe left - go to next tab
                                        switchToNextTab()
                                    }
                                }
                            }
                            dragOffset = 0
                        }
                )
                
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
                                showTabSwitchAnimation = true
                            }) {
                                ZStack {
                                    // Outer glow
                                    Circle()
                                        .fill(
                                            RadialGradient(
                                                colors: [
                                                    DesignSystem.Colors.secondary.opacity(0.4),
                                                    DesignSystem.Colors.secondary.opacity(0)
                                                ],
                                                center: .center,
                                                startRadius: 20,
                                                endRadius: 40
                                            )
                                        )
                                        .frame(width: 80, height: 80)
                                        .blur(radius: 10)
                                        .opacity(fabScale > 1 ? 1 : 0.6)
                                    
                                    // Gradient background
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: [DesignSystem.Colors.secondary, DesignSystem.Colors.secondary.opacity(0.8)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 56, height: 56)
                                        .overlay(
                                            Circle()
                                                .stroke(
                                                    LinearGradient(
                                                        colors: [Color.white.opacity(0.6), Color.white.opacity(0.2)],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    ),
                                                    lineWidth: 1
                                                )
                                        )
                                    
                                    // Shadow layers for depth
                                    Circle()
                                        .fill(DesignSystem.Colors.secondary.opacity(0.2))
                                        .frame(width: 56, height: 56)
                                        .blur(radius: 8)
                                        .offset(y: 4)
                                    
                                    // Icon with enhanced animation
                                    Image(systemName: "highlighter")
                                        .font(.system(size: 24, weight: .semibold))
                                        .foregroundColor(.white)
                                        .rotationEffect(.degrees(fabRotation))
                                        .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                                }
                                .scaleEffect(fabScale)
                                .rotation3DEffect(
                                    .degrees(fabScale > 1 ? 10 : 0),
                                    axis: (x: 0, y: 1, z: 0)
                                )
                            }
                            .padding(.trailing, DesignSystem.Spacing.large)
                            .padding(.bottom, DesignSystem.Spacing.medium)
                            .shadow(color: DesignSystem.Colors.secondary.opacity(0.4), radius: DesignSystem.Shadow.medium.radius, x: DesignSystem.Shadow.medium.x, y: DesignSystem.Shadow.medium.y)
                        }
                        
                        EnhancedTabBar(selectedTab: $selectedTab)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(DesignSystem.Animation.springSnappy, value: tabBarVisible)
                }
            }
            .background(DesignSystem.Colors.background)
            .fullScreenCover(isPresented: $showCreateHighlight) {
                CreateHighlightView()
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func offsetForTab(_ tab: Tab) -> CGFloat {
        guard selectedTab != tab else { return 0 }
        
        let currentIndex = Tab.allCases.firstIndex(of: selectedTab) ?? 0
        let tabIndex = Tab.allCases.firstIndex(of: tab) ?? 0
        let indexDifference = tabIndex - currentIndex
        
        return CGFloat(indexDifference) * 20 + dragOffset * 0.3
    }
    
    private func transitionForTab(_ tab: Tab) -> AnyTransition {
        let currentIndex = Tab.allCases.firstIndex(of: selectedTab) ?? 0
        let tabIndex = Tab.allCases.firstIndex(of: tab) ?? 0
        
        if tabIndex < currentIndex {
            return .asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            )
        } else {
            return .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
        }
    }
    
    private func switchToNextTab() {
        let currentIndex = Tab.allCases.firstIndex(of: selectedTab) ?? 0
        let nextIndex = (currentIndex + 1) % Tab.allCases.count
        selectedTab = Tab.allCases[nextIndex]
        HapticManager.shared.impact(.light)
    }
    
    private func switchToPreviousTab() {
        let currentIndex = Tab.allCases.firstIndex(of: selectedTab) ?? 0
        let previousIndex = currentIndex > 0 ? currentIndex - 1 : Tab.allCases.count - 1
        selectedTab = Tab.allCases[previousIndex]
        HapticManager.shared.impact(.light)
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
        .preferredColorScheme(.dark)
}
