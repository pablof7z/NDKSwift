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
            let y = sin(relativeX * .pi * 2 + phase) * 50 + midHeight
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

// MARK: - Gradient Button Style
struct GradientButtonStyle: ButtonStyle {
    let gradient: LinearGradient
    let shadowColor: Color
    
    init(colors: [Color], shadowColor: Color? = nil) {
        self.gradient = LinearGradient(
            gradient: Gradient(colors: colors),
            startPoint: .leading,
            endPoint: .trailing
        )
        self.shadowColor = shadowColor ?? colors.first ?? .clear
    }
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white)
            .font(.system(size: 18, weight: .semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(gradient)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: shadowColor.opacity(0.3), radius: 10, x: 0, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Outline Button Style
struct OutlineButtonStyle: ButtonStyle {
    let color: Color
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(color)
            .font(.system(size: 18, weight: .semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(color.opacity(0.1))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(color.opacity(0.3), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}



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

