import SwiftUI

/// Modern, unified card component following Highlighter's design system
/// Supports multiple variants and interaction states for consistent UI
struct ModernCard<Content: View>: View {
    let content: Content
    let variant: CardVariant
    let isSelected: Bool
    let isHighlighted: Bool
    let action: (() -> Void)?
    
    @State private var isPressed = false
    @State private var hovering = false
    
    init(
        variant: CardVariant = .standard,
        isSelected: Bool = false,
        isHighlighted: Bool = false,
        action: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.variant = variant
        self.isSelected = isSelected
        self.isHighlighted = isHighlighted
        self.action = action
        self.content = content()
    }
    
    var body: some View {
        Group {
            if let action = action {
                Button(action: {
                    HapticManager.shared.cardTap()
                    action()
                }) {
                    cardContent
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                cardContent
            }
        }
    }
    
    private var cardContent: some View {
        content
            .padding(variant.padding)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: variant.cornerRadius, style: .continuous))
            .overlay(cardBorder)
            .shadow(
                color: shadowColor,
                radius: shadowRadius,
                x: 0,
                y: shadowOffset
            )
            .scaleEffect(scaleValue)
            .opacity(opacityValue)
            .animation(DesignSystem.Animation.springSnappy, value: isSelected)
            .animation(DesignSystem.Animation.quick, value: isPressed)
            .animation(DesignSystem.Animation.quick, value: hovering)
            .onLongPressGesture(
                minimumDuration: 0,
                maximumDistance: .infinity,
                pressing: { pressing in
                    if action != nil {
                        withAnimation(DesignSystem.Animation.quick) {
                            isPressed = pressing
                        }
                    }
                },
                perform: {}
            )
            .onHover { hovering in
                #if os(macOS) // Only enable hover on macOS
                withAnimation(DesignSystem.Animation.quick) {
                    self.hovering = hovering
                }
                #endif
            }
    }
    
    // MARK: - Computed Properties
    
    private var cardBackground: some View {
        Group {
            switch variant {
            case .standard, .compact, .elevated:
                RoundedRectangle(cornerRadius: variant.cornerRadius, style: .continuous)
                    .fill(DesignSystem.Colors.surface)
            case .glass:
                RoundedRectangle(cornerRadius: variant.cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
            case .highlighted:
                RoundedRectangle(cornerRadius: variant.cornerRadius, style: .continuous)
                    .fill(DesignSystem.Colors.highlightSubtle.opacity(0.3))
            case .primary:
                RoundedRectangle(cornerRadius: variant.cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                DesignSystem.Colors.primary.opacity(0.1),
                                DesignSystem.Colors.primary.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        }
    }
    
    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: variant.cornerRadius, style: .continuous)
            .stroke(borderGradient, lineWidth: borderWidth)
    }
    
    private var borderGradient: LinearGradient {
        if isSelected {
            return LinearGradient(
                colors: [
                    DesignSystem.Colors.secondary,
                    DesignSystem.Colors.primary
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else if isHighlighted {
            return LinearGradient(
                colors: [
                    DesignSystem.Colors.secondary.opacity(0.4),
                    DesignSystem.Colors.secondary.opacity(0.2)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else if variant == .glass {
            return LinearGradient(
                colors: [
                    Color.white.opacity(0.3),
                    Color.white.opacity(0.1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                colors: [
                    DesignSystem.Colors.border,
                    DesignSystem.Colors.border.opacity(0.5)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    private var borderWidth: CGFloat {
        if isSelected { return 2.0 }
        else if isHighlighted { return 1.5 }
        else { return 1.0 }
    }
    
    private var shadowColor: Color {
        if isSelected {
            return DesignSystem.Colors.secondary.opacity(0.3)
        } else if variant == .elevated {
            return Color.black.opacity(0.12)
        } else {
            return variant.shadowColor
        }
    }
    
    private var shadowRadius: CGFloat {
        if isSelected { return 12 }
        else if isPressed { return variant.shadowRadius * 0.5 }
        else { return variant.shadowRadius }
    }
    
    private var shadowOffset: CGFloat {
        if isSelected { return 6 }
        else if isPressed { return variant.shadowOffset * 0.5 }
        else { return variant.shadowOffset }
    }
    
    private var scaleValue: CGFloat {
        if isSelected { return 1.02 }
        else if isPressed { return 0.98 }
        else if hovering { return 1.01 }
        else { return 1.0 }
    }
    
    private var opacityValue: Double {
        if isPressed { return 0.85 }
        else { return 1.0 }
    }
}

// MARK: - Card Variants

enum CardVariant {
    case standard
    case compact
    case elevated
    case glass
    case highlighted
    case primary
    
    var cornerRadius: CGFloat {
        switch self {
        case .standard, .elevated, .primary:
            return DesignSystem.CornerRadius.large
        case .compact:
            return DesignSystem.CornerRadius.medium
        case .glass, .highlighted:
            return DesignSystem.CornerRadius.medium
        }
    }
    
    var padding: CGFloat {
        switch self {
        case .standard, .elevated, .glass, .highlighted, .primary:
            return DesignSystem.Spacing.cardPadding
        case .compact:
            return DesignSystem.Spacing.base
        }
    }
    
    var shadowColor: Color {
        switch self {
        case .standard, .compact:
            return DesignSystem.Shadow.small.color
        case .elevated:
            return DesignSystem.Shadow.medium.color
        case .glass:
            return Color.black.opacity(0.1)
        case .highlighted:
            return DesignSystem.Colors.secondary.opacity(0.2)
        case .primary:
            return DesignSystem.Colors.primary.opacity(0.2)
        }
    }
    
    var shadowRadius: CGFloat {
        switch self {
        case .standard, .compact:
            return DesignSystem.Shadow.small.radius
        case .elevated:
            return DesignSystem.Shadow.medium.radius
        case .glass:
            return 8
        case .highlighted, .primary:
            return 6
        }
    }
    
    var shadowOffset: CGFloat {
        switch self {
        case .standard, .compact:
            return DesignSystem.Shadow.small.y
        case .elevated:
            return DesignSystem.Shadow.medium.y
        case .glass, .highlighted, .primary:
            return 4
        }
    }
}

// MARK: - Convenience View Extensions

extension View {
    /// Apply the modern card style with optional interaction
    func modernCard(
        variant: CardVariant = .standard,
        isSelected: Bool = false,
        isHighlighted: Bool = false,
        action: (() -> Void)? = nil
    ) -> some View {
        ModernCard(
            variant: variant,
            isSelected: isSelected,
            isHighlighted: isHighlighted,
            action: action
        ) {
            self
        }
    }
    
    /// Apply a tappable modern card style
    func tappableCard(
        variant: CardVariant = .standard,
        isSelected: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        modernCard(
            variant: variant,
            isSelected: isSelected,
            action: action
        )
    }
    
    /// Apply a highlighted card style for featured content
    func highlightCard(isSelected: Bool = false) -> some View {
        modernCard(variant: .highlighted, isSelected: isSelected)
    }
    
    /// Apply a glass card style for overlay content
    func glassCard() -> some View {
        modernCard(variant: .glass)
    }
    
    /// Apply an elevated card style for important content
    func elevatedCard(isSelected: Bool = false) -> some View {
        modernCard(variant: .elevated, isSelected: isSelected)
    }
}

// MARK: - Preview

#Preview("Card Variants") {
    ScrollView {
        LazyVStack(spacing: DesignSystem.Spacing.medium) {
            ForEach(["Standard", "Compact", "Elevated", "Glass", "Highlighted", "Primary"], id: \.self) { title in
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                    Text("Sample Content")
                        .font(DesignSystem.Typography.headline)
                        .foregroundColor(DesignSystem.Colors.text)
                    
                    Text("This is a sample card showing the \(title.lowercased()) variant with some content to demonstrate the styling and spacing.")
                        .font(DesignSystem.Typography.body)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .lineLimit(3)
                }
                .modernCard(variant: cardVariant(for: title))
            }
        }
        .padding(DesignSystem.Spacing.screenPadding)
    }
    .background(DesignSystem.Colors.background)
}

private func cardVariant(for title: String) -> CardVariant {
    switch title {
    case "Standard": return .standard
    case "Compact": return .compact
    case "Elevated": return .elevated
    case "Glass": return .glass
    case "Highlighted": return .highlighted
    case "Primary": return .primary
    default: return .standard
    }
}