import SwiftUI

struct ModernTabBar: View {
    @Binding var selectedTab: ContentView.Tab
    // Using consolidated HapticType from DesignSystem
    
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
                                HapticType.light.trigger()
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
        // Haptic feedback is now handled by HapticType system
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
        isSelected ? tab.filledIcon : tab.icon
    }
    
    private var title: String {
        tab.title
    }
}
