import SwiftUI
import UIKit

// MARK: - Time-based Gradient Background
struct TimeBasedGradient: View {
    @State private var gradientColors: [Color] = []
    @State private var animateGradient = false
    
    var body: some View {
        LinearGradient(
            colors: gradientColors.isEmpty ? OlasDesign.Colors.gradient : gradientColors,
            startPoint: animateGradient ? .topLeading : .bottomLeading,
            endPoint: animateGradient ? .bottomTrailing : .topTrailing
        )
        .animation(.linear(duration: 5).repeatForever(autoreverses: true), value: animateGradient)
        .onAppear {
            updateGradient()
            animateGradient = true
            
            // Update gradient periodically
            Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
                withAnimation(.easeInOut(duration: 2)) {
                    updateGradient()
                }
            }
        }
    }
    
    private func updateGradient() {
        let hour = Calendar.current.component(.hour, from: Date())
        
        switch hour {
        case 5..<12: // Dawn to noon
            gradientColors = [Color(hex: "FF6B6B"), Color(hex: "4ECDC4")]
        case 12..<17: // Day
            gradientColors = [Color(hex: "667eea"), Color(hex: "764ba2")]
        case 17..<21: // Dusk
            gradientColors = [Color(hex: "f093fb"), Color(hex: "f5576c")]
        default: // Night
            gradientColors = [Color(hex: "4facfe"), Color(hex: "00f2fe")]
        }
    }
}

// MARK: - Haptic Manager
struct HapticManager {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
        #endif
    }
    
    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
        #endif
    }
    
    static func selection() {
        #if os(iOS)
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
        #endif
    }
}


