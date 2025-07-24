import SwiftUI
import NDKSwift

struct AuthenticationView: View {
    @EnvironmentObject var nostrManager: NostrManager
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    
    // Animation states
    @State private var logoScale: CGFloat = 0.3
    @State private var logoOpacity: Double = 0
    @State private var logoRotation: Double = -180
    @State private var titleOffset: CGFloat = 50
    @State private var titleOpacity: Double = 0
    @State private var sloganOpacity: Double = 0
    @State private var sloganScale: CGFloat = 0.8
    @State private var pulseScale: CGFloat = 1
    @State private var glowOpacity: Double = 0
    @State private var electricityOffset: CGFloat = -100
    @State private var buttonsOffset: CGFloat = 100
    @State private var buttonsOpacity: Double = 0
    
    // Auth states
    @State private var showingLogin = false
    @State private var nsecInput = ""
    @State private var showPassword = false
    @State private var isLoggingIn = false
    @State private var errorMessage = ""
    @State private var showError = false
    @State private var showingFeatureNotImplemented = false
    
    var body: some View {
        ZStack {
            // Electric field effect
            ForEach(0..<5) { index in
                ElectricArc(
                    startPoint: CGPoint(x: 0.5, y: 0.5),
                    endPoint: CGPoint(
                        x: 0.5 + cos(Double(index) * .pi / 2.5) * 0.4,
                        y: 0.5 + sin(Double(index) * .pi / 2.5) * 0.4
                    )
                )
                .stroke(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.purple.opacity(0.6),
                            Color.blue.opacity(0.3),
                            Color.clear
                        ]),
                        startPoint: .center,
                        endPoint: .bottom
                    ),
                    lineWidth: 2
                )
                .blur(radius: 3)
                .opacity(glowOpacity)
                .offset(y: electricityOffset)
                .animation(
                    .easeInOut(duration: 2)
                    .delay(Double(index) * 0.1)
                    .repeatForever(autoreverses: true),
                    value: electricityOffset
                )
            }
            
            VStack(spacing: 40) {
                Spacer()
                
                // Logo and title
                ZStack {
                    // Outer pulsing glow
                    Circle()
                        .fill(
                            RadialGradient(
                                gradient: Gradient(colors: [
                                    Color.purple.opacity(0.8),
                                    Color.blue.opacity(0.4),
                                    Color.clear
                                ]),
                                center: .center,
                                startRadius: 10,
                                endRadius: 120
                            )
                        )
                        .frame(width: 280, height: 280)
                        .blur(radius: 30)
                        .scaleEffect(pulseScale)
                        .opacity(logoOpacity * 0.7)
                    
                    // Logo background circle
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.purple,
                                    Color.purple.opacity(0.9),
                                    Color(red: 0.4, green: 0.1, blue: 0.8)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 140, height: 140)
                        .shadow(color: Color.purple.opacity(0.5), radius: 20, x: 0, y: 5)
                        .scaleEffect(logoScale)
                        .opacity(logoOpacity)
                        .rotationEffect(.degrees(logoRotation))
                    
                    // Logo icon
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.white)
                        .scaleEffect(logoScale)
                        .opacity(logoOpacity)
                        .rotationEffect(.degrees(logoRotation))
                }
                
                // Title
                Text("SOCRATES")
                    .font(.system(size: 52, weight: .black, design: .default))
                    .tracking(4)
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
                    .shadow(color: Color.purple.opacity(0.3), radius: 10, x: 0, y: 2)
                    .opacity(titleOpacity)
                    .offset(y: titleOffset)
                
                // Slogan
                Text("WISDOM THROUGH VOICE")
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(Color.white.opacity(0.7))
                    .scaleEffect(sloganScale)
                    .opacity(sloganOpacity)
                
                Spacer()
                
                if !showingLogin {
                    // Login buttons
                    VStack(spacing: 16) {
                        Button(action: { showingLogin = true }) {
                            HStack {
                                Image(systemName: "key.fill")
                                    .font(.system(size: 20))
                                Text("Login with Private Key")
                                    .font(.system(size: 18, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.purple,
                                        Color(red: 0.5, green: 0.1, blue: 0.9)
                                    ]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: Color.purple.opacity(0.3), radius: 10, x: 0, y: 4)
                        }
                        
                        Button(action: { 
                            showingFeatureNotImplemented = true
                        }) {
                            HStack {
                                Image(systemName: "link")
                                    .font(.system(size: 20))
                                Text("Login with Nostr Connect")
                                    .font(.system(size: 18, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Color.white.opacity(0.1))
                            .foregroundColor(.white)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .opacity(0.5) // Disabled for now
                        .disabled(true)
                        
                        Text("Your voice, your wisdom")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.4))
                            .padding(.top, 8)
                    }
                    .padding(.horizontal, 32)
                    .offset(y: buttonsOffset)
                    .opacity(buttonsOpacity)
                } else {
                    // Login form
                    loginForm
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                }
                
                Spacer()
                    .frame(height: 60)
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .alert("Feature Not Implemented", isPresented: $showingFeatureNotImplemented) {
            Button("OK") { }
        } message: {
            Text("Nostr Connect login is not yet implemented in this demo app.")
        }
        .onAppear {
            animateIntro()
        }
    }
    
    private var loginForm: some View {
        VStack(spacing: 30) {
            // Back button
            HStack {
                Button(action: {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                        showingLogin = false
                        nsecInput = ""
                        showPassword = false
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .medium))
                        Text("Back")
                            .font(.system(size: 16, weight: .medium))
                    }
                    .foregroundColor(Color.purple)
                }
                Spacer()
            }
            
            VStack(spacing: 20) {
                Text("Welcome Back")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                
                Text("Enter your private key to continue")
                    .font(.system(size: 14))
                    .foregroundColor(Color.white.opacity(0.6))
            }
            
            // Input section
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Private Key")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.8))
                    
                    HStack {
                        if showPassword {
                            TextField("nsec1...", text: $nsecInput)
                                .textContentType(.password)
                                .textInputAutocapitalization(.never)
                                .font(.system(.body, design: .monospaced))
                        } else {
                            SecureField("nsec1...", text: $nsecInput)
                                .textContentType(.password)
                                .textInputAutocapitalization(.never)
                                .font(.system(.body, design: .monospaced))
                        }
                        
                        Button(action: { showPassword.toggle() }) {
                            Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                                .font(.callout)
                                .foregroundColor(Color.white.opacity(0.6))
                        }
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.08))
                    .foregroundColor(.white)
                    .accentColor(.purple)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    
                    HStack {
                        Image(systemName: "lock.shield.fill")
                            .font(.caption)
                            .foregroundColor(Color.white.opacity(0.4))
                        
                        Text("Your key is stored securely on this device")
                            .font(.caption)
                            .foregroundColor(Color.white.opacity(0.4))
                    }
                    .padding(.top, 4)
                }
                
                // Login button
                Button(action: login) {
                    ZStack {
                        if isLoggingIn {
                            HStack(spacing: 12) {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.9)
                                
                                Text("Logging in...")
                                    .fontWeight(.semibold)
                            }
                        } else {
                            HStack {
                                Image(systemName: "arrow.right.circle.fill")
                                Text("Log In")
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                nsecInput.isEmpty ? Color.gray : Color.purple,
                                nsecInput.isEmpty ? Color.gray.opacity(0.8) : Color(red: 0.5, green: 0.1, blue: 0.9)
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: nsecInput.isEmpty ? Color.clear : Color.purple.opacity(0.3), radius: 10, x: 0, y: 4)
                    .disabled(nsecInput.isEmpty || isLoggingIn)
                }
            }
        }
        .padding(.horizontal, 32)
    }
    
    private func animateIntro() {
        // Logo animation with rotation
        withAnimation(.spring(response: 1.2, dampingFraction: 0.7)) {
            logoScale = 1
            logoOpacity = 1
            logoRotation = 0
        }
        
        // Glow effects
        withAnimation(.easeInOut(duration: 1.5).delay(0.2)) {
            glowOpacity = 0.8
        }
        
        // Start electricity animation
        withAnimation(.easeInOut(duration: 2).delay(0.5).repeatForever(autoreverses: true)) {
            electricityOffset = 100
        }
        
        // Title animation
        withAnimation(.easeOut(duration: 0.8).delay(0.8)) {
            titleOffset = 0
            titleOpacity = 1
        }
        
        // Slogan animation
        withAnimation(.easeOut(duration: 0.8).delay(1.2)) {
            sloganOpacity = 1
            sloganScale = 1
        }
        
        // Pulse animation
        withAnimation(.easeInOut(duration: 1.5).delay(1).repeatForever(autoreverses: true)) {
            pulseScale = 1.1
        }
        
        // Button slide up animation
        withAnimation(.spring(response: 0.8, dampingFraction: 0.8).delay(2.0)) {
            buttonsOffset = 0
            buttonsOpacity = 1
        }
    }
    
    private func login() {
        isLoggingIn = true
        
        Task {
            do {
                let signer = try NDKPrivateKeySigner(nsec: nsecInput)
                let sessionData = try await nostrManager.login(with: signer)
                
                await MainActor.run {
                    appState.isAuthenticated = true
                    appState.currentUser = nostrManager.ndk?.getUser(sessionData.pubkey)
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isLoggingIn = false
                }
            }
        }
    }
}

// MARK: - Electric Arc Shape
struct ElectricArc: Shape {
    let startPoint: CGPoint
    let endPoint: CGPoint
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let start = CGPoint(
            x: startPoint.x * rect.width,
            y: startPoint.y * rect.height
        )
        let end = CGPoint(
            x: endPoint.x * rect.width,
            y: endPoint.y * rect.height
        )
        
        path.move(to: start)
        
        // Create a jagged lightning effect
        let segments = 8
        
        for i in 1...segments {
            let progress = CGFloat(i) / CGFloat(segments)
            let baseX = start.x + (end.x - start.x) * progress
            let baseY = start.y + (end.y - start.y) * progress
            
            // Add random offset for electric effect
            let offsetRange: CGFloat = 20
            let offsetX = CGFloat.random(in: -offsetRange...offsetRange)
            let offsetY = CGFloat.random(in: -offsetRange...offsetRange)
            
            let point = CGPoint(x: baseX + offsetX, y: baseY + offsetY)
            
            if i == segments {
                path.addLine(to: end)
            } else {
                path.addLine(to: point)
            }
        }
        
        return path
    }
}