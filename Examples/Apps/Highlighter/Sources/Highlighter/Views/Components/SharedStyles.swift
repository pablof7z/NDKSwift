import SwiftUI

// MARK: - Theme Colors
extension Color {
    // Primary Colors
    static let highlighterPurple = Color(hex: "6A1B9A")
    static let highlighterOrange = Color(hex: "FF9500")
    
    // Background Colors
    static let highlighterBackground = Color(hex: "F5F5F5")
    static let highlighterCardBackground = Color.white
    static let highlighterDarkBackground = Color(hex: "1C1C1E")
    static let highlighterDarkCard = Color(hex: "2C2C2E")
    
    // Text Colors
    static let highlighterText = Color.black
    static let highlighterSecondaryText = Color.gray
    static let highlighterDarkText = Color.white
    
    // Accent Colors
    static let highlighterSuccess = Color.green
    static let highlighterWarning = Color.orange
    static let highlighterError = Color.red
    
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - View Modifiers

struct CardStyle: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    
    func body(content: Content) -> some View {
        content
            .background(colorScheme == .dark ? Color.highlighterDarkCard : Color.highlighterCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
}

struct HighlightCardStyle: ViewModifier {
    let isSelected: Bool
    
    func body(content: Content) -> some View {
        content
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.highlighterCardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(isSelected ? Color.highlighterOrange : Color.clear, lineWidth: 2)
                    )
            )
            .shadow(color: isSelected ? Color.highlighterOrange.opacity(0.3) : Color.black.opacity(0.05), 
                    radius: isSelected ? 12 : 8, 
                    x: 0, 
                    y: isSelected ? 4 : 2)
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold, design: .default))
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.highlighterPurple)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .medium, design: .default))
            .foregroundColor(.highlighterPurple)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.highlighterPurple, lineWidth: 2)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

struct ZapButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium, design: .default))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.highlighterOrange)
            )
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.8), value: configuration.isPressed)
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
    
    
    func fadeSlide(isVisible: Bool, delay: Double = 0) -> some View {
        self
            .offset(y: isVisible ? 0 : 20)
            .opacity(isVisible ? 1 : 0)
            .animation(.easeOut(duration: 0.4).delay(delay), value: isVisible)
    }
    
    func glassBackground(cornerRadius: CGFloat = 16) -> some View {
        self.background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.3),
                                    Color.white.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        }
    }
    
    
    func pulse() -> some View {
        modifier(PulseModifier())
    }
    
    func rotateAndScale(isActive: Bool) -> some View {
        modifier(RotateAndScaleModifier(isActive: isActive))
    }
    
    func cardBackground(isSelected: Bool = false) -> some View {
        modifier(EnhancedCardModifier(isSelected: isSelected))
    }
}

// MARK: - Haptic Feedback

enum HapticType {
    case light
    case medium
    case heavy
    case selection
    case success
    case warning
    case error
    
    func trigger() {
        switch self {
        case .light:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .medium:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .heavy:
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case .selection:
            UISelectionFeedbackGenerator().selectionChanged()
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .error:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}

// MARK: - Typography

extension Font {
    static let highlighterTitle = Font.system(size: 28, weight: .bold, design: .default)
    static let highlighterHeadline = Font.system(size: 20, weight: .semibold, design: .default)
    static let highlighterBody = Font.system(size: 16, weight: .regular, design: .default)
    static let highlighterCaption = Font.system(size: 14, weight: .regular, design: .default)
    static let highlighterQuote = Font.custom("Georgia", size: 18).italic()
}

// MARK: - Animations

extension Animation {
    static let highlighterSpring = Animation.spring(response: 0.4, dampingFraction: 0.8)
    static let highlighterEase = Animation.easeInOut(duration: 0.3)
}

// MARK: - Additional Components

struct PressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct LoadingDots: View {
    @State private var animationStates = [false, false, false]
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.highlighterOrange)
                    .frame(width: 8, height: 8)
                    .scaleEffect(animationStates[index] ? 1.2 : 0.8)
                    .opacity(animationStates[index] ? 1 : 0.5)
                    .animation(
                        .easeInOut(duration: 0.6)
                        .repeatForever()
                        .delay(Double(index) * 0.2),
                        value: animationStates[index]
                    )
            }
        }
        .onAppear {
            for index in 0..<3 {
                animationStates[index] = true
            }
        }
    }
}

struct AnimatedGradientBackground: View {
    @State private var animationPhase = 0.0
    let colors: [Color]
    
    init(colors: [Color] = [.highlighterPurple.opacity(0.1), .highlighterOrange.opacity(0.1), .highlighterBackground]) {
        self.colors = colors
    }
    
    var body: some View {
        LinearGradient(
            colors: colors,
            startPoint: UnitPoint(x: 0 + animationPhase, y: 0),
            endPoint: UnitPoint(x: 1 + animationPhase, y: 1)
        )
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.linear(duration: 5).repeatForever(autoreverses: true)) {
                animationPhase = 0.5
            }
        }
    }
}

// MARK: - Custom Tab Bar

struct CustomTabBar: View {
    @Binding var selectedTab: ContentView.Tab
    @Namespace private var animation
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(ContentView.Tab.allCases, id: \.self) { tab in
                TabBarItem(
                    tab: tab,
                    isSelected: selectedTab == tab,
                    namespace: animation
                ) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        selectedTab = tab
                    }
                    HapticType.selection.trigger()
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.2),
                                    Color.white.opacity(0.1)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                }
                .shadow(
                    color: Color.black.opacity(0.1),
                    radius: 8,
                    x: 0,
                    y: 4
                )
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }
}

struct TabBarItem: View {
    let tab: ContentView.Tab
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    if isSelected {
                        Circle()
                            .fill(LinearGradient(colors: [Color.highlighterOrange, Color.highlighterPurple], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 48, height: 48)
                            .matchedGeometryEffect(id: "tabBackground", in: namespace)
                    }
                    
                    Image(systemName: isSelected ? tab.filledIcon : tab.icon)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(isSelected ? .white : Color.highlighterSecondaryText)
                        .scaleEffect(isPressed ? 0.9 : 1.0)
                        .rotationEffect(.degrees(isSelected ? 360 : 0))
                        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isSelected)
                }
                
                Text(tab.title)
                    .font(.highlighterCaption)
                    .foregroundColor(isSelected ? .highlighterText : Color.highlighterSecondaryText)
                    .opacity(isSelected ? 1 : 0.7)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(TabButtonStyle())
    }
}

struct TabButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeOut(duration: 0.2), value: configuration.isPressed)
    }
}

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

struct EnhancedCardModifier: ViewModifier {
    let isSelected: Bool
    
    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.highlighterCardBackground)
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(
                                isSelected ?
                                LinearGradient(
                                    colors: [Color.highlighterOrange, Color.highlighterPurple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ) :
                                LinearGradient(
                                    colors: [Color.gray.opacity(0.2), Color.gray.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: isSelected ? 2 : 1
                            )
                    }
                    .shadow(
                        color: isSelected ? Color.highlighterOrange.opacity(0.3) : Color.black.opacity(0.08),
                        radius: isSelected ? 12 : 8,
                        x: 0,
                        y: isSelected ? 6 : 4
                    )
            }
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}