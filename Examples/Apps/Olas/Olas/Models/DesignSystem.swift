import SwiftUI
import Foundation

// MARK: - Design System

enum OlasDesign {
    
    // MARK: - Time-Based Gradient System
    
    static var currentGradient: LinearGradient {
        let hour = Calendar.current.component(.hour, from: Date())
        
        switch hour {
        case 5...7: // Dawn
            return LinearGradient(
                colors: [Color(hex: "FF6B6B"), Color(hex: "4ECDC4")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case 8...16: // Day
            return LinearGradient(
                colors: [Color(hex: "667eea"), Color(hex: "764ba2")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case 17...19: // Dusk
            return LinearGradient(
                colors: [Color(hex: "f093fb"), Color(hex: "f5576c")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        default: // Night
            return LinearGradient(
                colors: [Color(hex: "4facfe"), Color(hex: "00f2fe")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    static var accentGradient: LinearGradient {
        currentGradient
    }
    
    // MARK: - Colors
    
    enum Colors {
        static let background = Color.black
        static let surface = Color.white.opacity(0.08) // Glass morphism
        static let text = Color.white
        static let textSecondary = Color.white.opacity(0.7)
        static let textTertiary = Color.white.opacity(0.5)
        static let divider = Color.white.opacity(0.1)
        static let border = Color.white.opacity(0.15)
        static let error = Color(hex: "FF6B6B")
        static let success = Color(hex: "4ECDC4")
        static let warning = Color(hex: "FFA726")
        static let primary = Color(hex: "667eea") // Default to day color
        static let secondary = Color(hex: "764ba2")
        static let like = Color(hex: "FF4458") // Heart red
        static let gradient = [Color(hex: "667eea"), Color(hex: "764ba2")] // Default gradient
        static let primaryGradient = [Color(hex: "667eea"), Color(hex: "764ba2")] // For compatibility
    }
    
    // MARK: - Typography
    
    enum Typography {
        static let largeTitle = Font.system(.largeTitle, design: .rounded, weight: .bold)
        static let title = Font.system(.title, design: .rounded, weight: .semibold)
        static let title2 = Font.system(.title2, design: .rounded, weight: .semibold)
        static let title3 = Font.system(.title3, design: .rounded, weight: .medium)
        static let headline = Font.system(.headline, design: .default, weight: .semibold)
        static let body = Font.custom("Inter", size: 16).weight(.regular)
        static let bodyMedium = Font.custom("Inter", size: 16).weight(.medium)
        static let bodyBold = Font.custom("Inter", size: 16).weight(.bold)
        static let caption = Font.custom("Inter", size: 14).weight(.regular)
        static let footnote = Font.custom("Inter", size: 13).weight(.regular)
        static let mono = Font.custom("JetBrains Mono", size: 14).weight(.regular)
    }
    
    // MARK: - Spacing (8pt Grid System)
    
    enum Spacing {
        static let xxs: CGFloat = 2   // 0.25x
        static let xs: CGFloat = 4    // 0.5x
        static let sm: CGFloat = 8    // 1x (base)
        static let md: CGFloat = 16   // 2x
        static let lg: CGFloat = 24   // 3x
        static let xl: CGFloat = 32   // 4x
        static let xxl: CGFloat = 48  // 6x
        static let xxxl: CGFloat = 64 // 8x
    }
    
    // MARK: - Animations
    
    enum Animation {
        static let springResponse: Double = 0.55
        static let springDamping: Double = 0.825
        static let spring = SwiftUI.Animation.spring(response: springResponse, dampingFraction: springDamping)
        
        static let microDuration: Double = 0.2
        static let macroDuration: Double = 0.35
        
        static let easeOutBack = SwiftUI.Animation.timingCurve(0.34, 1.56, 0.64, 1, duration: macroDuration)
    }
    
    // MARK: - Corner Radius
    
    enum CornerRadius {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let full: CGFloat = 9999
    }
    
    // MARK: - Shadows
    
    enum Shadow {
        static func small(color: Color = .black) -> SwiftShadow {
            SwiftShadow(color: color.opacity(0.15), radius: 4, x: 0, y: 2)
        }
        
        static func medium(color: Color = .black) -> SwiftShadow {
            SwiftShadow(color: color.opacity(0.2), radius: 8, x: 0, y: 4)
        }
        
        static func large(color: Color = .black) -> SwiftShadow {
            SwiftShadow(color: color.opacity(0.25), radius: 16, x: 0, y: 8)
        }
        
        static func glow(color: Color) -> SwiftShadow {
            SwiftShadow(color: color.opacity(0.6), radius: 20, x: 0, y: 0)
        }
    }
    
    // MARK: - Haptic Feedback
    
    enum Haptic {
        #if os(iOS)
        static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
            let impactFeedback = UIImpactFeedbackGenerator(style: style)
            impactFeedback.prepare()
            impactFeedback.impactOccurred()
        }
        #else
        static func impact(_ style: Int) {
            // No haptic feedback on macOS
        }
        #endif
        
        static func selection() {
            #if os(iOS)
            let selectionFeedback = UISelectionFeedbackGenerator()
            selectionFeedback.prepare()
            selectionFeedback.selectionChanged()
            #endif
        }
        
        #if os(iOS)
        static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
            let notificationFeedback = UINotificationFeedbackGenerator()
            notificationFeedback.prepare()
            notificationFeedback.notificationOccurred(type)
        }
        #else
        static func notification(_ type: Int) {
            // No haptic feedback on macOS
        }
        #endif
        
        static func success() {
            #if os(iOS)
            notification(.success)
            #endif
        }
        
        static func error() {
            #if os(iOS)
            notification(.error)
            #endif
        }
    }
}

// MARK: - Shadow Helper

struct SwiftShadow {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

// MARK: - View Extensions

extension View {
    func olasGradient() -> some View {
        self.foregroundStyle(OlasDesign.currentGradient)
    }
    
    func olasSurface() -> some View {
        self
            .background(OlasDesign.Colors.surface)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.lg))
    }
    
    func olasGlassMorphism() -> some View {
        self
            .background(
                ZStack {
                    OlasDesign.Colors.surface
                    Color.white.opacity(0.05)
                }
            )
            .background(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.lg)
                    .stroke(OlasDesign.Colors.divider, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.lg))
    }
    
    func olasShadow(_ shadow: SwiftShadow) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }
    
    func olasTextShadow() -> some View {
        self.shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
    }
    
    func olasSpringAnimation() -> some View {
        self.animation(OlasDesign.Animation.spring, value: UUID())
    }
}

// MARK: - Custom Components
// Note: OlasButton is defined in Views/Components/OlasButton.swift

struct OlasTextField: View {
    @Binding var text: String
    let placeholder: String
    var isSecure: Bool = false
    var icon: String? = nil
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack(spacing: OlasDesign.Spacing.md) {
            if let icon = icon {
                Image(systemName: icon)
                    .foregroundColor(OlasDesign.Colors.textSecondary)
                    .font(.system(size: 18))
            }
            
            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .font(OlasDesign.Typography.body)
            .foregroundColor(OlasDesign.Colors.text)
            .focused($isFocused)
        }
        .padding(OlasDesign.Spacing.md)
        .background(OlasDesign.Colors.surface)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.md)
                .stroke(
                    isFocused ? OlasDesign.Colors.text.opacity(0.5) : OlasDesign.Colors.divider,
                    lineWidth: isFocused ? 2 : 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.md))
        .animation(OlasDesign.Animation.spring, value: isFocused)
        .onChange(of: isFocused) { _, focused in
            if focused {
                OlasDesign.Haptic.selection()
            }
        }
    }
}

// MARK: - Loading States

struct OlasShimmer: View {
    @State private var isAnimating = false
    
    var body: some View {
        LinearGradient(
            colors: [
                OlasDesign.Colors.surface,
                OlasDesign.Colors.surface.opacity(0.6),
                OlasDesign.Colors.surface
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .offset(x: isAnimating ? 200 : -200)
        .animation(
            .linear(duration: 1.5)
            .repeatForever(autoreverses: false),
            value: isAnimating
        )
        .onAppear {
            isAnimating = true
        }
    }
}

struct OlasSkeletonView: View {
    let height: CGFloat
    
    var body: some View {
        RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.sm)
            .fill(OlasDesign.Colors.surface)
            .overlay(OlasShimmer())
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: OlasDesign.CornerRadius.sm))
    }
}

struct OlasLoadingView: View {
    var body: some View {
        Rectangle()
            .fill(OlasDesign.Colors.surface)
            .overlay(OlasShimmer())
    }
}


// MARK: - Relative Time Formatter
// RelativeTimeFormatter is defined in StoriesManager.swift
