import SwiftUI
import NDKSwift

struct PostaWelcomeView: View {
    @Environment(NDKAuthManager.self) var authManager
    @Environment(NDKManager.self) var ndkManager
    @Environment(RelayManager.self) var relayManager
    @Environment(\.colorScheme) private var colorScheme
    
    // Animation states
    @State private var logoScale: CGFloat = 0.3
    @State private var logoOpacity: Double = 0
    @State private var logoRotation: Double = -180
    @State private var titleOffset: CGFloat = 50
    @State private var titleOpacity: Double = 0
    @State private var sloganOpacity: Double = 0
    @State private var sloganScale: CGFloat = 0.8
    @State private var contentOpacity: Double = 0
    @State private var glowOpacity: Double = 0
    @State private var pulseScale: CGFloat = 1
    @State private var electricityPhase: CGFloat = 0
    
    // Button animation states
    @State private var buttonsOffset: CGFloat = 100
    @State private var buttonsOpacity: Double = 0
    @State private var showButtons = false
    
    // Auth states
    @State private var loginInput: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingLogin = true
    @State private var loginMethod: LoginMethod = .privateKey
    
    // Sheet states
    @State private var showCreateAccount = false
    @State private var showImportAccount = false
    
    // Logo animation
    @State private var showAnimatedLogo = false
    
    enum LoginMethod: String, CaseIterable {
        case privateKey = "Private Key"
        case nip46 = "NIP-46 (Bunker)"
        
        var placeholder: String {
            switch self {
            case .privateKey:
                return "Enter hex or nsec..."
            case .nip46:
                return "bunker:// or npub@domain.com"
            }
        }
    }
    
    var body: some View {
        ZStack {
            // Modern animated background
            PostaBackgroundView()
            
            // Electric field effects
            WelcomeElectricFieldView()
                .opacity(glowOpacity * 0.5)
            
            VStack(spacing: 40) {
                Spacer()
                
                // Logo section with glow
                ZStack {
                    // Outer glow
                    Circle()
                        .fill(
                            RadialGradient(
                                gradient: Gradient(colors: [
                                    PostaColors.electricPurple.opacity(0.6),
                                    PostaColors.glowPink.opacity(0.3),
                                    Color.clear
                                ]),
                                center: .center,
                                startRadius: 20,
                                endRadius: 120
                            )
                        )
                        .frame(width: 280, height: 280)
                        .blur(radius: 30)
                        .scaleEffect(pulseScale)
                        .opacity(logoOpacity * 0.7)
                    
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
                            .frame(width: 160, height: 160)
                            .shadow(color: PostaColors.electricPurple.opacity(0.5), radius: 20, x: 0, y: 5)
                        
                        // Animated Logo
                        if showAnimatedLogo {
                            AnimatedEnvelopeView(size: 100, color: .white)
                        } else {
                            PostaLogoView(size: 100, color: .white)
                        }
                    }
                    .scaleEffect(logoScale)
                    .opacity(logoOpacity)
                    .rotationEffect(.degrees(logoRotation))
                }
                
                // Title and slogan
                VStack(spacing: 20) {
                    Text("POSTA")
                        .font(.system(size: 56, weight: .black, design: .default))
                        .tracking(5)
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
                        .shadow(color: PostaColors.electricPurple.opacity(0.4), radius: 15, x: 0, y: 3)
                        .offset(y: titleOffset)
                        .opacity(titleOpacity)
                        .postaShimmer()
                    
                    Text("ENCRYPTED NOSTR MESSAGING")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .tracking(3)
                        .foregroundColor(PostaColors.textSecondary)
                        .scaleEffect(sloganScale)
                        .opacity(sloganOpacity)
                }
                
                Spacer()
                
                // Auth buttons that slide in
                if showButtons {
                    VStack(spacing: 16) {
                        // Create new account button
                        Button(action: {
                            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                                showCreateAccount = true
                            }
                        }) {
                            HStack {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 20))
                                Text("Create New Identity")
                                    .font(.system(size: 18, weight: .semibold))
                            }
                        }
                        .buttonStyle(PostaPrimaryButtonStyle())
                        
                        // Import existing account button
                        Button(action: {
                            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                                showImportAccount = true
                            }
                        }) {
                            HStack {
                                Image(systemName: "key.horizontal.fill")
                                    .font(.system(size: 20))
                                Text("Import Existing")
                                    .font(.system(size: 18, weight: .semibold))
                            }
                        }
                        .buttonStyle(PostaSecondaryButtonStyle())
                        
