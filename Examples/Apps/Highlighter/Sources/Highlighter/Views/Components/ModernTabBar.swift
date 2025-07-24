import SwiftUI

struct ModernTabBar: View {
    @Binding var selectedTab: ContentView.Tab
    @State private var hapticFeedback = UIImpactFeedbackGenerator(style: .light)
    
    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .background(DesignSystem.Colors.divider)
            
            HStack(spacing: 0) {
                ForEach(ContentView.Tab.allCases, id: \.self) { tab in
                    TabBarButton(
                        tab: tab,
                        isSelected: selectedTab == tab,
                        action: {
                            if selectedTab != tab {
                                hapticFeedback.impactOccurred()
                                withAnimation(DesignSystem.Animation.quick) {
                                    selectedTab = tab
                                }
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.mini)
            .padding(.top, DesignSystem.Spacing.small)
            .padding(.bottom, DesignSystem.Spacing.base)
        }
        .background(
            DesignSystem.Colors.surface
                .ignoresSafeArea()
        )
        .onAppear {
            hapticFeedback.prepare()
        }
    }
}

struct TabBarButton: View {
    let tab: ContentView.Tab
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: iconName)
                    .font(.system(size: 20, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(isSelected ? DesignSystem.Colors.primary : DesignSystem.Colors.textTertiary)
                    .scaleEffect(isSelected ? 1.1 : 1.0)
                    .animation(DesignSystem.Animation.springSnappy, value: isSelected)
                
                Text(title)
                    .font(DesignSystem.Typography.micro)
                    .foregroundColor(isSelected ? DesignSystem.Colors.primary : DesignSystem.Colors.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DesignSystem.Spacing.micro)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var iconName: String {
        switch tab {
        case .home:
            return isSelected ? "house.fill" : "house"
        case .feed:
            return isSelected ? "play.rectangle.fill" : "play.rectangle"
        case .discover:
            return isSelected ? "magnifyingglass.circle.fill" : "magnifyingglass.circle"
        case .library:
            return isSelected ? "books.vertical.fill" : "books.vertical"
        case .profile:
            return isSelected ? "person.crop.circle.fill" : "person.crop.circle"
        }
    }
    
    private var title: String {
        switch tab {
        case .home:
            return "Home"
        case .feed:
            return "Feed"
        case .discover:
            return "Discover"
        case .library:
            return "Library"
        case .profile:
            return "Profile"
        }
    }
}
