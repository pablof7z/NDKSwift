import SwiftUI

// MARK: - Design System Colors
struct PostaColors {
    // Primary gradient colors
    static let primaryGradient = Gradient(colors: [
        Color(red: 0.6, green: 0.2, blue: 0.9),  // Purple
        Color(red: 0.8, green: 0.3, blue: 0.6),  // Pink
        Color(red: 0.9, green: 0.4, blue: 0.5)   // Coral
    ])
    
    // Secondary gradient colors
    static let secondaryGradient = Gradient(colors: [
        Color(red: 0.2, green: 0.6, blue: 0.9),  // Blue
        Color(red: 0.3, green: 0.8, blue: 0.8),  // Cyan
    ])
    
    // Dark gradient background
    static let darkBackgroundGradient = Gradient(colors: [
        Color(red: 0.05, green: 0.02, blue: 0.08),
        Color(red: 0.02, green: 0.01, blue: 0.04),
        Color.black
    ])
    
    // Accent colors
    static let electricPurple = Color(red: 0.7, green: 0.3, blue: 0.9)
    static let glowPink = Color(red: 0.9, green: 0.3, blue: 0.6)
    static let neonBlue = Color(red: 0.3, green: 0.6, blue: 1.0)
    
    // UI colors
    static let surfaceColor = Color.white.opacity(0.08)
    static let borderColor = Color.white.opacity(0.2)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.7)
    static let textTertiary = Color.white.opacity(0.5)
}

// MARK: - Button Styles
struct PostaPrimaryButtonStyle: ButtonStyle {
    let isEnabled: Bool
    
    init(isEnabled: Bool = true) {
        self.isEnabled = isEnabled
    }
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                LinearGradient(
                    gradient: isEnabled ? PostaColors.primaryGradient : Gradient(colors: [Color.gray, Color.gray.opacity(0.8)]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(
                color: isEnabled ? PostaColors.electricPurple.opacity(0.3) : Color.clear,
                radius: configuration.isPressed ? 5 : 10,
                x: 0,
                y: configuration.isPressed ? 2 : 4
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

struct PostaSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(PostaColors.surfaceColor)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        LinearGradient(
                            gradient: PostaColors.primaryGradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 1.5
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

struct PostaTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(PostaColors.textSecondary)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Text Field Styles
struct PostaTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.system(size: 16))
            .padding(18)
            .background(PostaColors.surfaceColor)
            .foregroundColor(.white)
            .accentColor(PostaColors.electricPurple)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(PostaColors.borderColor, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Card Styles
struct PostaCardBackground: ViewModifier {
    let isHighlighted: Bool
    
    init(isHighlighted: Bool = false) {
        self.isHighlighted = isHighlighted
    }
    
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(PostaColors.surfaceColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(
                                isHighlighted ? 
                                LinearGradient(gradient: PostaColors.primaryGradient, startPoint: .topLeading, endPoint: .bottomTrailing) :
                                LinearGradient(gradient: Gradient(colors: [PostaColors.borderColor]), startPoint: .leading, endPoint: .trailing),
                                lineWidth: isHighlighted ? 1.5 : 1
                            )
                    )
                    .shadow(
                        color: isHighlighted ? PostaColors.electricPurple.opacity(0.2) : Color.black.opacity(0.3),
                        radius: isHighlighted ? 15 : 8,
                        x: 0,
                        y: isHighlighted ? 8 : 4
                    )
            )
    }
}

// MARK: - Glow Effects
struct PostaGlowEffect: ViewModifier {
    let color: Color
    let radius: CGFloat
    
    init(color: Color = PostaColors.electricPurple, radius: CGFloat = 20) {
        self.color = color
        self.radius = radius
    }
    
    func body(content: Content) -> some View {
        content
            .background(
                content
                    .blur(radius: radius)
                    .opacity(0.5)
                    .blendMode(.plusLighter)
            )
    }
}

// MARK: - Animation Helpers
struct PostaPulseAnimation: ViewModifier {
    @State private var scale: CGFloat = 1
    let minScale: CGFloat
    let maxScale: CGFloat
    let duration: Double
    
    init(minScale: CGFloat = 0.95, maxScale: CGFloat = 1.05, duration: Double = 2) {
        self.minScale = minScale
        self.maxScale = maxScale
        self.duration = duration
    }
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .onAppear {
                withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: true)) {
                    scale = maxScale
                }
            }
    }
}

