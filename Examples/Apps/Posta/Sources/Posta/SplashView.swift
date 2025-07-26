import SwiftUI

struct SplashView: View {
    @State private var isAnimating = false
    @State private var showContent = false
    @State private var logoScale: CGFloat = 0
    @State private var logoOpacity: Double = 0
    @State private var logoRotation: Double = -180
    @State private var titleOpacity: Double = 0
    @State private var glowOpacity: Double = 0
    @State private var pulseScale: CGFloat = 1
    @State private var electricityPhase: CGFloat = 0
    @Binding var isShowingSplash: Bool
    
    var body: some View {
        ZStack {
            // Modern animated background
            PostaBackgroundView()
            
            // Electric field effects
            ElectricFieldView()
                .opacity(glowOpacity * 0.3)
            
            VStack(spacing: 40) {
                Spacer()
                
                // Logo with advanced effects
                ZStack {
                    // Outer glow
                    Circle()
                        .fill(
                            RadialGradient(
                                gradient: Gradient(colors: [
                                    PostaColors.electricPurple.opacity(0.8),
                                    PostaColors.glowPink.opacity(0.4),
                                    Color.clear
                                ]),
                                center: .center,
                                startRadius: 30,
                                endRadius: 150
                            )
                        )
                        .frame(width: 350, height: 350)
                        .blur(radius: 40)
                        .scaleEffect(pulseScale)
                        .opacity(logoOpacity * 0.6)
                    
                    // Logo container
                    ZStack {
                        // Background circle
                        Circle()
                            .fill(
                                LinearGradient(
                                    gradient: PostaColors.primaryGradient,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 180, height: 180)
                            .shadow(color: PostaColors.electricPurple.opacity(0.6), radius: 30, x: 0, y: 10)
                        
                        // Logo
                        PostaLogoView(size: 110, color: .white)
                    }
                    .scaleEffect(logoScale)
                    .opacity(logoOpacity)
                    .rotationEffect(.degrees(logoRotation))
                }
                
                // App name with advanced styling
                VStack(spacing: 16) {
                    Text("POSTA")
                        .font(.system(size: 64, weight: .black, design: .default))
                        .tracking(6)
                        .foregroundStyle(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.white,
                                    Color.white.opacity(0.95)
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: PostaColors.electricPurple.opacity(0.5), radius: 20, x: 0, y: 4)
                        .opacity(titleOpacity)
                        .postaShimmer()
                    
                    Text("ENCRYPTED NOSTR MESSAGING")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .tracking(3)
                        .foregroundColor(PostaColors.textSecondary)
                        .opacity(titleOpacity)
                }
                
                Spacer()
                
                // Modern loading indicator
                HStack(spacing: 12) {
                    ForEach(0..<3) { index in
                        Circle()
                            .fill(
                                LinearGradient(
                                    gradient: PostaColors.primaryGradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: 12, height: 12)
                            .scaleEffect(showContent ? 1 : 0.3)
                            .opacity(showContent ? 1 : 0)
                            .animation(
                                .spring(response: 0.5, dampingFraction: 0.6)
                                .delay(Double(index) * 0.1),
                                value: showContent
                            )
                    }
                }
                .padding(.bottom, 20)
                
                Text("Loading...")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(PostaColors.textSecondary)
                    .opacity(showContent ? 1 : 0)
                
                Spacer()
                    .frame(height: 80)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            startAnimation()
        }
    }
    
    private func startAnimation() {
        // Logo entrance animation with rotation
        withAnimation(.spring(response: 1.2, dampingFraction: 0.7)) {
            logoScale = 1
            logoOpacity = 1
            logoRotation = 0
        }
        
        // Glow effects
        withAnimation(.easeInOut(duration: 1.5).delay(0.2)) {
            glowOpacity = 1
        }
        
        // Pulse animation
        withAnimation(.easeInOut(duration: 2).delay(0.8).repeatForever(autoreverses: true)) {
            pulseScale = 1.2
        }
        
        // Title and content fade in
        withAnimation(.easeOut(duration: 0.8).delay(0.6)) {
            titleOpacity = 1
        }
        
        withAnimation(.easeOut(duration: 0.6).delay(1)) {
            showContent = true
        }
        
        // Trigger app transition
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation(.easeInOut(duration: 0.6)) {
                isShowingSplash = false
            }
        }
    }
}

#Preview {
    SplashView(isShowingSplash: .constant(true))
}