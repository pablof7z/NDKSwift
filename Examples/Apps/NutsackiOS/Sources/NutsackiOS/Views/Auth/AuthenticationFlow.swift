import SwiftUI
import NDKSwift

struct AuthenticationFlow: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(NostrManager.self) private var nostrManager
    @Environment(WalletManager.self) private var walletManager
    @Environment(\.dismiss) private var dismiss
    
    // Flow states
    @State private var flowState: FlowState = .splash
    @State private var authMode: AuthMode = .none
    
    // Shared animation values for smooth transitions
    @State private var logoSize: CGFloat = 140
    @State private var logoOpacity: Double = 0
    @State private var logoScale: CGFloat = 0.3
    @State private var logoRotation: Double = -180
    @State private var logoPosition = CGPoint(x: 0, y: 0)
    
    @State private var titleText = "NUTSACK"
    @State private var titleOpacity: Double = 0
    @State private var titleOffset: CGFloat = 50
    @State private var titleSize: CGFloat = 52
    
    @State private var sloganOpacity: Double = 0
    @State private var contentOpacity: Double = 0
    @State private var buttonsOpacity: Double = 0
    
    // Background effects
    @State private var glowOpacity: Double = 0
    @State private var pulseScale: CGFloat = 1
    @State private var electricityOffset: CGFloat = -100
    
    // Form states
    @State private var displayName = ""
    @State private var about = ""
    @State private var nsecInput = ""
    @State private var showPassword = false
    @State private var isProcessing = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showScanner = false
    
    // Wallet onboarding sheet
    @State private var showWalletOnboarding = false
    @State private var walletOnboardingAuthMode: WalletOnboardingView.AuthMode = .none
    
    enum FlowState {
        case splash
        case auth
        case complete
    }
    
    enum AuthMode {
        case none
        case create
        case `import`
    }
    
    var body: some View {
        ZStack {
            // Background
            backgroundGradient
            electricEffects
            
            // Main content
            VStack(spacing: 0) {
                // Animated header that adapts based on state
                AnimatedHeader(
                    logoSize: logoSize,
                    logoOpacity: logoOpacity,
                    logoScale: logoScale,
                    logoRotation: logoRotation,
                    logoPosition: logoPosition,
                    titleText: titleText,
                    titleOpacity: titleOpacity,
                    titleOffset: titleOffset,
                    titleSize: titleSize,
                    sloganOpacity: sloganOpacity,
                    showSlogan: flowState == .splash && authMode == .none,
                    glowOpacity: glowOpacity,
                    pulseScale: pulseScale
                )
                .frame(height: headerHeight)
                .animation(.spring(response: 0.8, dampingFraction: 0.8), value: flowState)
                .animation(.spring(response: 0.8, dampingFraction: 0.8), value: authMode)
                
                // Content area
                contentView
                    .opacity(contentOpacity)
                    .animation(.easeInOut(duration: 0.4), value: contentOpacity)
                
                Spacer(minLength: 0)
            }
        }
        .onAppear {
            startSplashAnimation()
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .sheet(isPresented: $showScanner) {
            QRScannerView { scannedValue in
                nsecInput = scannedValue
                showScanner = false
            }
        }
        .fullScreenCover(isPresented: $showWalletOnboarding) {
            WalletOnboardingView(authMode: walletOnboardingAuthMode)
                .environment(nostrManager)
                .environment(walletManager)
                .onDisappear {
                    // If wallet onboarding completes, dismiss the whole auth flow
                    if walletManager.isWalletConfigured {
                        dismiss()
                    }
                }
        }
    }
    
    // MARK: - Computed Properties
    
    private var headerHeight: CGFloat {
        switch flowState {
        case .splash:
            return authMode == .none ? 400 : 120
        case .auth:
            return 120
        case .complete:
            return 0
        }
    }
    
    @ViewBuilder
    private var contentView: some View {
        switch flowState {
        case .splash:
            if authMode == .none {
                authButtons
            } else {
                authForms
            }
        case .auth:
            authForms
        case .complete:
            EmptyView()
        }
    }
    
    @ViewBuilder
    private var authButtons: some View {
        VStack(spacing: 16) {
            Button(action: { selectAuthMode(.create) }) {
                HStack {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 20))
                    Text("New Account")
                        .font(.system(size: 18, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.orange,
                            Color(red: 0.9, green: 0.5, blue: 0.1)
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: Color.orange.opacity(0.3), radius: 10, x: 0, y: 4)
            }
            
            Button(action: { selectAuthMode(.import) }) {
                HStack {
                    Image(systemName: "key.fill")
                        .font(.system(size: 20))
                    Text("Login")
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
            
            Text("Your keys, your nuts")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color.white.opacity(0.4))
                .padding(.top, 8)
        }
        .padding(.horizontal, 32)
        .opacity(buttonsOpacity)
    }
    
    @ViewBuilder
    private var authForms: some View {
        VStack(spacing: 30) {
            if authMode == .create {
                createAccountForm
            } else if authMode == .import {
                importAccountForm
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 20)
    }
    
    @ViewBuilder
    private var createAccountForm: some View {
        VStack(spacing: 20) {
            // Back button
            HStack {
                Button(action: { selectAuthMode(.none) }) {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .medium))
                        Text("Back")
                            .font(.system(size: 16, weight: .medium))
                    }
                    .foregroundColor(Color.orange)
                }
                Spacer()
            }
            
            // Form fields
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Display Name")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.8))
                    
                    TextField("", text: $displayName)
                        .textFieldStyle(DarkTextFieldStyle())
                        .textContentType(.name)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("About (optional)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.8))
                    
                    TextField("", text: $about, axis: .vertical)
                        .textFieldStyle(DarkTextFieldStyle())
                        .lineLimit(3...6)
                }
                
                Text("This information will be public on Nostr")
                    .font(.system(size: 12))
                    .foregroundColor(Color.white.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // Create button
            Button(action: createAccount) {
                if isProcessing {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    HStack {
                        Image(systemName: "bolt.fill")
                        Text("Create Wallet")
                            .fontWeight(.semibold)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [
                        displayName.isEmpty ? Color.gray : Color.orange,
                        displayName.isEmpty ? Color.gray.opacity(0.8) : Color(red: 0.9, green: 0.5, blue: 0.1)
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: displayName.isEmpty ? Color.clear : Color.orange.opacity(0.3), radius: 10, x: 0, y: 4)
            .disabled(displayName.isEmpty || isProcessing)
        }
    }
    
    @ViewBuilder
    private var importAccountForm: some View {
        VStack(spacing: 20) {
            // Back button
            HStack {
                Button(action: { selectAuthMode(.none) }) {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .medium))
                        Text("Back")
                            .font(.system(size: 16, weight: .medium))
                    }
                    .foregroundColor(Color.orange)
                }
                Spacer()
            }
            
            // Form fields
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Private Key")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.8))
                    
                    HStack(spacing: 12) {
                        HStack {
                            if showPassword {
                                TextField("nsec1...", text: $nsecInput)
                                    .textContentType(.password)
                                    #if os(iOS)
                                    .textInputAutocapitalization(.never)
                                    #endif
                                    .font(.system(.body, design: .monospaced))
                            } else {
                                SecureField("nsec1...", text: $nsecInput)
                                    .textContentType(.password)
                                    #if os(iOS)
                                    .textInputAutocapitalization(.never)
                                    #endif
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
                        .accentColor(.orange)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        
                        Button(action: { showScanner = true }) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white.opacity(0.08))
                                    .frame(width: 50, height: 50)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                    )
                                
                                Image(systemName: "qrcode.viewfinder")
                                    .font(.title2)
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                    
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
                Button(action: importAccount) {
                    if isProcessing {
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
                            nsecInput.isEmpty ? Color.gray : Color.orange,
                            nsecInput.isEmpty ? Color.gray.opacity(0.8) : Color(red: 0.9, green: 0.5, blue: 0.1)
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: nsecInput.isEmpty ? Color.clear : Color.orange.opacity(0.3), radius: 10, x: 0, y: 4)
                .disabled(nsecInput.isEmpty || isProcessing)
            }
        }
    }
    
    
    
    // MARK: - Background Views
    
    @ViewBuilder
    private var backgroundGradient: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                Color(red: 0.05, green: 0.02, blue: 0.08),
                Color(red: 0.02, green: 0.01, blue: 0.03),
                Color.black
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
    
    @ViewBuilder
    private var electricEffects: some View {
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
                        Color.orange.opacity(0.6),
                        Color.purple.opacity(0.3),
                        Color.clear
                    ]),
                    startPoint: .center,
                    endPoint: .bottom
                ),
                lineWidth: 2
            )
            .blur(radius: 3)
            .opacity(glowOpacity * 0.3)
            .offset(y: electricityOffset)
            .animation(
                .easeInOut(duration: 2)
                .delay(Double(index) * 0.1)
                .repeatForever(autoreverses: true),
                value: electricityOffset
            )
        }
    }
    
    private var primaryButtonGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [
                Color.orange,
                Color(red: 0.9, green: 0.5, blue: 0.1)
            ]),
            startPoint: .leading,
            endPoint: .trailing
        )
    }
    
    // MARK: - Animation Methods
    
    private func startSplashAnimation() {
        // Logo animation
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
        }
        
        // Pulse animation
        withAnimation(.easeInOut(duration: 1.5).delay(1).repeatForever(autoreverses: true)) {
            pulseScale = 1.1
        }
        
        // Button animation
        withAnimation(.spring(response: 0.8, dampingFraction: 0.8).delay(2.0)) {
            buttonsOpacity = 1
            contentOpacity = 1
        }
    }
    
    private func selectAuthMode(_ mode: AuthMode) {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            authMode = mode
            
            if mode != .none {
                // Transition to welcome state
                flowState = .auth
                logoSize = 60
                logoPosition = CGPoint(x: -UIScreen.main.bounds.width/2 + 80, y: 0)
                titleText = "WELCOME"
                titleSize = 40
                sloganOpacity = 0
                
                // Fade in content
                withAnimation(.easeIn(duration: 0.3).delay(0.3)) {
                    contentOpacity = 1
                }
            } else {
                // Reset to splash
                flowState = .splash
                logoSize = 140
                logoPosition = CGPoint(x: 0, y: 0)
                titleText = "NUTSACK"
                titleSize = 52
                titleOffset = 0  // Reset title offset
                sloganOpacity = 1
                contentOpacity = 0
                
                // Clear form data
                displayName = ""
                about = ""
                nsecInput = ""
                showPassword = false
            }
        }
    }
    
    
    // MARK: - Action Methods
    
    private func createAccount() {
        guard !displayName.isEmpty else { return }
        
        isProcessing = true
        
        Task {
            do {
                _ = try await nostrManager.createNewAccount(
                    displayName: displayName,
                    about: about.isEmpty ? nil : about
                )
                
                await MainActor.run {
                    isProcessing = false
                    // Open wallet onboarding
                    walletOnboardingAuthMode = .create
                    showWalletOnboarding = true
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isProcessing = false
                }
            }
        }
    }
    
    private func importAccount() {
        isProcessing = true
        
        Task {
            do {
                let signer = try NDKPrivateKeySigner(nsec: nsecInput)
                let pubkey = try await signer.pubkey
                
                var displayName = "Nostr User"
                
                if let ndk = nostrManager.ndk {
                    let profileDataSource = ndk.observe(
                        filter: NDKFilter(
                            authors: [pubkey],
                            kinds: [0]
                        ),
                        maxAge: 3600,
                        cachePolicy: .cacheWithNetwork
                    )
                    
                    for await event in profileDataSource.events {
                        if let profileData = event.content.data(using: .utf8),
                           let profile = JSONCoding.safeDecode(NDKUserProfile.self, from: profileData) {
                            displayName = profile.displayName ?? profile.name ?? "Nostr User"
                            break
                        }
                    }
                }
                
                let _ = try await nostrManager.createAccountFromNsec(
                    nsecInput,
                    displayName: displayName
                )
                
                await MainActor.run {
                    isProcessing = false
                    // Open wallet onboarding
                    walletOnboardingAuthMode = .import
                    showWalletOnboarding = true
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isProcessing = false
                }
            }
        }
    }
    
    
    private func logout() {
        Task {
            nostrManager.logout()
            dismiss()
        }
    }
}