                        // Info text
                        HStack(spacing: 6) {
                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 12))
                            Text("Your keys, your messages")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(PostaColors.textTertiary)
                        .padding(.top, 12)
                    }
                    .padding(.horizontal, 32)
                    .offset(y: buttonsOffset)
                    .opacity(buttonsOpacity)
                }
                
                Spacer()
                    .frame(height: 80)
            }
        }
        .onAppear {
            animateWelcome()
        }
        .sheet(isPresented: $showCreateAccount) {
            CreateAccountSheet(authManager: authManager, ndkManager: ndkManager)
        }
        .sheet(isPresented: $showImportAccount) {
            ImportAccountSheet(authManager: authManager, ndkManager: ndkManager, loginMethod: $loginMethod)
        }
    }
    
    private func animateWelcome() {
        // Logo animation with rotation
        withAnimation(.spring(response: 1.2, dampingFraction: 0.7)) {
            logoScale = 1
            logoOpacity = 1
            logoRotation = 0
        }
        
        // Glow effects
        withAnimation(.easeInOut(duration: 1.5).delay(0.3)) {
            glowOpacity = 1
        }
        
        // Pulse animation
        withAnimation(.easeInOut(duration: 2).delay(1).repeatForever(autoreverses: true)) {
            pulseScale = 1.15
        }
        
        // Show animated logo after initial animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.5)) {
                showAnimatedLogo = true
            }
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
        
        // Content fade in
        withAnimation(.easeInOut(duration: 0.8).delay(1.5)) {
            contentOpacity = 1
        }
        
        // Show and animate buttons after the main animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            showButtons = true
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
                buttonsOffset = 0
                buttonsOpacity = 1
            }
        }
    }
}

// MARK: - Electric Field View
struct WelcomeElectricFieldView: View {
    @State private var animationPhase: CGFloat = 0
    
    var body: some View {
        GeometryReader { geometry in
            ForEach(0..<5) { index in
                Path { path in
                    let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    let angle = Double(index) * (2 * .pi / 5) + animationPhase
                    let endPoint = CGPoint(
                        x: center.x + Foundation.cos(angle) * geometry.size.width * 0.4,
                        y: center.y + Foundation.sin(angle) * geometry.size.height * 0.4
                    )
                    
                    path.move(to: center)
                    
                    // Create jagged lightning path
                    let segments = 8
                    for j in 1...segments {
                        let progress = CGFloat(j) / CGFloat(segments)
                        let baseX = center.x + (endPoint.x - center.x) * progress
                        let baseY = center.y + (endPoint.y - center.y) * progress
                        
                        let offsetRange: CGFloat = j == segments ? 0 : 20
                        let offsetX = CGFloat.random(in: -offsetRange...offsetRange)
                        let offsetY = CGFloat.random(in: -offsetRange...offsetRange)
                        
                        let point = j == segments ? endPoint : CGPoint(x: baseX + offsetX, y: baseY + offsetY)
                        path.addLine(to: point)
                    }
                }
                .stroke(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            PostaColors.electricPurple.opacity(0.6),
                            PostaColors.glowPink.opacity(0.3),
                            Color.clear
                        ]),
                        startPoint: .center,
                        endPoint: .bottom
                    ),
                    lineWidth: 2
                )
                .blur(radius: 3)
                .animation(
                    .linear(duration: Double.random(in: 2...4))
                    .delay(Double(index) * 0.2)
                    .repeatForever(autoreverses: false),
                    value: animationPhase
                )
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 10).repeatForever(autoreverses: false)) {
                animationPhase = .pi * 2
            }
        }
    }
}

// MARK: - Create Account Sheet
struct CreateAccountSheet: View {
    let authManager: NDKAuthManager
    let ndkManager: NDKManager
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showSuccess = false
    
