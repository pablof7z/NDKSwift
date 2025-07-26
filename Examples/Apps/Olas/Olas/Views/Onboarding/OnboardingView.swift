import SwiftUI

struct OnboardingView: View {
    @Environment(NostrManager.self) private var nostrManager
    @EnvironmentObject var appState: AppState
    @State private var currentPage = 0
    @State private var animateContent = false
    
    var body: some View {
        ZStack {
            // Dynamic gradient background
            TimeBasedGradient()
                .ignoresSafeArea()
            
            TabView(selection: $currentPage) {
                WelcomePageView()
                    .tag(0)
                
                NostrExplainerView()
                    .tag(1)
                
                KeyGenerationView()
                    .tag(2)
                
                SecurityEducationView()
                    .tag(3)
            }
            #if os(iOS)
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            #endif
            
            // Skip button
            if currentPage < 2 {
                VStack {
                    HStack {
                        Spacer()
                        Button("Skip") {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                currentPage = 2
                            }
                        }
                        .font(OlasDesign.Typography.body)
                        .foregroundStyle(.white.opacity(0.8))
                        .padding()
                    }
                    Spacer()
                }
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                animateContent = true
            }
        }
    }
}

// MARK: - Welcome Page
struct WelcomePageView: View {
    @State private var animate = false
    
    var body: some View {
        VStack(spacing: OlasDesign.Spacing.xxxl) {
            Spacer()
            
            // Animated Olas logo
            ZStack {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    OlasDesign.Colors.primaryGradient.first!,
                                    OlasDesign.Colors.primaryGradient.last!
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 120, height: 120)
                        .opacity(0.3)
                        .scaleEffect(animate ? 1.5 : 1.0)
                        .animation(
                            .easeInOut(duration: 2.0)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.3),
                            value: animate
                        )
                }
                
                Text("Olas")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            
            VStack(spacing: OlasDesign.Spacing.lg) {
                Text("Picture-First Social")
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                
                Text("Share your visual story on the\ndecentralized web")
                    .font(OlasDesign.Typography.body)
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
            .opacity(animate ? 1 : 0)
            .offset(y: animate ? 0 : 20)
            .animation(.easeOut(duration: 0.8).delay(0.3), value: animate)
            
            Spacer()
            
            // Swipe indicator
            HStack(spacing: 8) {
                ForEach(0..<4) { index in
                    Capsule()
                        .fill(index == 0 ? .white : .white.opacity(0.3))
                        .frame(width: index == 0 ? 24 : 8, height: 8)
                }
            }
            .padding(.bottom, 50)
        }
        .padding(.horizontal, OlasDesign.Spacing.xl)
        .onAppear {
            animate = true
        }
    }
}

// MARK: - Nostr Explainer
struct NostrExplainerView: View {
    @State private var animate = false
    @State private var nodeAnimations: [Bool] = Array(repeating: false, count: 6)
    
    var body: some View {
        VStack(spacing: OlasDesign.Spacing.xxxl) {
            Spacer()
            
            // Network visualization
            NetworkVisualization(animate: animate, nodeAnimations: nodeAnimations)
                .frame(width: 300, height: 300)
            
            VStack(spacing: OlasDesign.Spacing.lg) {
                Text("Your Content, Everywhere")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                
                Text("No single company controls your photos.\nThey live on a network of independent servers.")
                    .font(OlasDesign.Typography.body)
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
            .opacity(animate ? 1 : 0)
            .offset(y: animate ? 0 : 20)
            .animation(.easeOut(duration: 0.8).delay(0.5), value: animate)
            
            Spacer()
            
            // Page indicator
            HStack(spacing: 8) {
                ForEach(0..<4) { index in
                    Capsule()
                        .fill(index == 1 ? .white : .white.opacity(0.3))
                        .frame(width: index == 1 ? 24 : 8, height: 8)
                }
            }
            .padding(.bottom, 50)
        }
        .padding(.horizontal, OlasDesign.Spacing.xl)
        .onAppear {
            animate = true
            for i in 0..<6 {
                nodeAnimations[i] = true
            }
        }
    }
}

// MARK: - Network Visualization Component
struct NetworkVisualization: View {
    let animate: Bool
    let nodeAnimations: [Bool]
    
    var body: some View {
        ZStack {
            // Connection lines
            ForEach(0..<5) { index in
                ConnectionLine(index: index, animate: animate)
            }
            
            // Center node
            CenterNode(isAnimating: nodeAnimations[0])
            
            // Surrounding nodes
            ForEach(0..<5) { index in
                SurroundingNode(index: index, isAnimating: nodeAnimations[index + 1])
            }
        }
    }
}

struct ConnectionLine: View {
    let index: Int
    let animate: Bool
    
