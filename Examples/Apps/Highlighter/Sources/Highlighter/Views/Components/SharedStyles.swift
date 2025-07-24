import SwiftUI

// MARK: - Enhanced Zap Button Style
// Specialized button style for zap actions with enhanced visual effects

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

// MARK: - Enhanced View Extensions
extension View {
    func enhancedZapButton() -> some View {
        self.buttonStyle(EnhancedZapButton())
    }
    
    func lazyRender(threshold: CGFloat = 100) -> some View {
        self.modifier(LazyRenderModifier(threshold: threshold))
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