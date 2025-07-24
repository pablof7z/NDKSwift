import SwiftUI

// MARK: - Legacy Color Extensions (for backward compatibility)
// These are deprecated - use DesignSystem.Colors instead
extension Color {
    // Primary Colors - mapped to DesignSystem
    static let highlighterPurple = DesignSystem.Colors.primary
    static let highlighterOrange = DesignSystem.Colors.secondary
    
    // Background Colors - mapped to DesignSystem  
    static let highlighterBackground = DesignSystem.Colors.background
    static let highlighterCardBackground = DesignSystem.Colors.surface
    static let highlighterDarkBackground = DesignSystem.Colors.darkBackground
    static let highlighterDarkCard = DesignSystem.Colors.darkSurface
    
    // Text Colors - mapped to DesignSystem
    static let highlighterText = DesignSystem.Colors.text
    static let highlighterSecondaryText = DesignSystem.Colors.textSecondary
    static let highlighterDarkText = DesignSystem.Colors.darkText
    
    // Accent Colors - mapped to DesignSystem
    static let highlighterSuccess = DesignSystem.Colors.success
    static let highlighterWarning = DesignSystem.Colors.warning
    static let highlighterError = DesignSystem.Colors.error
}

// MARK: - View Modifiers

struct CardStyle: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    
    func body(content: Content) -> some View {
        content
            .background(
                colorScheme == .dark ? 
                DesignSystem.Colors.darkSurface : 
                DesignSystem.Colors.surface
            )
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large, style: .continuous))
            .shadow(
                color: DesignSystem.Shadow.small.color,
                radius: DesignSystem.Shadow.small.radius,
                x: DesignSystem.Shadow.small.x,
                y: DesignSystem.Shadow.small.y
            )
    }
}

struct HighlightCardStyle: ViewModifier {
    let isSelected: Bool
    
    func body(content: Content) -> some View {
        content
            .padding(DesignSystem.Spacing.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large, style: .continuous)
                    .fill(DesignSystem.Colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large, style: .continuous)
                            .stroke(
                                isSelected ? DesignSystem.Colors.secondary : Color.clear, 
                                lineWidth: 2
                            )
                    )
            )
            .shadow(
                color: isSelected ? DesignSystem.Colors.secondary.opacity(0.3) : DesignSystem.Shadow.small.color,
                radius: isSelected ? 12 : DesignSystem.Shadow.small.radius,
                x: 0,
                y: isSelected ? 4 : DesignSystem.Shadow.small.y
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .animation(DesignSystem.Animation.springSnappy, value: isSelected)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignSystem.Typography.headline)
            .foregroundColor(.white)
            .padding(.horizontal, DesignSystem.Spacing.xl)
            .padding(.vertical, DesignSystem.Spacing.medium)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium, style: .continuous)
                    .fill(DesignSystem.Colors.primary)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(DesignSystem.Animation.interactive, value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignSystem.Typography.bodyMedium)
            .foregroundColor(DesignSystem.Colors.primary)
            .padding(.horizontal, DesignSystem.Spacing.xl)
            .padding(.vertical, DesignSystem.Spacing.medium)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium, style: .continuous)
                    .stroke(DesignSystem.Colors.primary, lineWidth: 2)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(DesignSystem.Animation.interactive, value: configuration.isPressed)
    }
}

struct ZapButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignSystem.Typography.callout)
            .fontWeight(.medium)
            .foregroundColor(.white)
            .padding(.horizontal, DesignSystem.Spacing.medium)
            .padding(.vertical, DesignSystem.Spacing.small)
            .background(
                Capsule()
                    .fill(DesignSystem.Colors.secondary)
            )
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(DesignSystem.Animation.interactive, value: configuration.isPressed)
    }
}

// MARK: - Extensions

extension View {
    func cardStyle() -> some View {
        modifier(CardStyle())
    }
    
    func highlightCard(isSelected: Bool = false) -> some View {
        modifier(HighlightCardStyle(isSelected: isSelected))
    }
    
    func pulse() -> some View {
        modifier(PulseModifier())
    }
    
    func rotateAndScale(isActive: Bool) -> some View {
        modifier(RotateAndScaleModifier(isActive: isActive))
    }
}

// MARK: - Haptic Feedback (Deprecated - use HapticType from DesignSystem)
// HapticType is now defined in DesignSystem.swift

// MARK: - Typography (Legacy - use DesignSystem.Typography instead)
extension Font {
    static let highlighterTitle = DesignSystem.Typography.title
    static let highlighterHeadline = DesignSystem.Typography.headline  
    static let highlighterBody = DesignSystem.Typography.body
    static let highlighterCaption = DesignSystem.Typography.caption
    static let highlighterQuote = Font.custom("Georgia", size: 18).italic()
}

// MARK: - Animations (Legacy - use DesignSystem.Animation instead) 
extension Animation {
    static let highlighterSpring = DesignSystem.Animation.springSnappy
    static let highlighterEase = DesignSystem.Animation.standard
}

// MARK: - Additional Components

struct PressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Legacy Components (Cleaned up following YAGNI principles)
// Removed unused components: LoadingDots, AnimatedGradientBackground, CustomTabBar, TabBarItem
// Consolidated duplicate design systems into single DesignSystem.swift

// MARK: - Additional Modifiers

struct PulseModifier: ViewModifier {
    @State private var scale: CGFloat = 1
    @State private var opacity: Double = 1
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                    scale = 1.05
                    opacity = 0.8
                }
            }
    }
}

struct RotateAndScaleModifier: ViewModifier {
    @State private var rotation: Double = 0
    @State private var scale: CGFloat = 1
    let isActive: Bool
    
    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(isActive ? rotation : 0))
            .scaleEffect(isActive ? scale : 1)
            .onChange(of: isActive) { oldValue, newValue in
                if newValue {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.5)) {
                        rotation = 360
                        scale = 1.2
                    }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6).delay(0.3)) {
                        scale = 1.0
                    }
                } else {
                    rotation = 0
                }
            }
    }
}

// MARK: - Enhanced Card Modifier (Deprecated - use cardBackground() from DesignSystem)
struct EnhancedCardModifier: ViewModifier {
    let isSelected: Bool
    
    func body(content: Content) -> some View {
        content.cardBackground(isSelected: isSelected)
    }
}
