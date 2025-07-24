import SwiftUI

// MARK: - Modern Animation Library
// Enhanced animations for a pixel-perfect, professional feel

// MARK: - Hero Animations
struct HeroScale: ViewModifier {
    let isActive: Bool
    let scale: CGFloat
    
    init(isActive: Bool, scale: CGFloat = 1.05) {
        self.isActive = isActive
        self.scale = scale
    }
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isActive ? scale : 1.0)
            .shadow(
                color: DesignSystem.Colors.primary.opacity(isActive ? 0.2 : 0),
                radius: isActive ? 20 : 0,
                x: 0,
                y: isActive ? 10 : 0
            )
            .animation(
                .spring(response: 0.4, dampingFraction: 0.7, blendDuration: 0),
                value: isActive
            )
    }
}

// MARK: - Morphing Card
struct MorphingCard: ViewModifier {
    let isExpanded: Bool
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isExpanded ? 1.02 : 1.0)
            .shadow(
                color: Color.black.opacity(isExpanded ? 0.15 : 0.08),
                radius: isExpanded ? 20 : 10,
                x: 0,
                y: isExpanded ? 10 : 5
            )
            .animation(
                .spring(response: 0.5, dampingFraction: 0.8),
                value: isExpanded
            )
    }
}

// MARK: - Parallax Scroll Effect
struct ParallaxEffect: ViewModifier {
    let offset: CGFloat
    let multiplier: CGFloat
    
    init(offset: CGFloat, multiplier: CGFloat = 0.5) {
        self.offset = offset
        self.multiplier = multiplier
    }
    
    func body(content: Content) -> some View {
        content
            .offset(y: offset * multiplier)
    }
}

// MARK: - Liquid Swipe Transition
struct LiquidSwipe: ViewModifier {
    let progress: CGFloat
    let direction: Edge
    
    func body(content: Content) -> some View {
        content
            .mask(
                LiquidShape(progress: progress, direction: direction)
                    .fill(Color.black)
            )
    }
}

struct LiquidShape: Shape {
    var progress: CGFloat
    let direction: Edge
    
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let width = rect.width
        let height = rect.height
        let waveHeight: CGFloat = 40
        
        switch direction {
        case .leading:
            let x = width * progress
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: x - waveHeight, y: 0))
            path.addQuadCurve(
                to: CGPoint(x: x - waveHeight, y: height),
                control: CGPoint(x: x + waveHeight, y: height / 2)
            )
            path.addLine(to: CGPoint(x: 0, y: height))
            path.closeSubpath()
        case .trailing:
            let x = width * (1 - progress)
            path.move(to: CGPoint(x: width, y: 0))
            path.addLine(to: CGPoint(x: x + waveHeight, y: 0))
            path.addQuadCurve(
                to: CGPoint(x: x + waveHeight, y: height),
                control: CGPoint(x: x - waveHeight, y: height / 2)
            )
            path.addLine(to: CGPoint(x: width, y: height))
            path.closeSubpath()
        default:
            path = Path(rect)
        }
        
        return path
    }
}

// MARK: - Mesh Gradient Background
struct MeshGradientBackground: View {
    @State private var animateGradient = false
    let colors: [Color]
    
    init(colors: [Color] = [
        DesignSystem.Colors.primary.opacity(0.3),
        DesignSystem.Colors.secondary.opacity(0.3),
        DesignSystem.Colors.primaryDark.opacity(0.2)
    ]) {
        self.colors = colors
    }
    
    var body: some View {
        LinearGradient(
            colors: colors,
            startPoint: animateGradient ? .topLeading : .bottomLeading,
            endPoint: animateGradient ? .bottomTrailing : .topTrailing
        )
        .blur(radius: 50)
        .onAppear {
            withAnimation(.easeInOut(duration: 5).repeatForever(autoreverses: true)) {
                animateGradient.toggle()
            }
        }
    }
}

// MARK: - Ripple Effect
struct RippleEffect: ViewModifier {
    let trigger: Bool
    @State private var scale: CGFloat = 0
    @State private var opacity: Double = 0.5
    
    func body(content: Content) -> some View {
        content
            .background(
                Circle()
                    .fill(DesignSystem.Colors.primary)
                    .scaleEffect(scale)
                    .opacity(opacity)
                    .animation(.easeOut(duration: 0.6), value: scale)
                    .animation(.easeOut(duration: 0.6), value: opacity)
            )
            .onChange(of: trigger) { _, _ in
                scale = 0
                opacity = 0.5
                
                withAnimation {
                    scale = 3
                    opacity = 0
                }
            }
    }
}