struct PostaShimmerEffect: ViewModifier {
    @State private var phase: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.white.opacity(0),
                        Color.white.opacity(0.3),
                        Color.white.opacity(0)
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .rotationEffect(.degrees(20))
                .offset(x: phase * 400 - 200)
                .mask(content)
                .allowsHitTesting(false)
            )
            .onAppear {
                withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

// MARK: - View Extensions
extension View {
    func postaCard(isHighlighted: Bool = false) -> some View {
        modifier(PostaCardBackground(isHighlighted: isHighlighted))
    }
    
    func postaGlow(_ color: Color = PostaColors.electricPurple, radius: CGFloat = 20) -> some View {
        modifier(PostaGlowEffect(color: color, radius: radius))
    }
    
    func postaPulse(minScale: CGFloat = 0.95, maxScale: CGFloat = 1.05, duration: Double = 2) -> some View {
        modifier(PostaPulseAnimation(minScale: minScale, maxScale: maxScale, duration: duration))
    }
    
    func postaShimmer() -> some View {
        modifier(PostaShimmerEffect())
    }
}

// MARK: - Common Components
struct PostaSectionHeader: View {
    let title: String
    let subtitle: String?
    
    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(PostaColors.textPrimary)
            
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.system(size: 16))
                    .foregroundColor(PostaColors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PostaLoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: PostaColors.electricPurple))
                .scaleEffect(1.2)
            
            Text("Loading...")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(PostaColors.textSecondary)
        }
        .padding(40)
        .postaCard()
    }
}

// MARK: - Background Patterns
struct PostaBackgroundView: View {
    @State private var animationPhase: CGFloat = 0
    
    var body: some View {
        ZStack {
            // Base gradient
            LinearGradient(
                gradient: PostaColors.darkBackgroundGradient,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // Animated mesh gradient overlay
            GeometryReader { geometry in
                ForEach(0..<3) { index in
                    Circle()
                        .fill(
                            RadialGradient(
                                gradient: Gradient(colors: [
                                    PostaColors.electricPurple.opacity(0.3),
                                    PostaColors.glowPink.opacity(0.2),
                                    Color.clear
                                ]),
                                center: .center,
                                startRadius: 50,
                                endRadius: 200
                            )
                        )
                        .frame(width: 300, height: 300)
                        .blur(radius: 40)
                        .offset(
                            x: Foundation.cos(animationPhase + Double(index) * 2) * geometry.size.width * 0.3,
                            y: Foundation.sin(animationPhase + Double(index) * 2) * geometry.size.height * 0.3
                        )
                }
            }
            .onAppear {
                withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
                    animationPhase = .pi * 2
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Electric Effect Shape
struct ElectricField: Shape {
    let points: Int
    
    init(points: Int = 5) {
        self.points = points
    }
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        
        for i in 0..<points {
            let angle = Double(i) * (2 * .pi / Double(points))
            let endPoint = CGPoint(
                x: center.x + Foundation.cos(angle) * rect.width * 0.4,
                y: center.y + Foundation.sin(angle) * rect.height * 0.4
            )
            
            path.move(to: center)
            
            // Create jagged lightning path
            let segments = 6
            var currentPoint = center
            
            for j in 1...segments {
                let progress = CGFloat(j) / CGFloat(segments)
                let baseX = center.x + (endPoint.x - center.x) * progress
                let baseY = center.y + (endPoint.y - center.y) * progress
                
                let offsetRange: CGFloat = j == segments ? 0 : 15
                let offsetX = CGFloat.random(in: -offsetRange...offsetRange)
                let offsetY = CGFloat.random(in: -offsetRange...offsetRange)
                
                let nextPoint = CGPoint(x: baseX + offsetX, y: baseY + offsetY)
                path.addLine(to: j == segments ? endPoint : nextPoint)
                currentPoint = nextPoint
            }
        }
        
        return path
    }
}

// MARK: - Electric Field View
struct ElectricFieldView: View {
    @State private var regenerateTrigger = false
    @State private var opacity: Double = 0
    
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.5)) { timeline in
            Canvas { context, size in
                for _ in 0..<3 {
                    var electricPath = Path()
                    let field = ElectricField(points: Int.random(in: 4...7))
                    electricPath = field.path(in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
                    
                    context.stroke(
                        electricPath,
                        with: .linearGradient(
                            Gradient(colors: [
                                PostaColors.electricPurple,
                                PostaColors.glowPink,
                                PostaColors.neonBlue
                            ]),
                            startPoint: CGPoint(x: 0, y: 0),
                            endPoint: CGPoint(x: size.width, y: size.height)
                        ),
                        lineWidth: 2
                    )
                }
            }
            .blur(radius: 3)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeIn(duration: 0.3)) {
                    opacity = 1
                }
            }
            .onChange(of: timeline.date) { _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    opacity = 0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    withAnimation(.easeIn(duration: 0.3)) {
                        opacity = 1
                    }
                }
            }
        }
    }
}