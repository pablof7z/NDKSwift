import SwiftUI

// MARK: - Modern View Modifiers
// Clean, sophisticated components without excessive effects

// MARK: - Card Styles
struct ModernCard: ViewModifier {
    var noPadding: Bool = false
    var isInteractive: Bool = false
    
    func body(content: Content) -> some View {
        content
            .padding(noPadding ? 0 : DesignSystem.Spacing.cardPadding)
            .background(DesignSystem.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium, style: .continuous))
            .shadow(
                color: DesignSystem.Shadow.small.color,
                radius: DesignSystem.Shadow.small.radius,
                x: DesignSystem.Shadow.small.x,
                y: DesignSystem.Shadow.small.y
            )
    }
}

struct ModernCardSelected: ViewModifier {
    let isSelected: Bool
    
    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium, style: .continuous)
                    .stroke(isSelected ? DesignSystem.Colors.primary : Color.clear, lineWidth: 2)
                    .animation(DesignSystem.Animation.quick, value: isSelected)
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .animation(DesignSystem.Animation.springSnappy, value: isSelected)
    }
}

// MARK: - Button Styles
struct ModernPrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.ds.bodyMedium)
            .foregroundColor(.white)
            .padding(.horizontal, .ds.large)
            .padding(.vertical, .ds.base)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium, style: .continuous)
                    .fill(DesignSystem.Colors.primary)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(DesignSystem.Animation.instant, value: configuration.isPressed)
    }
}

struct ModernSecondaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.ds.bodyMedium)
            .foregroundColor(DesignSystem.Colors.primary)
            .padding(.horizontal, .ds.large)
            .padding(.vertical, .ds.base)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium, style: .continuous)
                    .fill(DesignSystem.Colors.primaryLight.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium, style: .continuous)
                    .stroke(DesignSystem.Colors.primary.opacity(0.2), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(DesignSystem.Animation.instant, value: configuration.isPressed)
    }
}

struct ModernGhostButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.ds.bodyMedium)
            .foregroundColor(DesignSystem.Colors.primary)
            .padding(.horizontal, .ds.medium)
            .padding(.vertical, .ds.small)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small, style: .continuous)
                    .fill(configuration.isPressed ? DesignSystem.Colors.primary.opacity(0.05) : Color.clear)
            )
            .animation(DesignSystem.Animation.instant, value: configuration.isPressed)
    }
}

// MARK: - List Item Style
struct ModernListItem: ViewModifier {
    var showDivider: Bool = true
    
    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            content
                .padding(.vertical, .ds.base)
                .padding(.horizontal, .ds.screenPadding)
            
            if showDivider {
                Divider()
                    .background(DesignSystem.Colors.divider)
                    .padding(.leading, .ds.screenPadding)
            }
        }
    }
}

// MARK: - Input Styles
struct ModernTextField: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.ds.base)
            .background(DesignSystem.Colors.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small, style: .continuous)
                    .stroke(DesignSystem.Colors.border, lineWidth: 1)
            )
    }
}

// MARK: - Modern Tab Bar Item
struct ModernTabItem: View {
    let icon: String
    let title: String
    let isSelected: Bool
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(isSelected ? DesignSystem.Colors.primary : DesignSystem.Colors.textTertiary)
                .scaleEffect(isSelected ? 1.1 : 1.0)
                .animation(DesignSystem.Animation.springSnappy, value: isSelected)
            
            Text(title)
                .font(.ds.micro)
                .foregroundColor(isSelected ? DesignSystem.Colors.primary : DesignSystem.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Modern Section Header
struct ModernSectionHeader: View {
    let title: String
    var action: (() -> Void)? = nil
    var actionTitle: String? = nil
    
    var body: some View {
        HStack {
            Text(title)
                .font(.ds.title3)
                .foregroundColor(.ds.text)
            
            Spacer()
            
            if let action = action, let actionTitle = actionTitle {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.ds.footnoteMedium)
                        .foregroundColor(.ds.primary)
                }
            }
        }
        .padding(.horizontal, .ds.screenPadding)
        .padding(.vertical, .ds.small)
    }
}

// MARK: - Highlight Effect (Subtle)
struct ModernHighlight: ViewModifier {
    let isHighlighted: Bool
    
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.micro, style: .continuous)
                    .fill(isHighlighted ? DesignSystem.Colors.highlightSubtle : Color.clear)
                    .animation(DesignSystem.Animation.quick, value: isHighlighted)
            )
    }
}

// MARK: - Loading Placeholder
struct ModernPlaceholder: ViewModifier {
    @State private var opacity: Double = 0.5
    
    func body(content: Content) -> some View {
        content
            .redacted(reason: .placeholder)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    opacity = 0.8
                }
            }
    }
}

// MARK: - View Extensions
extension View {
    func modernCard(noPadding: Bool = false) -> some View {
        self.modifier(ModernCard(noPadding: noPadding))
    }
    
    func modernCardSelected(_ isSelected: Bool) -> some View {
        self.modifier(ModernCardSelected(isSelected: isSelected))
    }
    
    func modernListItem(showDivider: Bool = true) -> some View {
        self.modifier(ModernListItem(showDivider: showDivider))
    }
    
    func modernTextField() -> some View {
        self.modifier(ModernTextField())
    }
    
    func modernHighlight(_ isHighlighted: Bool) -> some View {
        self.modifier(ModernHighlight(isHighlighted: isHighlighted))
    }
    
    func modernPlaceholder() -> some View {
        self.modifier(ModernPlaceholder())
    }
}

// MARK: - Modern Empty State
struct ModernEmptyState: View {
    let icon: String
    let title: String
    let message: String
    var action: (() -> Void)? = nil
    var actionTitle: String? = nil
    
    var body: some View {
        VStack(spacing: .ds.medium) {
            Image(systemName: icon)
                .font(.system(size: 48, weight: .light))
                .foregroundColor(.ds.textTertiary)
            
            VStack(spacing: .ds.small) {
                Text(title)
                    .font(.ds.headline)
                    .foregroundColor(.ds.text)
                
                Text(message)
                    .font(.ds.body)
                    .foregroundColor(.ds.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            if let action = action, let actionTitle = actionTitle {
                Button(action: action) {
                    Text(actionTitle)
                }
                .buttonStyle(ModernPrimaryButton())
                .padding(.top, .ds.small)
            }
        }
        .padding(.ds.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