    private var angle: Double {
        Double(index) * 72 * .pi / 180
    }
    
    private var endPoint: CGPoint {
        let center = CGPoint(x: 150, y: 150)
        return CGPoint(
            x: center.x + cos(angle) * 100,
            y: center.y + sin(angle) * 100
        )
    }
    
    private var gradientEndPoint: UnitPoint {
        UnitPoint(
            x: 0.5 + cos(angle) * 0.5,
            y: 0.5 + sin(angle) * 0.5
        )
    }
    
    var body: some View {
        Path { path in
            let center = CGPoint(x: 150, y: 150)
            path.move(to: center)
            path.addLine(to: endPoint)
        }
        .stroke(
            LinearGradient(
                colors: [.white.opacity(0.2), .white.opacity(0.6)],
                startPoint: .center,
                endPoint: gradientEndPoint
            ),
            lineWidth: 2
        )
        .opacity(animate ? 1 : 0)
        .animation(.easeOut(duration: 0.5).delay(Double(index) * 0.1), value: animate)
    }
}

struct CenterNode: View {
    let isAnimating: Bool
    
    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: OlasDesign.Colors.primaryGradient,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 60, height: 60)
            .overlay(
                Image(systemName: "person.fill")
                    .foregroundStyle(.white)
                    .font(.title2)
            )
            .scaleEffect(isAnimating ? 1.1 : 1.0)
            .animation(
                .easeInOut(duration: 1.5).repeatForever(autoreverses: true),
                value: isAnimating
            )
    }
}

struct SurroundingNode: View {
    let index: Int
    let isAnimating: Bool
    
    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [.purple, .pink],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 40, height: 40)
            .overlay(
                Image(systemName: "server.rack")
                    .foregroundStyle(.white)
                    .font(.caption)
            )
            .offset(
                x: cos(Double(index) * 72 * .pi / 180) * 100,
                y: sin(Double(index) * 72 * .pi / 180) * 100
            )
            .scaleEffect(isAnimating ? 1.1 : 1.0)
            .animation(
                .easeInOut(duration: 1.5)
                .repeatForever(autoreverses: true)
                .delay(Double(index) * 0.2),
                value: isAnimating
            )
    }
}

// MARK: - Key Generation
struct KeyGenerationView: View {
    @Environment(NostrManager.self) private var nostrManager
    @EnvironmentObject var appState: AppState
    @State private var animate = false
    @State private var particles: [Particle] = []
    @State private var keyGenerated = false
    @State private var privateKey: String = ""
    @State private var showMnemonic = false
    
    struct Particle: Identifiable {
        let id = UUID()
        var position: CGPoint
        var velocity: CGVector
        var opacity: Double
        var scale: CGFloat
    }
    
