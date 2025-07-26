import SwiftUI

struct SplashView: View {
    @State private var isAnimating = false
    @State private var showContent = false
    @State private var logoScale: CGFloat = 0
    @State private var logoOpacity: Double = 0
    @State private var titleOpacity: Double = 0
    @State private var particleOffset: CGFloat = -100
    @Binding var isShowingSplash: Bool
    
    var body: some View {
        ZStack {
            // Animated background
            AnimatedBackgroundView()
            
            // Floating particles
            ForEach(0..<15) { index in
                Circle()
                    .fill(Color.purple.opacity(0.4))
                    .frame(width: CGFloat.random(in: 4...12))
                    .offset(
                        x: CGFloat.random(in: -150...150),
                        y: particleOffset + CGFloat(index * 60)
                    )
                    .blur(radius: CGFloat.random(in: 1...3))
                    .opacity(showContent ? 0.6 : 0)
            }
            
            VStack(spacing: 30) {
                Spacer()
                
                // Animated logo
                PostaLogoView(size: 120, color: .purple)
                    .scaleEffect(logoScale)
                    .opacity(logoOpacity)
                    .pulsing(minScale: 0.95, maxScale: 1.05, duration: 2)
                
                // App name with shimmer effect
                Text("Posta")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white,
                                Color.white.opacity(0.9)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .opacity(titleOpacity)
                    .shimmer()
                
                // Tagline
                Text("Secure Messaging on Nostr")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                    .opacity(titleOpacity)
                
                Spacer()
                
                // Loading indicator
                LoadingDots(dotSize: 10, color: .white.opacity(0.8))
                    .opacity(showContent ? 1 : 0)
                
                Spacer()
                    .frame(height: 60)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            startAnimation()
        }
    }
    
    private func startAnimation() {
        // Logo entrance animation
        withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
            logoScale = 1
            logoOpacity = 1
        }
        
        // Title and content fade in
        withAnimation(.easeOut(duration: 0.6).delay(0.3)) {
            titleOpacity = 1
            showContent = true
        }
        
        // Start particle animation
        withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
            particleOffset = UIScreen.main.bounds.height + 200
        }
        
        // Trigger app transition
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeInOut(duration: 0.5)) {
                isShowingSplash = false
            }
        }
    }
}

#Preview {
    SplashView(isShowingSplash: .constant(true))
}