import SwiftUI
import NDKSwift

struct SplashView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(NostrManager.self) private var nostrManager
    
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
    
    // Auth mode states
    @State private var authMode: AuthMode = .none
    @State private var logoSize: CGFloat = 140
    @State private var logoXOffset: CGFloat = 0
    @State private var contentOpacity: Double = 0
    
    // Create account form states
    @State private var displayName = ""
    @State private var about = ""
    @State private var isCreating = false
    @State private var createdSession: NDKSession?
    @State private var showBackupView = false
    
    // Import account form states
    @State private var nsecInput = ""
    @State private var showPassword = false
    @State private var isLoggingIn = false
    @State private var showScanner = false
    
    // Error states
    @State private var showError = false
    @State private var errorMessage = ""
    
    enum AuthMode {
        case none
        case create
        case `import`
    }
    
    var body: some View {
        ZStack {
            // Dark gradient background
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
                
                // Logo and title container
                ZStack {
                    // Logo container that will animate
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
                                    endRadius: authMode == .none ? 120 : 80
                                )
                            )
                            .frame(width: authMode == .none ? 280 : 160, height: authMode == .none ? 280 : 160)
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
                    .offset(x: logoXOffset)
                    .animation(.spring(response: 0.8, dampingFraction: 0.7), value: logoXOffset)
                    .animation(.spring(response: 0.8, dampingFraction: 0.7), value: logoSize)
                    
                    // Single title that animates position
                    Text("NUTSACK")
                        .font(.system(
                            size: authMode == .none ? 52 : 38,
                            weight: .black,
                            design: .default
                        ))
                        .tracking(authMode == .none ? 4 : 3)
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
                        .offset(
                            x: authMode == .none ? 0 : 100,
                            y: authMode == .none ? 140 + titleOffset : -50
                        )
                        .animation(.spring(response: 0.8, dampingFraction: 0.7), value: authMode)
                    
                    // Slogan that fades away
                    if authMode == .none {
                        Text("A WALLET FOR THE RELAYS")
                            .font(.system(size: 16, weight: .medium, design: .monospaced))
                            .tracking(2)
                            .foregroundColor(Color.white.opacity(0.7))
                            .scaleEffect(sloganScale)
                            .opacity(sloganOpacity)
                            .offset(y: 190)
                            .transition(.opacity.combined(with: .scale))
                    }
                }
                .frame(height: authMode == .none ? 300 : 100)
                
                Spacer()
                
                // Content area that changes based on auth mode
                ZStack {
                    // Initial auth buttons
                    if authMode == .none {
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
                        .offset(y: buttonsOffset)
                        .opacity(buttonsOpacity)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    
                    // Create account form
                    if authMode == .create {
                        createAccountForm
                            .opacity(contentOpacity)
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                    }
                    
                    // Import account form
                    if authMode == .import {
                        importAccountForm
                            .opacity(contentOpacity)
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                Spacer()
                    .frame(height: 60)
            }
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
        .fullScreenCover(isPresented: $showBackupView) {
            // BackupKeyView not added to project yet
            NavigationStack {
                VStack(spacing: 20) {
                    Text("Account Created!")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Your wallet is ready to use")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Button("Continue") {
                        showBackupView = false
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .padding()
            }
        }
        .onAppear {
            animateSplash()
        }
    }
    
    // MARK: - Create Account Form
    private var createAccountForm: some View {
        VStack(spacing: 30) {
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
            .padding(.horizontal, 32)
            
            VStack(spacing: 20) {
                Text("Create Your Wallet")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                
                Text("Your gateway to the Lightning Network")
                    .font(.system(size: 14))
                    .foregroundColor(Color.white.opacity(0.6))
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
            .padding(.horizontal, 32)
            
            // Create button
            Button(action: createAccount) {
                ZStack {
                    if isCreating {
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
            }
            .disabled(displayName.isEmpty || isCreating)
            .padding(.horizontal, 32)
            
            Spacer()
        }
    }
    
    // MARK: - Import Account Form
    private var importAccountForm: some View {
        VStack(spacing: 30) {
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
            .padding(.horizontal, 32)
            
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
                Button(action: loginWithAccount) {
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
                                nsecInput.isEmpty ? Color.gray : Color.orange,
                                nsecInput.isEmpty ? Color.gray.opacity(0.8) : Color(red: 0.9, green: 0.5, blue: 0.1)
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: nsecInput.isEmpty ? Color.clear : Color.orange.opacity(0.3), radius: 10, x: 0, y: 4)
                    .disabled(nsecInput.isEmpty || isLoggingIn)
                }
            }
            .padding(.horizontal, 32)
            
            Spacer()
        }
    }
    
    // MARK: - Helper Methods
    private func selectAuthMode(_ mode: AuthMode) {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            authMode = mode
            
            if mode != .none {
                // Animate logo to the left and shrink
                logoSize = 80
                logoXOffset = -60
                
                // Fade in content
                withAnimation(.easeIn(duration: 0.3).delay(0.3)) {
                    contentOpacity = 1
                }
            } else {
                // Reset to center
                logoSize = 140
                logoXOffset = 0
                contentOpacity = 0
                
                // Clear form data
                displayName = ""
                about = ""
                nsecInput = ""
                showPassword = false
            }
        }
    }
    
    private func animateSplash() {
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
    
    private func createAccount() {
        guard !displayName.isEmpty else { return }
        
        isCreating = true
        
        Task {
            do {
                let session = try await nostrManager.createNewAccount(
                    displayName: displayName,
                    about: about.isEmpty ? nil : about
                )
                
                await MainActor.run {
                    createdSession = session
                    showBackupView = true
                    isCreating = false
                }
            } catch {
                await MainActor.run {
                    if let nostrError = error as? NostrError {
                        errorMessage = "Nostr Error: \(nostrError)"
                    } else {
                        errorMessage = "Failed to create account: \(error.localizedDescription)"
                    }
                    showError = true
                    isCreating = false
                }
            }
        }
    }
    
    private func loginWithAccount() {
        #if os(iOS)
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        #endif
        
        withAnimation(.easeInOut(duration: 0.3)) {
            isLoggingIn = true
        }
        
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
                    #if os(iOS)
                    let successFeedback = UINotificationFeedbackGenerator()
                    successFeedback.notificationOccurred(.success)
                    #endif
                    
                    Task {
                        try? await Task.sleep(nanoseconds: 100_000_000)
                        
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isLoggingIn = false
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    #if os(iOS)
                    let errorFeedback = UINotificationFeedbackGenerator()
                    errorFeedback.notificationOccurred(.error)
                    #endif
                    
                    errorMessage = error.localizedDescription
                    showError = true
                    
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isLoggingIn = false
                    }
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


// MARK: - Dark Text Field Style
struct DarkTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(16)
            .background(Color.white.opacity(0.08))
            .foregroundColor(.white)
            .accentColor(.orange)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Preview
struct SplashView_Previews: PreviewProvider {
    static var previews: some View {
        SplashView()
            .environment(NostrManager(from: "Preview"))
    }
}