    var body: some View {
        VStack(spacing: OlasDesign.Spacing.xxxl) {
            Spacer()
            
            // Particle animation container
            ZStack {
                // Particles
                ForEach(particles) { particle in
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.purple, .pink, .blue].shuffled(),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 10, height: 10)
                        .scaleEffect(particle.scale)
                        .opacity(particle.opacity)
                        .position(particle.position)
                }
                
                // Key visualization
                if keyGenerated {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: OlasDesign.Colors.primaryGradient,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 120, height: 120)
                            .blur(radius: 20)
                            .scaleEffect(animate ? 1.2 : 1.0)
                            .animation(
                                .easeInOut(duration: 2).repeatForever(autoreverses: true),
                                value: animate
                            )
                        
                        Image(systemName: "key.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.white)
                            .rotationEffect(.degrees(animate ? 360 : 0))
                            .animation(
                                .linear(duration: 20).repeatForever(autoreverses: false),
                                value: animate
                            )
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: 300, height: 300)
            .onAppear {
                startParticleAnimation()
            }
            
            VStack(spacing: OlasDesign.Spacing.lg) {
                Text(keyGenerated ? "Your Identity is Ready" : "Creating Your Identity")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                
                Text(keyGenerated ? 
                     "Your unique cryptographic identity has been created" :
                     "Generating your secure keys...")
                    .font(OlasDesign.Typography.body)
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
            
            if keyGenerated {
                VStack(spacing: OlasDesign.Spacing.md) {
                    Button {
                        showMnemonic = true
                        #if os(iOS)
                        OlasDesign.Haptic.impact(.medium)
                        #else
                        OlasDesign.Haptic.impact(0)
                        #endif
                    } label: {
                        HStack {
                            Image(systemName: "lock.shield.fill")
                            Text("Secure My Account")
                        }
                        .font(OlasDesign.Typography.bodyBold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            LinearGradient(
                                colors: OlasDesign.Colors.primaryGradient,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    
                    Button {
                        completeOnboarding()
                    } label: {
                        Text("I'll do this later")
                            .font(OlasDesign.Typography.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .padding(.horizontal, OlasDesign.Spacing.xl)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            // Page indicator
            HStack(spacing: 8) {
                ForEach(0..<4) { index in
                    Capsule()
                        .fill(index == 2 ? .white : .white.opacity(0.3))
                        .frame(width: index == 2 ? 24 : 8, height: 8)
                }
            }
            .padding(.bottom, 50)
        }
        .sheet(isPresented: $showMnemonic) {
            MnemonicBackupView(privateKey: privateKey) {
                completeOnboarding()
            }
        }
    }
    
    private func startParticleAnimation() {
        // Create initial particles
        for _ in 0..<50 {
            let particle = Particle(
                position: CGPoint(x: CGFloat.random(in: 50...250),
                                y: CGFloat.random(in: 50...250)),
                velocity: CGVector(dx: CGFloat.random(in: -2...2),
                                 dy: CGFloat.random(in: -2...2)),
                opacity: Double.random(in: 0.3...1.0),
                scale: CGFloat.random(in: 0.5...1.5)
            )
            particles.append(particle)
        }
        
        // Animate particles converging
        Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { timer in
            withAnimation(.linear(duration: 0.016)) {
                for i in particles.indices {
                    // Move towards center
                    let center = CGPoint(x: 150, y: 150)
                    let dx = (center.x - particles[i].position.x) * 0.02
                    let dy = (center.y - particles[i].position.y) * 0.02
                    
                    particles[i].position.x += dx
                    particles[i].position.y += dy
                    particles[i].opacity *= 0.98
                    
                    // Remove particles that are too faded
                    if particles[i].opacity < 0.1 {
                        particles[i].position = CGPoint(
                            x: CGFloat.random(in: 50...250),
                            y: CGFloat.random(in: 50...250)
                        )
                        particles[i].opacity = 1.0
                    }
                }
            }
        }
        
        // Generate key after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            generateKey()
        }
    }
    
    private func generateKey() {
        privateKey = generateRandomKey()
        
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            keyGenerated = true
            animate = true
        }
        
        OlasDesign.Haptic.success()
    }
    
    private func generateRandomKey() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
    
    private func completeOnboarding() {
        Task {
            do {
                _ = try await nostrManager.createNewAccount(
                    displayName: "Olas User",
                    about: "Visual storyteller on Nostr 📸"
                )
            } catch {
                print("Failed to create account: \(error)")
            }
        }
    }
}

// MARK: - Security Education
struct SecurityEducationView: View {
    @State private var animate = false
    @State private var lockAnimation = false
    
    var body: some View {
        VStack(spacing: OlasDesign.Spacing.xxxl) {
            Spacer()
            
            // Lock animation
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.green, .mint],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 160, height: 160)
                    .blur(radius: 30)
                    .scaleEffect(lockAnimation ? 1.2 : 0.8)
                    .animation(
                        .easeInOut(duration: 2).repeatForever(autoreverses: true),
                        value: lockAnimation
                    )
                
                Image(systemName: lockAnimation ? "lock.fill" : "lock.open.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.white)
                    .animation(.spring(response: 0.5, dampingFraction: 0.6), value: lockAnimation)
            }
            
            VStack(spacing: OlasDesign.Spacing.lg) {
                Text("Your Keys, Your Control")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                
                VStack(alignment: .leading, spacing: OlasDesign.Spacing.md) {
                    SecurityPoint(
                        icon: "key.fill",
                        text: "You own your identity",
                        delay: 0.1
                    )
                    
                    SecurityPoint(
                        icon: "lock.shield.fill",
                        text: "No company can ban you",
                        delay: 0.2
                    )
                    
                    SecurityPoint(
                        icon: "arrow.triangle.2.circlepath",
                        text: "Take your content anywhere",
                        delay: 0.3
                    )
                }
            }
            .opacity(animate ? 1 : 0)
            .offset(y: animate ? 0 : 20)
            .animation(.easeOut(duration: 0.8).delay(0.5), value: animate)
            
            Spacer()
            
            // Page indicator
            HStack(spacing: 8) {
                ForEach(0..<4) { index in
                    Capsule()
                        .fill(index == 3 ? .white : .white.opacity(0.3))
                        .frame(width: index == 3 ? 24 : 8, height: 8)
                }
            }
            .padding(.bottom, 50)
        }
        .padding(.horizontal, OlasDesign.Spacing.xl)
        .onAppear {
            animate = true
            withAnimation(.easeInOut(duration: 0.8).delay(0.3)) {
                lockAnimation = true
            }
        }
    }
}

struct SecurityPoint: View {
    let icon: String
    let text: String
    let delay: Double
    @State private var animate = false
    
    var body: some View {
        HStack(spacing: OlasDesign.Spacing.md) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.green, .mint],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 32)
            
            Text(text)
                .font(OlasDesign.Typography.body)
                .foregroundStyle(.white.opacity(0.9))
        }
        .opacity(animate ? 1 : 0)
        .offset(x: animate ? 0 : -20)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(delay)) {
                animate = true
            }
        }
    }
}

