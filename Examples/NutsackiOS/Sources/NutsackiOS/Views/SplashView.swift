import SwiftUI

struct SplashView: View {
    @State private var logoScale: CGFloat = 0.3
    @State private var logoOpacity: Double = 0
    @State private var titleOffset: CGFloat = 50
    @State private var titleOpacity: Double = 0
    @State private var subtitleOpacity: Double = 0
    @State private var ringScale: CGFloat = 0
    @State private var ringOpacity: Double = 0
    @State private var particlesVisible = false
    
    let onComplete: () -> Void
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.05),
                    Color.black
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            // Animated rings
            ZStack {
                ForEach(0..<3) { index in
                    Circle()
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.orange.opacity(0.3),
                                    Color.orange.opacity(0.1)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                        .frame(width: 200 + CGFloat(index) * 80, height: 200 + CGFloat(index) * 80)
                        .scaleEffect(ringScale)
                        .opacity(ringOpacity)
                        .animation(
                            .easeOut(duration: 1.5)
                            .delay(Double(index) * 0.2),
                            value: ringScale
                        )
                }
            }
            
            // Floating particles
            if particlesVisible {
                ParticleEffectView()
                    .opacity(0.6)
            }
            
            VStack(spacing: 30) {
                // Logo
                ZStack {
                    // Glow effect
                    Circle()
                        .fill(
                            RadialGradient(
                                gradient: Gradient(colors: [
                                    Color.orange.opacity(0.5),
                                    Color.orange.opacity(0)
                                ]),
                                center: .center,
                                startRadius: 5,
                                endRadius: 80
                            )
                        )
                        .frame(width: 200, height: 200)
                        .blur(radius: 20)
                        .scaleEffect(logoScale * 1.2)
                        .opacity(logoOpacity)
                    
                    // Main logo
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.orange,
                                        Color.orange.opacity(0.8)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 120, height: 120)
                        
                        Image(systemName: "banknote.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.white)
                            .rotationEffect(.degrees(-15))
                    }
                    .scaleEffect(logoScale)
                    .opacity(logoOpacity)
                }
                
                // Title and subtitle
                VStack(spacing: 10) {
                    Text("Nutsack")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    .white,
                                    .white.opacity(0.8)
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .offset(y: titleOffset)
                        .opacity(titleOpacity)
                    
                    Text("Lightning-fast payments with Nostr")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.7))
                        .opacity(subtitleOpacity)
                }
            }
        }
        .onAppear {
            animateSplash()
        }
    }
    
    private func animateSplash() {
        // Logo animation
        withAnimation(.spring(response: 0.8, dampingFraction: 0.6)) {
            logoScale = 1
            logoOpacity = 1
        }
        
        // Ring animation
        withAnimation(.easeOut(duration: 1.2)) {
            ringScale = 1
            ringOpacity = 0.3
        }
        
        // Title animation
        withAnimation(.easeOut(duration: 0.8).delay(0.3)) {
            titleOffset = 0
            titleOpacity = 1
        }
        
        // Subtitle animation
        withAnimation(.easeOut(duration: 0.8).delay(0.5)) {
            subtitleOpacity = 1
        }
        
        // Particles
        withAnimation(.easeIn(duration: 0.5).delay(0.8)) {
            particlesVisible = true
        }
        
        // Complete animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeInOut(duration: 0.5)) {
                onComplete()
            }
        }
    }
}

// MARK: - Particle Effect View
struct ParticleEffectView: View {
    @State private var particles: [Particle] = []
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(particles) { particle in
                    Circle()
                        .fill(Color.orange.opacity(particle.opacity))
                        .frame(width: particle.size, height: particle.size)
                        .position(particle.position)
                        .blur(radius: particle.blur)
                }
            }
            .onAppear {
                createParticles(in: geometry.size)
            }
        }
    }
    
    private func createParticles(in size: CGSize) {
        for _ in 0..<20 {
            let particle = Particle(
                position: CGPoint(
                    x: CGFloat.random(in: 0...size.width),
                    y: CGFloat.random(in: size.height * 0.3...size.height * 0.7)
                ),
                size: CGFloat.random(in: 2...6),
                opacity: Double.random(in: 0.2...0.6),
                blur: CGFloat.random(in: 0...3)
            )
            particles.append(particle)
            
            // Animate particle
            withAnimation(
                .easeInOut(duration: Double.random(in: 3...6))
                .repeatForever(autoreverses: true)
            ) {
                if let index = particles.firstIndex(where: { $0.id == particle.id }) {
                    particles[index].position.y -= CGFloat.random(in: 20...40)
                    particles[index].opacity *= 0.5
                }
            }
        }
    }
}

struct Particle: Identifiable {
    let id = UUID()
    var position: CGPoint
    var size: CGFloat
    var opacity: Double
    var blur: CGFloat
}

// MARK: - Preview
struct SplashView_Previews: PreviewProvider {
    static var previews: some View {
        SplashView(onComplete: {})
            .preferredColorScheme(.dark)
    }
}