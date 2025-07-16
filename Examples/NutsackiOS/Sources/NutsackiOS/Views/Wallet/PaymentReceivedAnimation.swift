import SwiftUI
import UIKit

struct PaymentReceivedAnimation: View {
    let amount: Int64
    let onComplete: () -> Void
    
    @State private var showAmount = false
    @State private var showConfetti = false
    @State private var lightningScale: CGFloat = 0
    @State private var amountScale: CGFloat = 0
    @State private var amountRotation: Double = 0
    @State private var glowOpacity: Double = 0
    @State private var particleOpacity: Double = 0
    @State private var ringScale: CGFloat = 0
    @State private var satoshiSymbolRotation: Double = 0
    @State private var lightningBolts: [LightningBolt] = []
    @State private var coins: [FallingCoin] = []
    @State private var fireworks: [Firework] = []
    
    var body: some View {
        ZStack {
            // Dark backdrop
            Color.black.opacity(0.9)
                .ignoresSafeArea()
                .onTapGesture {
                    onComplete()
                }
            
            // Radial gradient background pulse
            RadialGradient(
                colors: [
                    Color.orange.opacity(glowOpacity * 0.3),
                    Color.orange.opacity(glowOpacity * 0.1),
                    Color.clear
                ],
                center: .center,
                startRadius: 50,
                endRadius: 300
            )
            .animation(.easeInOut(duration: 1.5).repeatCount(3), value: glowOpacity)
            
            // Expanding rings
            ForEach(0..<3) { index in
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [Color.orange, Color.yellow],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
                    .scaleEffect(ringScale)
                    .opacity(1 - Double(ringScale))
                    .animation(
                        .easeOut(duration: 2)
                            .delay(Double(index) * 0.3),
                        value: ringScale
                    )
            }
            
            // Lightning bolts radiating outward
            ForEach(lightningBolts) { bolt in
                LightningBoltView(bolt: bolt)
            }
            
            // Falling coins
            ForEach(coins) { coin in
                FallingCoinView(coin: coin)
            }
            
            // Main content
            VStack(spacing: 30) {
                // Lightning symbol with glow
                ZStack {
                    // Outer glow
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 120))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.yellow, .orange],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .blur(radius: 20)
                        .opacity(glowOpacity)
                        .scaleEffect(lightningScale * 1.2)
                    
                    // Main lightning bolt
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 100))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, .yellow, .orange],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .scaleEffect(lightningScale)
                        .rotationEffect(.degrees(satoshiSymbolRotation))
                        .shadow(color: .orange, radius: 20)
                }
                
                // Amount with epic entrance
                if showAmount {
                    VStack(spacing: 10) {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text("\(amount)")
                                .font(.system(size: 72, weight: .black, design: .rounded))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.white, .yellow, .orange],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            
                            Text("sats")
                                .font(.system(size: 36, weight: .bold, design: .rounded))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.orange, .yellow],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                        .scaleEffect(amountScale)
                        .rotationEffect(.degrees(amountRotation))
                        .shadow(color: .orange, radius: 30)
                        
                        Text("RECEIVED!")
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 30)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [.orange, .red],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                            )
                            .scaleEffect(amountScale)
                            .shadow(color: .orange, radius: 20)
                    }
                }
            }
            
            // Fireworks
            ForEach(fireworks) { firework in
                FireworkView(firework: firework)
            }
            
            // Confetti overlay
            if showConfetti {
                ConfettiView()
                    .allowsHitTesting(false)
            }
            
            // Particle effects
            GeometryReader { geometry in
                ForEach(0..<50) { _ in
                    ParticleView()
                        .position(
                            x: CGFloat.random(in: 0...geometry.size.width),
                            y: CGFloat.random(in: 0...geometry.size.height)
                        )
                        .opacity(particleOpacity)
                }
            }
        }
        .onAppear {
            startEpicAnimation()
        }
    }
    
    private func startEpicAnimation() {
        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
        impactFeedback.prepare()
        
        // Create lightning bolts
        for i in 0..<8 {
            let angle = Double(i) * (2 * .pi / 8)
            lightningBolts.append(LightningBolt(angle: angle))
        }
        
        // Create falling coins
        for _ in 0..<20 {
            coins.append(FallingCoin())
        }
        
        // Main animation sequence
        withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) {
            lightningScale = 1.2
            glowOpacity = 1
        }
        
        // Heavy haptic on lightning appear
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            impactFeedback.impactOccurred()
        }
        
        // Shrink lightning and show amount
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                lightningScale = 0.8
            }
            
            withAnimation(.interpolatingSpring(stiffness: 200, damping: 10)) {
                showAmount = true
                amountScale = 1.1
                amountRotation = 5
            }
            
            // Another haptic
            impactFeedback.impactOccurred()
        }
        
        // Settle amount animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                amountScale = 1
                amountRotation = 0
            }
        }
        
        // Start rotating satoshi symbol
        withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
            satoshiSymbolRotation = 360
        }
        
        // Show particles
        withAnimation(.easeIn(duration: 0.5)) {
            particleOpacity = 1
        }
        
        // Expand rings
        withAnimation(.easeOut(duration: 2)) {
            ringScale = 3
        }
        
        // Show confetti
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            showConfetti = true
            
            // Create fireworks
            for _ in 0..<5 {
                fireworks.append(Firework())
            }
            
            // Success haptic pattern
            let notificationFeedback = UINotificationFeedbackGenerator()
            notificationFeedback.notificationOccurred(.success)
        }
        
        // Auto dismiss after 4 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            withAnimation(.easeOut(duration: 0.3)) {
                glowOpacity = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                onComplete()
            }
        }
    }
}

