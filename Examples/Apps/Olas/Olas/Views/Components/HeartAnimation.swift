import SwiftUI

struct HeartAnimation: View {
    let location: CGPoint
    @State private var scale: CGFloat = 0
    @State private var opacity: Double = 1
    @State private var particles: [HeartParticle] = []
    
    var body: some View {
        ZStack {
            // Main heart
            Image(systemName: "heart.fill")
                .font(.system(size: 80))
                .foregroundStyle(
                    LinearGradient(
                        colors: [OlasDesign.Colors.error, .pink],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .scaleEffect(scale)
                .opacity(opacity)
                .position(location)
                .shadow(color: OlasDesign.Colors.error.opacity(0.3), radius: 10)
            
            // Particle hearts
            ForEach(particles) { particle in
                Image(systemName: "heart.fill")
                    .font(.system(size: particle.size))
                    .foregroundColor(particle.color)
                    .position(
                        x: location.x + particle.offset.width,
                        y: location.y + particle.offset.height
                    )
                    .opacity(particle.opacity)
            }
        }
        .onAppear {
            // Create particles
            for i in 0..<12 {
                let angle = Double(i) * (360.0 / 12.0) * .pi / 180
                let radius = Double.random(in: 60...120)
                let particle = HeartParticle(
                    angle: angle,
                    radius: radius,
                    size: CGFloat.random(in: 12...20),
                    color: [OlasDesign.Colors.error, .pink, .red].randomElement()!
                )
                particles.append(particle)
            }
            
            // Animate main heart
            withAnimation(.easeOut(duration: 0.15)) {
                scale = 1.2
            }
            
            withAnimation(.easeInOut(duration: 0.3).delay(0.15)) {
                scale = 1.0
                opacity = 0
            }
            
            // Animate particles
            for (index, particle) in particles.enumerated() {
                withAnimation(.easeOut(duration: 0.6).delay(Double(index) * 0.02)) {
                    particles[index].offset = CGSize(
                        width: cos(particle.angle) * particle.radius,
                        height: sin(particle.angle) * particle.radius
                    )
                    particles[index].opacity = 0
                }
            }
        }
    }
}

struct HeartParticle: Identifiable {
    let id = UUID()
    let angle: Double
    let radius: Double
    let size: CGFloat
    let color: Color
    var offset: CGSize = .zero
    var opacity: Double = 1
}