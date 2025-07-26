import SwiftUI

struct AnimatedBackgroundView: View {
    @State private var animate = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Base gradient
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.purple.opacity(0.4),
                        Color.blue.opacity(0.3),
                        Color.indigo.opacity(0.4)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                
                // Animated circles
                ForEach(0..<3) { index in
                    Circle()
                        .fill(
                            RadialGradient(
                                gradient: Gradient(colors: [
                                    Color.purple.opacity(0.3),
                                    Color.purple.opacity(0.1)
                                ]),
                                center: .center,
                                startRadius: 50,
                                endRadius: 150
                            )
                        )
                        .frame(width: 300, height: 300)
                        .offset(
                            x: animate ? CGFloat.random(in: -100...100) : 0,
                            y: animate ? CGFloat.random(in: -100...100) : 0
                        )
                        .blur(radius: 20)
                        .opacity(animate ? 0.8 : 0.4)
                        .animation(
                            .easeInOut(duration: Double.random(in: 4...8))
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.5),
                            value: animate
                        )
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            animate = true
        }
    }
}