    var body: some View {
        NavigationView {
            ZStack {
                // Modern background
                PostaBackgroundView()
                
                VStack(spacing: 30) {
                    // Header with icon
                    VStack(spacing: 20) {
                        ZStack {
                            // Glow effect
                            Circle()
                                .fill(
                                    RadialGradient(
                                        gradient: Gradient(colors: [
                                            PostaColors.electricPurple.opacity(0.4),
                                            PostaColors.glowPink.opacity(0.2),
                                            Color.clear
                                        ]),
                                        center: .center,
                                        startRadius: 10,
                                        endRadius: 60
                                    )
                                )
                                .frame(width: 140, height: 140)
                                .blur(radius: 20)
                            
                            Circle()
                                .fill(
                                    LinearGradient(
                                        gradient: PostaColors.primaryGradient,
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 80, height: 80)
                                .shadow(color: PostaColors.electricPurple.opacity(0.3), radius: 10, x: 0, y: 3)
                            
                            Image(systemName: "sparkles")
                                .font(.system(size: 40))
                                .foregroundColor(.white)
                                .symbolEffect(.bounce, value: showSuccess)
                        }
                        .padding(.top, 20)
                        
                        Text("Create New Identity")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(PostaColors.textPrimary)
                        
                        Text("Generate a secure keypair for your Nostr identity")
                            .font(.system(size: 16))
                            .foregroundColor(PostaColors.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    
                    Spacer()
                    
                    // Features list
                    VStack(alignment: .leading, spacing: 20) {
                        FeatureRow(
                            icon: "lock.shield.fill",
                            text: "End-to-end encrypted messages",
                            color: PostaColors.electricPurple
                        )
                        FeatureRow(
                            icon: "key.horizontal.fill",
                            text: "Your keys stay on your device",
                            color: PostaColors.neonBlue
                        )
                        FeatureRow(
                            icon: "network",
                            text: "Decentralized communication",
                            color: PostaColors.glowPink
                        )
                    }
                    .padding(.horizontal, 32)
                    
                    Spacer()
                    
                    // Error message
                    if let errorMessage = errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(errorMessage)
                                .font(.system(size: 14))
                                .foregroundColor(.red)
                        }
                        .padding(.horizontal)
                        .padding(12)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(12)
                        .padding(.horizontal, 32)
                    }
                    
                    // Create button
                    Button(action: {
                        Task {
                            await createAccount()
                        }
                    }) {
                        if isLoading {
                            LoadingDots(dotSize: 10, color: .white)
                        } else {
                            HStack {
                                Image(systemName: "sparkles")
                                Text("Generate Identity")
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                    .buttonStyle(PostaPrimaryButtonStyle(isEnabled: !isLoading))
                    .disabled(isLoading)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(PostaColors.textSecondary)
                    }
                }
            }
        }
    }
    
    private func createAccount() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let signer = try NDKPrivateKeySigner.generate()
            _ = try await authManager.createSession(with: signer)
            showSuccess = true
        } catch {
            errorMessage = "Failed to create account: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
}

// MARK: - Feature Row Component
struct FeatureRow: View {
    let icon: String
    let text: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(color)
                .frame(width: 40)
            
            Text(text)
                .font(.system(size: 16))
                .foregroundColor(.primary)
            
            Spacer()
        }
    }
}

// MARK: - Import Account Sheet
struct ImportAccountSheet: View {
    let authManager: NDKAuthManager
    let ndkManager: NDKManager
    @Binding var loginMethod: PostaWelcomeView.LoginMethod
    @Environment(\.dismiss) private var dismiss
    @State private var loginInput: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingPassword = false
    @State private var showScanner = false
    
