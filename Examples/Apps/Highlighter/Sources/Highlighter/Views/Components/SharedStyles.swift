import SwiftUI

// MARK: - Enhanced Components
// Additional components that extend the DesignSystem

// MARK: - Specialized Button Styles (complement ModernViewModifiers)

// Enhanced Zap Button with haptic feedback and visual effects
struct EnhancedZapButton: ButtonStyle {
    @State private var isAnimating = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.ds.callout)
            .fontWeight(.medium)
            .foregroundColor(.white)
            .padding(.horizontal, .ds.medium)
            .padding(.vertical, .ds.small)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                DesignSystem.Colors.secondary,
                                DesignSystem.Colors.secondaryDark
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        Capsule()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.3),
                                        Color.clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.95 : (isAnimating ? 1.05 : 1.0))
            .shadow(
                color: DesignSystem.Colors.secondary.opacity(0.4),
                radius: configuration.isPressed ? 2 : 4,
                x: 0,
                y: configuration.isPressed ? 1 : 2
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
            .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: isAnimating)
            .onAppear {
                isAnimating = true
            }
            .onChange(of: configuration.isPressed) { _, newValue in
                if newValue {
                    HapticType.medium.trigger()
                }
            }
    }
}

// Enhanced Card Style with better visual hierarchy
struct EnhancedHighlightCard: ViewModifier {
    let isSelected: Bool
    let isHighlighted: Bool
    
    func body(content: Content) -> some View {
        content
            .padding(.ds.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: .ds.large, style: .continuous)
                    .fill(DesignSystem.Colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: .ds.large, style: .continuous)
                            .stroke(
                                strokeGradient,
                                lineWidth: strokeWidth
                            )
                    )
            )
            .shadow(
                color: shadowColor,
                radius: shadowRadius,
                x: 0,
                y: shadowY
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .opacity(isSelected ? 1.0 : 0.95)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
    
    private var strokeGradient: LinearGradient {
        if isSelected {
            return LinearGradient(
                colors: [DesignSystem.Colors.secondary, DesignSystem.Colors.primary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else if isHighlighted {
            return LinearGradient(
                colors: [DesignSystem.Colors.secondary.opacity(0.3), Color.clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                colors: [DesignSystem.Colors.border, DesignSystem.Colors.border],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
    
    private var strokeWidth: CGFloat {
        isSelected ? 2 : (isHighlighted ? 1.5 : 1)
    }
    
    private var shadowColor: Color {
        if isSelected {
            return DesignSystem.Colors.secondary.opacity(0.3)
        } else {
            return Color.black.opacity(0.08)
        }
    }
    
    private var shadowRadius: CGFloat {
        isSelected ? 12 : 8
    }
    
    private var shadowY: CGFloat {
        isSelected ? 6 : 4
    }
}

// MARK: - View Extensions

extension View {
    func enhancedZapButton() -> some View {
        self.buttonStyle(EnhancedZapButton())
    }
    
    func enhancedHighlightCard(isSelected: Bool = false, isHighlighted: Bool = false) -> some View {
        self.modifier(EnhancedHighlightCard(isSelected: isSelected, isHighlighted: isHighlighted))
    }
    
    func pulseGently() -> some View {
        self.modifier(GentlePulseModifier())
    }
    
    func contextualFeedback(isActive: Bool) -> some View {
        self.modifier(ContextualFeedbackModifier(isActive: isActive))
    }
}

// MARK: - Specialized Typography
extension Font {
    // Specialized quote font for highlighted text
    static let highlighterQuote = Font.custom("Georgia", size: 18).italic()
    
    // Dynamic quote sizing based on content length
    static func dynamicQuote(for length: Int) -> Font {
        let size: CGFloat = length > 100 ? 16 : (length > 50 ? 17 : 18)
        return Font.custom("Georgia", size: size).italic()
    }
}

// MARK: - Contextual Components

// Subtle feedback for interactive elements
struct ContextualFeedbackModifier: ViewModifier {
    let isActive: Bool
    @State private var feedbackScale: CGFloat = 1.0
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(feedbackScale)
            .onChange(of: isActive) { _, newValue in
                if newValue {
                    withAnimation(.spring(response: 0.15, dampingFraction: 0.8)) {
                        feedbackScale = 1.02
                    }
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                            feedbackScale = 1.0
                        }
                    }
                    
                    HapticType.selection.trigger()
                }
            }
    }
}

// MARK: - Refined Animation Modifiers

// Gentle pulse for attention without being distracting
struct GentlePulseModifier: ViewModifier {
    @State private var scale: CGFloat = 1
    @State private var opacity: Double = 1
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 2.5)
                    .repeatForever(autoreverses: true)
                ) {
                    scale = 1.02
                    opacity = 0.9
                }
            }
    }
}

// Refined highlight effect for text selections
struct HighlightTextEffect: ViewModifier {
    let isHighlighted: Bool
    let highlightColor: Color
    
    init(isHighlighted: Bool, highlightColor: Color = DesignSystem.Colors.secondary) {
        self.isHighlighted = isHighlighted
        self.highlightColor = highlightColor
    }
    
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(
                        isHighlighted ? 
                        highlightColor.opacity(0.15) : 
                        Color.clear
                    )
                    .animation(.easeInOut(duration: 0.2), value: isHighlighted)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(
                        isHighlighted ? 
                        highlightColor.opacity(0.3) : 
                        Color.clear,
                        lineWidth: 1
                    )
                    .animation(.easeInOut(duration: 0.2), value: isHighlighted)
            )
    }
}

extension View {
    func highlightText(_ isHighlighted: Bool, color: Color = DesignSystem.Colors.secondary) -> some View {
        self.modifier(HighlightTextEffect(isHighlighted: isHighlighted, highlightColor: color))
    }
}

// MARK: - Performance Optimizations

// Lazy loading modifier for better scroll performance
struct LazyRenderModifier: ViewModifier {
    let threshold: CGFloat
    @State private var isVisible = false
    
    init(threshold: CGFloat = 100) {
        self.threshold = threshold
        self.isVisible = false
    }
    
    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .onAppear {
                withAnimation(.easeIn(duration: 0.2)) {
                    isVisible = true
                }
            }
    }
}

extension View {
    func lazyRender(threshold: CGFloat = 100) -> some View {
        self.modifier(LazyRenderModifier(threshold: threshold))
    }
}