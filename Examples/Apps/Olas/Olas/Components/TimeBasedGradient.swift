import SwiftUI

struct TimeBasedGradient: View {
    @State private var animateGradient = false
    
    private var gradientColors: [Color] {
        let hour = Calendar.current.component(.hour, from: Date())
        
        switch hour {
        case 5..<8: // Early morning
            return [Color(hex: "FF6B6B"), Color(hex: "4ECDC4")]
        case 8..<12: // Morning
            return [Color(hex: "667EEA"), Color(hex: "764BA2")]
        case 12..<17: // Afternoon
            return [Color(hex: "F093FB"), Color(hex: "F5576C")]
        case 17..<20: // Evening
            return [Color(hex: "FA709A"), Color(hex: "FEE140")]
        case 20..<24, 0..<5: // Night
            return [Color(hex: "30CFD0"), Color(hex: "330867")]
        default:
            return [Color(hex: "667EEA"), Color(hex: "764BA2")]
        }
    }
    
    var body: some View {
        LinearGradient(
            colors: gradientColors,
            startPoint: animateGradient ? .topLeading : .bottomLeading,
            endPoint: animateGradient ? .bottomTrailing : .topTrailing
        )
        .animation(.easeInOut(duration: 5).repeatForever(autoreverses: true), value: animateGradient)
        .onAppear {
            animateGradient = true
        }
    }
}