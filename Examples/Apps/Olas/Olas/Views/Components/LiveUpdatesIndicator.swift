import SwiftUI

struct LiveUpdatesIndicator: View {
    @Binding var newPostsCount: Int
    @State private var isAnimating = false
    @State private var showPulse = false
    
    var body: some View {
        Button {
            OlasDesign.Haptic.selection()
            // Action will be handled by parent view
        } label: {
            HStack(spacing: 12) {
                // Animated live dot
                ZStack {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    
                    // Pulsing rings
                    ForEach(0..<3) { index in
                        Circle()
                            .stroke(Color.green.opacity(0.4), lineWidth: 1)
                            .frame(width: 8, height: 8)
                            .scaleEffect(showPulse ? CGFloat(2 + index) : 1)
                            .opacity(showPulse ? 0 : 0.6)
                            .animation(
                                .easeOut(duration: 2)
                                .repeatForever(autoreverses: false)
                                .delay(Double(index) * 0.4),
                                value: showPulse
                            )
                    }
                }
                
                // Text with count
                HStack(spacing: 6) {
                    Text("\(newPostsCount)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    OlasDesign.Colors.primary,
                                    OlasDesign.Colors.primary.opacity(0.8)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .contentTransition(.numericText())
                    
                    Text("new \(newPostsCount == 1 ? "post" : "posts")")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(OlasDesign.Colors.text)
                }
                
                // Arrow icon
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(
                        LinearGradient(
                            colors: OlasDesign.Colors.primaryGradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .rotationEffect(.degrees(isAnimating ? 0 : -180))
                    .animation(
                        .spring(response: 0.5, dampingFraction: 0.7)
                        .repeatForever(autoreverses: true),
                        value: isAnimating
                    )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        OlasDesign.Colors.primary.opacity(0.1),
                                        OlasDesign.Colors.primary.opacity(0.05)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        Capsule()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.2),
                                        Color.white.opacity(0.1)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
            .shadow(
                color: OlasDesign.Colors.primary.opacity(0.2),
                radius: 10,
                x: 0,
                y: 5
            )
        }
        .buttonStyle(ScaleButtonStyle())
        .padding(.vertical, 8)
        .onAppear {
            isAnimating = true
            showPulse = true
        }
    }
}

// Custom button style for scale effect
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// Preview
struct LiveUpdatesIndicator_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            LiveUpdatesIndicator(newPostsCount: .constant(5))
            LiveUpdatesIndicator(newPostsCount: .constant(1))
            LiveUpdatesIndicator(newPostsCount: .constant(23))
        }
        .padding()
        .background(Color.black)
    }
}