// MARK: - Lightning Bolt
struct LightningBolt: Identifiable {
    let id = UUID()
    let angle: Double
    @State var offset: CGFloat = 0
    @State var opacity: Double = 1
}

struct LightningBoltView: View {
    let bolt: LightningBolt
    @State private var offset: CGFloat = 0
    @State private var opacity: Double = 1
    
    var body: some View {
        Image(systemName: "bolt.fill")
            .font(.system(size: 30))
            .foregroundStyle(
                LinearGradient(
                    colors: [.yellow, .orange],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .offset(
                x: cos(bolt.angle) * offset,
                y: sin(bolt.angle) * offset
            )
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeOut(duration: 1)) {
                    offset = 200
                    opacity = 0
                }
            }
    }
}

// MARK: - Falling Coin
struct FallingCoin: Identifiable {
    let id = UUID()
    let startX = CGFloat.random(in: 0...UIScreen.main.bounds.width)
    let startY = CGFloat.random(in: -200...0)
    let rotationSpeed = Double.random(in: 1...3)
}

struct FallingCoinView: View {
    let coin: FallingCoin
    @State private var offsetY: CGFloat = 0
    @State private var rotation: Double = 0
    @State private var opacity: Double = 1
    
    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [.yellow, .orange],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 20, height: 20)
            .overlay(
                Text("₿")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
            )
            .position(x: coin.startX, y: coin.startY + offsetY)
            .rotationEffect(.degrees(rotation))
            .opacity(opacity)
            .onAppear {
                withAnimation(.linear(duration: coin.rotationSpeed).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
                
                withAnimation(.easeIn(duration: 2)) {
                    offsetY = UIScreen.main.bounds.height + 200
                }
                
                withAnimation(.easeIn(duration: 2).delay(1)) {
                    opacity = 0
                }
            }
    }
}

// MARK: - Firework
struct Firework: Identifiable {
    let id = UUID()
    let position = CGPoint(
        x: CGFloat.random(in: 100...UIScreen.main.bounds.width - 100),
        y: CGFloat.random(in: 100...UIScreen.main.bounds.height - 300)
    )
    let color = [Color.orange, Color.yellow, Color.red, Color.pink].randomElement()!
}

struct FireworkView: View {
    let firework: Firework
    @State private var scale: CGFloat = 0
    @State private var opacity: Double = 1
    
    var body: some View {
        ZStack {
            ForEach(0..<12) { index in
                Rectangle()
                    .fill(firework.color)
                    .frame(width: 3, height: 20)
                    .offset(y: -40)
                    .rotationEffect(.degrees(Double(index) * 30))
                    .scaleEffect(scale)
            }
        }
        .position(firework.position)
        .opacity(opacity)
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                scale = 2
            }
            
            withAnimation(.easeIn(duration: 0.5).delay(0.3)) {
                opacity = 0
            }
        }
    }
}

// MARK: - Particle View
struct ParticleView: View {
    @State private var offset = CGSize.zero
    @State private var opacity: Double = 1
    
    var body: some View {
        Circle()
            .fill(Color.orange)
            .frame(width: 3, height: 3)
            .offset(offset)
            .opacity(opacity)
            .onAppear {
                let randomX = CGFloat.random(in: -100...100)
                let randomY = CGFloat.random(in: -100...100)
                let duration = Double.random(in: 1...2)
                
                withAnimation(.easeOut(duration: duration)) {
                    offset = CGSize(width: randomX, height: randomY)
                    opacity = 0
                }
            }
    }
}

// MARK: - Confetti View
struct ConfettiView: View {
    @State private var confettiPieces: [ConfettiPiece] = []
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(confettiPieces) { piece in
                    ConfettiPieceView(piece: piece, screenHeight: geometry.size.height)
                }
            }
        }
        .onAppear {
            for _ in 0..<100 {
                confettiPieces.append(ConfettiPiece())
            }
        }
    }
}

struct ConfettiPiece: Identifiable {
    let id = UUID()
    let color = [Color.red, Color.orange, Color.yellow, Color.green, Color.blue, Color.purple, Color.pink].randomElement()!
    let startX = CGFloat.random(in: 0...UIScreen.main.bounds.width)
    let startY = CGFloat.random(in: -50...0)
    let size = CGFloat.random(in: 5...15)
    let shape = Int.random(in: 0...2) // 0: square, 1: circle, 2: triangle
    let rotationSpeed = Double.random(in: 1...3)
    let fallSpeed = Double.random(in: 2...4)
}

struct ConfettiPieceView: View {
    let piece: ConfettiPiece
    let screenHeight: CGFloat
    @State private var offsetY: CGFloat = 0
    @State private var rotation: Double = 0
    @State private var opacity: Double = 1
    
    var body: some View {
        Group {
            switch piece.shape {
            case 0: // Square
                Rectangle()
            case 1: // Circle
                Circle()
            default: // Triangle
                Triangle()
            }
        }
        .fill(piece.color)
        .frame(width: piece.size, height: piece.size)
        .position(x: piece.startX, y: piece.startY + offsetY)
        .rotationEffect(.degrees(rotation))
        .opacity(opacity)
        .onAppear {
            withAnimation(.linear(duration: piece.rotationSpeed).repeatForever(autoreverses: false)) {
                rotation = 360
            }
            
            withAnimation(.linear(duration: piece.fallSpeed)) {
                offsetY = screenHeight + 100
            }
            
            withAnimation(.easeIn(duration: 0.5).delay(piece.fallSpeed - 0.5)) {
                opacity = 0
            }
        }
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

// MARK: - Preview
#Preview {
    PaymentReceivedAnimation(amount: 21000) {
        print("Animation completed")
    }
}