// MARK: - Mnemonic Backup View
struct MnemonicBackupView: View {
    let privateKey: String
    let onComplete: () -> Void
    @State private var words: [String] = []
    @State private var copiedWords = Set<Int>()
    @State private var allCopied = false
    
    var body: some View {
        ZStack {
            TimeBasedGradient()
                .ignoresSafeArea()
            
            VStack(spacing: OlasDesign.Spacing.xl) {
                // Header
                VStack(spacing: OlasDesign.Spacing.md) {
                    Image(systemName: "doc.on.doc.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.white)
                    
                    Text("Save Your Recovery Words")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    
                    Text("Write these down in order and keep them safe")
                        .font(OlasDesign.Typography.body)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(.top, OlasDesign.Spacing.xxxl)
                
                // Mnemonic words grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: OlasDesign.Spacing.md) {
                    ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                        MnemonicWordView(
                            word: word,
                            number: index + 1,
                            isCopied: copiedWords.contains(index)
                        ) {
                            copiedWords.insert(index)
                            #if os(iOS)
                            OlasDesign.Haptic.impact(.light)
                            #else
                            OlasDesign.Haptic.impact(0)
                            #endif
                            
                            if copiedWords.count == words.count {
                                withAnimation(.spring()) {
                                    allCopied = true
                                }
                                OlasDesign.Haptic.success()
                            }
                        }
                    }
                }
                .padding(.horizontal, OlasDesign.Spacing.xl)
                
                Spacer()
                
                // Action buttons
                VStack(spacing: OlasDesign.Spacing.md) {
                    Button {
                        #if os(iOS)
                        OlasDesign.Haptic.impact(.medium)
                        #else
                        OlasDesign.Haptic.impact(0)
                        #endif
                        onComplete()
                    } label: {
                        Text(allCopied ? "I've Saved My Words" : "Copy All Words First")
                        .font(OlasDesign.Typography.bodyBold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            LinearGradient(
                                colors: allCopied ? OlasDesign.Colors.primaryGradient : [.gray],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .disabled(!allCopied)
                    
                    Text("⚠️ Never share these words with anyone")
                        .font(OlasDesign.Typography.caption)
                        .foregroundStyle(.yellow)
                }
                .padding(.horizontal, OlasDesign.Spacing.xl)
                .padding(.bottom, OlasDesign.Spacing.xxxl)
            }
        }
        .onAppear {
            generateMnemonic()
        }
    }
    
    private func generateMnemonic() {
        // In a real app, this would convert the private key to a proper BIP39 mnemonic
        // For now, we'll generate sample words
        words = [
            "laptop", "ancient", "energy", "turtle",
            "space", "panda", "sunset", "wisdom",
            "ocean", "ladder", "crystal", "voyage"
        ]
    }
}

struct MnemonicWordView: View {
    let word: String
    let number: Int
    let isCopied: Bool
    let onTap: () -> Void
    @State private var animate = false
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: OlasDesign.Spacing.sm) {
                Text("\(number).")
                    .font(OlasDesign.Typography.caption)
                    .foregroundStyle(.white.opacity(0.6))
                
                Text(word)
                    .font(OlasDesign.Typography.bodyBold)
                    .foregroundStyle(.white)
                
                Spacer()
                
                Image(systemName: isCopied ? "checkmark.circle.fill" : "doc.on.doc")
                    .foregroundStyle(isCopied ? .green : .white.opacity(0.6))
                    .animation(.spring(), value: isCopied)
            }
            .padding(.horizontal, OlasDesign.Spacing.md)
            .padding(.vertical, OlasDesign.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.white.opacity(isCopied ? 0.2 : 0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.white.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .scaleEffect(animate ? 1 : 0.8)
        .opacity(animate ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(Double(number) * 0.05)) {
                animate = true
            }
        }
    }
}



#Preview {
    OnboardingView()
        .environmentObject(AppState())
}