// MARK: - Animated Header Component
struct AnimatedHeader: View {
    let logoSize: CGFloat
    let logoOpacity: Double
    let logoScale: CGFloat
    let logoRotation: Double
    let logoPosition: CGPoint
    let titleText: String
    let titleOpacity: Double
    let titleOffset: CGFloat
    let titleSize: CGFloat
    let sloganOpacity: Double
    let showSlogan: Bool
    let glowOpacity: Double
    let pulseScale: CGFloat
    
    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // Logo
            ZStack {
                // Outer pulsing glow
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [
                                Color.orange.opacity(0.8),
                                Color.purple.opacity(0.4),
                                Color.clear
                            ]),
                            center: .center,
                            startRadius: 10,
                            endRadius: logoSize * 0.8
                        )
                    )
                    .frame(width: logoSize * 2, height: logoSize * 2)
                    .blur(radius: 30)
                    .scaleEffect(pulseScale)
                    .opacity(logoOpacity * 0.7)
                
                // Logo background circle
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.orange,
                                Color.orange.opacity(0.9),
                                Color(red: 0.8, green: 0.4, blue: 0.1)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: logoSize, height: logoSize)
                    .shadow(color: Color.orange.opacity(0.5), radius: 20, x: 0, y: 5)
                    .scaleEffect(logoScale)
                    .opacity(logoOpacity)
                    .rotationEffect(.degrees(logoRotation))
                
                // Nut logo
                NutLogoView(size: logoSize * 0.57, color: .white)
                    .scaleEffect(logoScale)
                    .opacity(logoOpacity)
                    .rotationEffect(.degrees(logoRotation))
            }
            .offset(x: logoPosition.x, y: logoPosition.y)
            
            // Title and slogan
            VStack(spacing: 8) {
                Text(titleText)
                    .font(.system(size: titleSize, weight: .black, design: .default))
                    .tracking(titleSize > 40 ? 4 : 3)
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
                    .shadow(color: Color.orange.opacity(0.3), radius: 10, x: 0, y: 2)
                    .opacity(titleOpacity)
                    .offset(y: titleOffset)
                
                if showSlogan {
                    Text("A WALLET FOR THE RELAYS")
                        .font(.system(size: 16, weight: .medium, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(Color.white.opacity(0.7))
                        .opacity(sloganOpacity)
                        .transition(.opacity.combined(with: .scale))
                }
            }
            .padding(.leading, logoPosition.x != 0 ? 20 : 0)
            
            Spacer()
        }
        .padding(.horizontal, 32)
    }
}