    var body: some View {
        NavigationView {
            ZStack {
                // Modern background
                PostaBackgroundView()
                
                VStack(spacing: 24) {
                    // Header with icon
                    VStack(spacing: 20) {
                        ZStack {
                            // Glow effect
                            Circle()
                                .fill(
                                    RadialGradient(
                                        gradient: Gradient(colors: [
                                            PostaColors.neonBlue.opacity(0.4),
                                            PostaColors.electricPurple.opacity(0.2),
                                            Color.clear
                                        ]),
                                        center: .center,
                                        startRadius: 10,
                                        endRadius: 60
                                    )
                                )
                                .frame(width: 140, height: 140)
                                .blur(radius: 20)
                            
                            Circle()
                                .fill(
                                    LinearGradient(
                                        gradient: PostaColors.secondaryGradient,
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 80, height: 80)
                                .shadow(color: PostaColors.neonBlue.opacity(0.3), radius: 10, x: 0, y: 3)
                            
                            Image(systemName: "key.horizontal.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.white)
                        }
                        .padding(.top, 20)
                        
                        Text("Import Identity")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(PostaColors.textPrimary)
                        
                        Text("Enter your private key or bunker URL")
                            .font(.system(size: 16))
                            .foregroundColor(PostaColors.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    
                    // Login method picker with modern styling
                    HStack(spacing: 8) {
                        ForEach(PostaWelcomeView.LoginMethod.allCases, id: \.self) { method in
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    loginMethod = method
                                }
                            }) {
                                Text(method.rawValue)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(loginMethod == method ? .white : PostaColors.textSecondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(
                                        loginMethod == method ?
                                        LinearGradient(
                                            gradient: PostaColors.primaryGradient,
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        ) : LinearGradient(
                                            gradient: Gradient(colors: [PostaColors.surfaceColor]),
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .cornerRadius(12)
                            }
                        }
                    }
                    .padding(.horizontal, 32)
                    
                    // Input field with modern design
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            HStack {
                                if loginMethod == .privateKey && !showingPassword {
                                    SecureField(loginMethod.placeholder, text: $loginInput)
                                        .textFieldStyle(PlainTextFieldStyle())
                                        .font(.system(size: 16, design: .monospaced))
                                } else {
                                    TextField(loginMethod.placeholder, text: $loginInput)
                                        .textFieldStyle(PlainTextFieldStyle())
                                        .font(.system(size: 16, design: .monospaced))
                                        .autocapitalization(.none)
                                        .disableAutocorrection(true)
                                }
                                
                                if loginMethod == .privateKey {
                                    Button(action: { showingPassword.toggle() }) {
                                        Image(systemName: showingPassword ? "eye.slash.fill" : "eye.fill")
                                            .font(.system(size: 16))
                                            .foregroundColor(PostaColors.textSecondary)
                                    }
                                }
                                
                                Button(action: { showScanner = true }) {
                                    Image(systemName: "qrcode.viewfinder")
                                        .font(.system(size: 20))
                                        .foregroundColor(PostaColors.electricPurple)
                                }
                            }
                            .padding(18)
                            .background(PostaColors.surfaceColor)
                            .foregroundColor(.white)
                            .accentColor(PostaColors.electricPurple)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(PostaColors.borderColor, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        
                        if loginMethod == .privateKey {
                            HStack(spacing: 6) {
                                Image(systemName: "info.circle.fill")
                                    .font(.system(size: 12))
                                Text("Accepts hex format or nsec")
                                    .font(.system(size: 13))
                            }
                            .foregroundColor(PostaColors.textTertiary)
                            .padding(.horizontal, 8)
                        }
                    }
                    .padding(.horizontal, 32)
                    
                    // Error message
                    if let errorMessage = errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(errorMessage)
                                .font(.system(size: 14))
                                .foregroundColor(.red)
                        }
                        .padding(.horizontal)
                        .padding(12)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(12)
                        .padding(.horizontal, 32)
                    }
                    
                    Spacer()
                    
                    // Import button
                    Button(action: {
                        Task {
                            await performLogin()
                        }
                    }) {
                        if isLoading {
                            LoadingDots(dotSize: 10, color: .white)
                        } else {
                            HStack {
                                Image(systemName: "arrow.down.circle.fill")
                                Text("Import Identity")
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                    .buttonStyle(PostaPrimaryButtonStyle(isEnabled: !loginInput.isEmpty))
                    .disabled(isLoading || loginInput.isEmpty)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(PostaColors.textSecondary)
                    }
                }
            }
        }
        .sheet(isPresented: $showScanner) {
            QRScannerView { scannedValue in
                loginInput = scannedValue
                showScanner = false
            }
        }
    }
    
    private func performLogin() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let signer: any NDKSigner
            
            switch loginMethod {
            case .privateKey:
                if loginInput.starts(with: "nsec1") {
                    signer = try NDKPrivateKeySigner(nsec: loginInput)
                } else {
                    signer = try NDKPrivateKeySigner(privateKey: loginInput)
                }
                
            case .nip46:
                guard let ndk = ndkManager.ndk else {
                    throw AuthError.ndkNotInitialized
                }
                
                if loginInput.starts(with: "bunker://") {
                    guard let connectionToken = extractConnectionToken(from: loginInput) else {
                        throw AuthError.invalidBunkerUrl
                    }
                    signer = try NDKBunkerSigner.bunker(ndk: ndk, connectionToken: connectionToken)
                } else if loginInput.contains("@") {
                    signer = try NDKBunkerSigner.nip05(ndk: ndk, nip05: loginInput)
                } else {
                    throw AuthError.invalidBunkerUrl
                }
            }
            
            _ = try await authManager.createSession(with: signer)
            
        } catch {
            switch loginMethod {
            case .privateKey:
                errorMessage = "Invalid private key or nsec"
            case .nip46:
                errorMessage = "Failed to connect: \(error.localizedDescription)"
            }
        }
        
        isLoading = false
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
        var previousPoint = start
        
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
            
            previousPoint = point
        }
        
        return path
    }
}

// Helper function to extract connection token from bunker URL
private func extractConnectionToken(from bunkerUrl: String) -> String? {
    guard let url = URL(string: bunkerUrl),
          let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
        return nil
    }
    
    if let secret = components.queryItems?.first(where: { $0.name == "secret" })?.value {
        return secret
    }
    
    if let host = url.host, !host.isEmpty {
        return host
    }
    
    return nil
}

#Preview {
    PostaWelcomeView()
        .environment(NDKAuthManager.shared)
        .environment(NDKManager.shared)
        .environment(RelayManager())
}