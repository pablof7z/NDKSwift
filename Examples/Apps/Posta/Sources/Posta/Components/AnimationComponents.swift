import SwiftUI

// MARK: - Wave Shape Helper

// Wave shape for background animation
struct WaveShape: Shape {
    var phase: Double
    
    var animatableData: Double {
        get { phase }
        set { phase = newValue }
    }
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height
        let midHeight = height * 0.5
        let wavelength = width / 3
        
        path.move(to: CGPoint(x: 0, y: midHeight))
        
        for x in stride(from: 0, through: width, by: 1) {
            let relativeX = x / wavelength
            let y = Foundation.sin(relativeX * .pi * 2 + phase) * 50 + midHeight
            path.addLine(to: CGPoint(x: x, y: y))
        }
        
        path.addLine(to: CGPoint(x: width, y: height))
        path.addLine(to: CGPoint(x: 0, y: height))
        path.closeSubpath()
        
        return path
    }
}

// MARK: - Glowing Button Style
struct GlowingButtonStyle: ButtonStyle {
    let backgroundColor: Color
    let foregroundColor: Color
    let glowColor: Color
    
    init(
        backgroundColor: Color = .purple,
        foregroundColor: Color = .white,
        glowColor: Color = .purple
    ) {
        self.backgroundColor = backgroundColor
        self.foregroundColor = foregroundColor
        self.glowColor = glowColor
    }
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(foregroundColor)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(
                ZStack {
                    // Glow effect
                    RoundedRectangle(cornerRadius: 16)
                        .fill(glowColor)
                        .blur(radius: configuration.isPressed ? 5 : 10)
                        .opacity(configuration.isPressed ? 0.6 : 0.4)
                    
                    // Main background
                    RoundedRectangle(cornerRadius: 16)
                        .fill(backgroundColor)
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                glowColor.opacity(0.6),
                                glowColor.opacity(0.2)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// Legacy button styles removed - Use PostaPrimaryButtonStyle and PostaSecondaryButtonStyle from DesignSystem.swift instead



// MARK: - Bounce Animation Modifier
struct BounceModifier: ViewModifier {
    @State private var bounce = false
    let delay: Double
    
    func body(content: Content) -> some View {
        content
            .offset(y: bounce ? 0 : -10)
            .animation(
                .interpolatingSpring(stiffness: 300, damping: 10)
                    .delay(delay)
                    .repeatForever(autoreverses: true),
                value: bounce
            )
            .onAppear {
                bounce = true
            }
    }
}

extension View {
    func bouncing(delay: Double = 0) -> some View {
        modifier(BounceModifier(delay: delay))
    }
}

