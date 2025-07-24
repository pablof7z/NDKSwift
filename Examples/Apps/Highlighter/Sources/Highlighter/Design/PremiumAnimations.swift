import SwiftUI

/// Premium animation system for pixel-perfect micro-interactions
/// Provides sophisticated animations that enhance the user experience
struct PremiumAnimations {
    
    // MARK: - Premium Animation Curves
    
    /// Ultra-smooth spring animation for premium feel
    static let premiumSpring = Animation.interpolatingSpring(
        mass: 0.7,
        stiffness: 120,
        damping: 12,
        initialVelocity: 0
    )
    
    /// Quick responsive animation for immediate feedback
    static let quickResponse = Animation.timingCurve(0.2, 0.8, 0.2, 1.0, duration: 0.15)
    
    /// Smooth entrance animation with slight overshoot
    static let smoothEntrance = Animation.timingCurve(0.05, 0.7, 0.1, 1.05, duration: 0.4)
    
    /// Gentle fade with scale for content appearance
    static let gentleFadeScale = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.5)
    
    /// Elastic bounce for playful interactions
    static let elasticBounce = Animation.interpolatingSpring(
        mass: 1.2,
        stiffness: 170,
        damping: 10,
        initialVelocity: 0
    )
    
    // MARK: - Staggered Animation Helpers
    
    /// Create staggered animations for list items
    static func staggered(index: Int, delay: Double = 0.1) -> Animation {
        return smoothEntrance.delay(Double(index) * delay)
    }
    
    /// Create wave-like staggered animations
    static func wave(index: Int, total: Int, duration: Double = 1.0) -> Animation {
        let normalizedIndex = Double(index) / Double(max(total - 1, 1))
        let waveDelay = sin(normalizedIndex * .pi) * 0.3
        return premiumSpring.delay(waveDelay)
    }
}

// MARK: - Premium View Modifiers

/// Adds premium entrance animation with fade and slide
struct PremiumEntranceModifier: ViewModifier {
    let delay: Double
    @State private var isVisible = false
    
    init(delay: Double = 0) {
        self.delay = delay
    }
    
    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 20)
            .scaleEffect(isVisible ? 1 : 0.95)
            .onAppear {
                withAnimation(PremiumAnimations.smoothEntrance.delay(delay)) {
                    isVisible = true
                }
            }
    }
}

/// Adds premium hover effect for interactive elements
struct PremiumHoverModifier: ViewModifier {
    @State private var isHovered = false
    let scale: CGFloat
    let shadowRadius: CGFloat
    
    init(scale: CGFloat = 1.03, shadowRadius: CGFloat = 12) {
        self.scale = scale
        self.shadowRadius = shadowRadius
    }
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered ? scale : 1.0)
            .shadow(
                color: DesignSystem.Colors.primary.opacity(isHovered ? 0.2 : 0.1),
                radius: isHovered ? shadowRadius : 6,
                x: 0,
                y: isHovered ? 6 : 3
            )
            .animation(PremiumAnimations.premiumSpring, value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

/// Adds premium press animation with haptic feedback
struct PremiumPressModifier: ViewModifier {
    @State private var isPressed = false
    let hapticStyle: HapticManager.ImpactStyle
    let scale: CGFloat
    
    init(hapticStyle: HapticManager.ImpactStyle = .light, scale: CGFloat = 0.96) {
        self.hapticStyle = hapticStyle
        self.scale = scale
    }
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? scale : 1.0)
            .opacity(isPressed ? 0.8 : 1.0)
            .animation(PremiumAnimations.quickResponse, value: isPressed)
            .onLongPressGesture(
                minimumDuration: 0,
                maximumDistance: .infinity,
                pressing: { pressing in
                    isPressed = pressing
                    if pressing {
                        HapticManager.shared.impact(hapticStyle)
                    }
                },
                perform: {}
            )
    }
}

/// Adds premium floating animation for FABs and prominent elements
struct PremiumFloatingModifier: ViewModifier {
    @State private var isFloating = false
    let amplitude: CGFloat
    let duration: Double
    
    init(amplitude: CGFloat = 3, duration: Double = 3.0) {
        self.amplitude = amplitude
        self.duration = duration
    }
    
    func body(content: Content) -> some View {
        content
            .offset(y: isFloating ? -amplitude : amplitude)
            .animation(
                .easeInOut(duration: duration).repeatForever(autoreverses: true),
                value: isFloating
            )
            .onAppear {
                isFloating = true
            }
    }
}

/// Adds premium shimmer effect for loading states
struct PremiumShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0
    let duration: Double
    let brightness: Double
    
    init(duration: Double = 1.5, brightness: Double = 0.6) {
        self.duration = duration
        self.brightness = brightness
    }
    
    func body(content: Content) -> some View {
        content
            .overlay(
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.clear,
                                Color.white.opacity(brightness),
                                Color.clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .rotationEffect(.degrees(15))
                    .offset(x: -200 + (phase * 400))
                    .animation(
                        .linear(duration: duration).repeatForever(autoreverses: false),
                        value: phase
                    )
            )
            .clipped()
            .onAppear {
                phase = 1
            }
    }
}