// MARK: - Magnetic Hover Effect
struct MagneticHover: ViewModifier {
    @State private var offset = CGSize.zero
    @State private var isDragging = false
    
    func body(content: Content) -> some View {
        content
            .offset(offset)
            .scaleEffect(isDragging ? 1.05 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: offset)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isDragging)
            .onHover { hovering in
                if !hovering {
                    offset = .zero
                    isDragging = false
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        let maxOffset: CGFloat = 10
                        offset = CGSize(
                            width: min(max(value.translation.width * 0.1, -maxOffset), maxOffset),
                            height: min(max(value.translation.height * 0.1, -maxOffset), maxOffset)
                        )
                    }
                    .onEnded { _ in
                        offset = .zero
                        isDragging = false
                    }
            )
    }
}

// MARK: - Number Counter Animation
struct AnimatedNumber: View {
    let value: Int
    let duration: Double
    @State private var displayValue: Int = 0
    
    init(value: Int, duration: Double = 0.5) {
        self.value = value
        self.duration = duration
    }
    
    var body: some View {
        Text("\(displayValue)")
            .contentTransition(.numericText(countsDown: value < displayValue))
            .onAppear {
                animate()
            }
            .onChange(of: value) { _, _ in
                animate()
            }
    }
    
    private func animate() {
        withAnimation(.easeInOut(duration: duration)) {
            displayValue = value
        }
    }
}

// MARK: - Page Curl Transition
struct PageCurl: ViewModifier {
    let progress: CGFloat
    
    func body(content: Content) -> some View {
        content
            .rotation3DEffect(
                .degrees(progress * 90),
                axis: (x: 0, y: -1, z: 0),
                anchor: .leading,
                anchorZ: 0,
                perspective: 0.5
            )
            .opacity(progress < 0.5 ? 1 : 0)
    }
}

// MARK: - View Extensions
extension View {
    func heroScale(isActive: Bool, scale: CGFloat = 1.05) -> some View {
        modifier(HeroScale(isActive: isActive, scale: scale))
    }
    
    func morphingCard(isExpanded: Bool) -> some View {
        modifier(MorphingCard(isExpanded: isExpanded))
    }
    
    func parallax(offset: CGFloat, multiplier: CGFloat = 0.5) -> some View {
        modifier(ParallaxEffect(offset: offset, multiplier: multiplier))
    }
    
    func liquidSwipe(progress: CGFloat, direction: Edge = .trailing) -> some View {
        modifier(LiquidSwipe(progress: progress, direction: direction))
    }
    
    func rippleEffect(trigger: Bool) -> some View {
        modifier(RippleEffect(trigger: trigger))
    }
    
    func magneticHover() -> some View {
        modifier(MagneticHover())
    }
    
    func pageCurl(progress: CGFloat) -> some View {
        modifier(PageCurl(progress: progress))
    }
}

// MARK: - Animated Components
struct ModernLoadingIndicator: View {
    @State private var rotation = 0.0
    
    var body: some View {
        ZStack {
            ForEach(0..<3) { index in
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                DesignSystem.Colors.primary,
                                DesignSystem.Colors.secondary
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 15, height: 15)
                    .offset(y: -25)
                    .rotationEffect(.degrees(rotation + Double(index * 120)))
                    .animation(
                        .linear(duration: 1.2)
                        .repeatForever(autoreverses: false),
                        value: rotation
                    )
            }
        }
        .onAppear {
            rotation = 360
        }
    }
}

struct ModernProgressBar: View {
    let progress: CGFloat
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(DesignSystem.Colors.surfaceSecondary)
                
                // Progress
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                DesignSystem.Colors.primary,
                                DesignSystem.Colors.secondary
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * progress)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: progress)
                
                // Glow effect
                if progress > 0 {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.4),
                                    Color.white.opacity(0.1)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: geometry.size.width * progress, height: geometry.size.height * 0.5)
                        .offset(y: -geometry.size.height * 0.25)
                        .blur(radius: 2)
                }
            }
        }
        .frame(height: 20)
    }
}

#Preview {
    VStack(spacing: 40) {
        Text("Hero Animation")
            .font(.largeTitle)
            .heroScale(isActive: true)
        
        RoundedRectangle(cornerRadius: 20)
            .fill(DesignSystem.Colors.primary)
            .frame(width: 200, height: 100)
            .morphingCard(isExpanded: true)
        
        ModernLoadingIndicator()
        
        ModernProgressBar(progress: 0.7)
            .padding(.horizontal, 40)
        
        AnimatedNumber(value: 42)
            .font(.system(size: 48, weight: .bold, design: .rounded))
    }
    .padding()
    .background(MeshGradientBackground())
}