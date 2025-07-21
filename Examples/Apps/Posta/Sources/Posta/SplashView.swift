import SwiftUI

struct SplashView: View {
    @State private var isAnimating = false
    @State private var showContent = false
    @Binding var isShowingSplash: Bool
    
    var body: some View {
        ZStack {
            backgroundGradient
            
            VStack(spacing: 30) {
                Spacer()
                
                logoView
                
                appNameView
                
                taglineView
                
                Spacer()
                
                loadingIndicator
                
                Spacer()
                    .frame(height: 60)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            startAnimation()
        }
    }
    
    private var backgroundGradient: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                Color(red: 0.58, green: 0.0, blue: 0.83),
                Color(red: 0.29, green: 0.0, blue: 0.51),
                Color(red: 0.13, green: 0.0, blue: 0.25)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    private var logoView: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.1))
                .frame(width: 140, height: 140)
                .blur(radius: 10)
                .scaleEffect(isAnimating ? 1.2 : 0.8)
                .animation(
                    Animation.easeInOut(duration: 2.0)
                        .repeatForever(autoreverses: true),
                    value: isAnimating
                )
            
            Circle()
                .fill(Color.white.opacity(0.15))
                .frame(width: 120, height: 120)
                .blur(radius: 5)
                .scaleEffect(isAnimating ? 1.1 : 0.9)
                .animation(
                    Animation.easeInOut(duration: 2.0)
                        .repeatForever(autoreverses: true)
                        .delay(0.2),
                    value: isAnimating
                )
            
            Image(systemName: "envelope.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 60, height: 60)
                .foregroundColor(.white)
                .rotationEffect(.degrees(isAnimating ? 0 : -10))
                .scaleEffect(showContent ? 1 : 0)
                .animation(
                    .spring(response: 0.6, dampingFraction: 0.7, blendDuration: 0),
                    value: showContent
                )
        }
    }
    
    private var appNameView: some View {
        Text("Posta")
            .font(.system(size: 48, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .scaleEffect(showContent ? 1 : 0)
            .animation(
                .spring(response: 0.6, dampingFraction: 0.7, blendDuration: 0)
                    .delay(0.2),
                value: showContent
            )
    }
    
    private var taglineView: some View {
        Text("Connect. Share. Decentralize.")
            .font(.system(size: 18, weight: .medium, design: .rounded))
            .foregroundColor(.white.opacity(0.8))
            .scaleEffect(showContent ? 1 : 0)
            .animation(
                .spring(response: 0.6, dampingFraction: 0.7, blendDuration: 0)
                    .delay(0.4),
                value: showContent
            )
    }
    
    private var loadingIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.white.opacity(0.7))
                    .frame(width: 8, height: 8)
                    .scaleEffect(isAnimating ? 1 : 0.5)
                    .animation(
                        Animation.easeInOut(duration: 0.6)
                            .repeatForever()
                            .delay(Double(index) * 0.2),
                        value: isAnimating
                    )
            }
        }
        .opacity(showContent ? 1 : 0)
        .animation(
            .easeIn(duration: 0.4)
                .delay(0.6),
            value: showContent
        )
    }
    
    private func startAnimation() {
        withAnimation {
            isAnimating = true
            showContent = true
        }
        
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