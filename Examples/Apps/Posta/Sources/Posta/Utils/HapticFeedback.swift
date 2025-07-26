import SwiftUI
import UIKit

// MARK: - Haptic Feedback Manager
enum HapticFeedback {
    
    // Impact styles
    enum ImpactStyle {
        case light
        case medium
        case heavy
        case soft
        case rigid
        
        var generator: UIImpactFeedbackGenerator {
            switch self {
            case .light:
                return UIImpactFeedbackGenerator(style: .light)
            case .medium:
                return UIImpactFeedbackGenerator(style: .medium)
            case .heavy:
                return UIImpactFeedbackGenerator(style: .heavy)
            case .soft:
                return UIImpactFeedbackGenerator(style: .soft)
            case .rigid:
                return UIImpactFeedbackGenerator(style: .rigid)
            }
        }
    }
    
    // Notification styles
    enum NotificationStyle {
        case success
        case warning
        case error
        
        var feedbackType: UINotificationFeedbackGenerator.FeedbackType {
            switch self {
            case .success:
                return .success
            case .warning:
                return .warning
            case .error:
                return .error
            }
        }
    }
    
    // Selection feedback
    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }
    
    // Impact feedback
    static func impact(_ style: ImpactStyle) {
        let generator = style.generator
        generator.prepare()
        generator.impactOccurred()
    }
    
    // Notification feedback
    static func notification(_ style: NotificationStyle) {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(style.feedbackType)
    }
    
    // Custom pattern feedback
    static func pattern(_ pattern: [TimeInterval], intensity: CGFloat = 1.0) {
        guard !pattern.isEmpty else { return }
        
        Task {
            for (index, delay) in pattern.enumerated() {
                if index > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
                impact(.light)
            }
        }
    }
}

// MARK: - View Extensions
extension View {
    /// Adds haptic feedback when the view is tapped
    func hapticTap(_ style: HapticFeedback.ImpactStyle = .light) -> some View {
        self.onTapGesture {
            HapticFeedback.impact(style)
        }
    }
    
    /// Adds haptic feedback when a boolean value changes
    func hapticChange<V: Equatable>(_ value: V, style: HapticFeedback.ImpactStyle = .light) -> some View {
        self.onChange(of: value) { _, _ in
            HapticFeedback.impact(style)
        }
    }
    
    /// Adds haptic feedback for button presses
    func hapticButton(_ style: HapticFeedback.ImpactStyle = .light) -> some View {
        self.simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    HapticFeedback.impact(style)
                }
        )
    }
}

// MARK: - Button Style with Haptics
struct HapticButtonStyle: ButtonStyle {
    let hapticStyle: HapticFeedback.ImpactStyle
    
    init(hapticStyle: HapticFeedback.ImpactStyle = .light) {
        self.hapticStyle = hapticStyle
    }
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    HapticFeedback.impact(hapticStyle)
                }
            }
    }
}