/// Adds premium glow effect for highlights and emphasis
struct PremiumGlowModifier: ViewModifier {
    let color: Color
    let radius: CGFloat
    let isActive: Bool
    
    init(color: Color = DesignSystem.Colors.secondary, radius: CGFloat = 8, isActive: Bool = true) {
        self.color = color
        self.radius = radius
        self.isActive = isActive
    }
    
    func body(content: Content) -> some View {
        content
            .background(
                content
                    .blur(radius: radius / 2)
                    .opacity(isActive ? 0.8 : 0)
                    .blendMode(.multiply)
            )
            .shadow(
                color: color.opacity(isActive ? 0.6 : 0),
                radius: radius,
                x: 0,
                y: 0
            )
            .animation(PremiumAnimations.gentleFadeScale, value: isActive)
    }
}

// MARK: - Premium View Extensions

extension View {
    /// Apply premium entrance animation
    func premiumEntrance(delay: Double = 0) -> some View {
        self.modifier(PremiumEntranceModifier(delay: delay))
    }
    
    /// Apply premium hover effect (macOS only)
    func premiumHover(scale: CGFloat = 1.03, shadowRadius: CGFloat = 12) -> some View {
        #if os(macOS)
        self.modifier(PremiumHoverModifier(scale: scale, shadowRadius: shadowRadius))
        #else
        self
        #endif
    }
    
    /// Apply premium press animation with haptic feedback
    func premiumPress(
        hapticStyle: HapticManager.ImpactStyle = .light,
        scale: CGFloat = 0.96
    ) -> some View {
        self.modifier(PremiumPressModifier(hapticStyle: hapticStyle, scale: scale))
    }
    
    /// Apply premium floating animation
    func premiumFloat(amplitude: CGFloat = 3, duration: Double = 3.0) -> some View {
        self.modifier(PremiumFloatingModifier(amplitude: amplitude, duration: duration))
    }
    
    /// Apply premium shimmer effect
    func premiumShimmer(duration: Double = 1.5, brightness: Double = 0.6) -> some View {
        self.modifier(PremiumShimmerModifier(duration: duration, brightness: brightness))
    }
    
    /// Apply premium glow effect
    func premiumGlow(
        color: Color = DesignSystem.Colors.secondary,
        radius: CGFloat = 8,
        isActive: Bool = true
    ) -> some View {
        self.modifier(PremiumGlowModifier(color: color, radius: radius, isActive: isActive))
    }
    
    /// Apply premium card interaction (combines hover and press)
    func premiumCardInteraction() -> some View {
        self
            .premiumHover()
            .premiumPress()
    }
    
    /// Apply staggered entrance animation for list items
    func staggeredEntrance(index: Int, delay: Double = 0.1) -> some View {
        self
            .opacity(0)
            .offset(y: 20)
            .onAppear {
                withAnimation(PremiumAnimations.staggered(index: index, delay: delay)) {
                    // Note: SwiftUI automatically animates to the view's natural state
                    // when the animation is applied
                }
            }
    }
    
    /// Apply premium scale transition for modals and overlays
    func premiumScaleTransition() -> some View {
        self
            .scaleEffect(1.0)
            .opacity(1.0)
            .transition(
                .asymmetric(
                    insertion: .scale(scale: 0.8).combined(with: .opacity),
                    removal: .scale(scale: 1.1).combined(with: .opacity)
                )
            )
    }
    
    /// Apply premium slide transition with bounce
    func premiumSlideTransition(edge: Edge = .bottom) -> some View {
        self.transition(
            .asymmetric(
                insertion: .move(edge: edge).combined(with: .opacity),
                removal: .move(edge: edge).combined(with: .opacity)
            )
            .animation(PremiumAnimations.elasticBounce)
        )
    }
}

// MARK: - Premium Transition Extensions

extension AnyTransition {
    /// Premium fade with scale
    static var premiumFadeScale: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.9).combined(with: .opacity),
            removal: .scale(scale: 1.1).combined(with: .opacity)
        )
        .animation(PremiumAnimations.gentleFadeScale)
    }
    
    /// Premium slide with overshoot
    static func premiumSlide(from edge: Edge) -> AnyTransition {
        .asymmetric(
            insertion: .move(edge: edge).combined(with: .opacity),
            removal: .move(edge: edge).combined(with: .opacity)
        )
        .animation(PremiumAnimations.smoothEntrance)
    }
    
    /// Premium rotation transition
    static var premiumRotation: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.8).combined(with: .opacity),
            removal: .scale(scale: 1.2).combined(with: .opacity)
        )
        .animation(PremiumAnimations.elasticBounce)
    }
}

// MARK: - Convenience Functions

/// Create a premium loading sequence for multiple elements
func premiumLoadingSequence<T: Hashable>(
    items: [T],
    delay: Double = 0.15
) -> [(item: T, animation: Animation)] {
    return items.enumerated().map { index, item in
        (item: item, animation: PremiumAnimations.staggered(index: index, delay: delay))
    }
}

/// Create a premium wave animation sequence
func premiumWaveSequence<T: Hashable>(
    items: [T],
    duration: Double = 1.0
) -> [(item: T, animation: Animation)] {
    return items.enumerated().map { index, item in
        (item: item, animation: PremiumAnimations.wave(index: index, total: items.count, duration: duration))
    }
}