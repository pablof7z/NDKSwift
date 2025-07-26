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
            // Animated background
            AnimatedBackgroundView()
            
            VStack(spacing: 40) {
                Spacer()
                
                // Animated Logo
                if showAnimatedLogo {
                    AnimatedEnvelopeView(size: 140, color: .purple)
                        .scaleEffect(logoScale)
                        .opacity(logoOpacity)
                        .rotationEffect(.degrees(logoRotation))
                        .frame(height: 200)
                } else {
                    PostaLogoView(size: 140, color: .purple)
                        .scaleEffect(logoScale)
                        .opacity(logoOpacity)
                        .rotationEffect(.degrees(logoRotation))
                        .frame(height: 200)
                }
                
                // Title and slogan
                VStack(spacing: 20) {
                    Text("POSTA")
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
                        .offset(y: titleOffset)
                        .opacity(titleOpacity)
                        .shimmer()
                    
                    Text("SECURE MESSAGING ON NOSTR")
                        .font(.system(size: 16, weight: .medium, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(Color.white.opacity(0.7))
                        .scaleEffect(sloganScale)
                        .opacity(sloganOpacity)
                }
                
                Spacer()
                
                // Auth buttons that slide in
                if showButtons {
                    VStack(spacing: 16) {
                        // Create new account button
                        Button(action: {
                            withAnimation(.spring()) {
                                showCreateAccount = true
                            }
                        }) {
                            HStack {
                                Image(systemName: "envelope.badge.fill")
                                    .font(.system(size: 20))
                                Text("Create New Account")
                            }
                        }
                        .buttonStyle(GradientButtonStyle(
                            colors: [Color.purple, Color(red: 0.7, green: 0.3, blue: 0.9)],
                            shadowColor: .purple
                        ))
                        
                        // Import existing account button
                        Button(action: {
                            withAnimation(.spring()) {
                                showImportAccount = true
                            }
                        }) {
                            HStack {
                                Image(systemName: "key.fill")
                                    .font(.system(size: 20))
                                Text("Import Existing")
                            }
                        }
                        .buttonStyle(OutlineButtonStyle(color: .white))
                        
                        // Info text
                        Text("Your keys, your messages")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.4))
                            .padding(.top, 8)
                    }
                    .padding(.horizontal, 32)
                    .offset(y: buttonsOffset)
                    .opacity(buttonsOpacity)
                }
                
                Spacer()
                    .frame(height: 60)
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
                // Background gradient
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.purple.opacity(0.05),
                        Color.black.opacity(0.02)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack(spacing: 30) {
                    // Header with icon
                    VStack(spacing: 20) {
                        ZStack {
                            Circle()
                                .fill(Color.purple.opacity(0.1))
                                .frame(width: 80, height: 80)
                            
                            Image(systemName: "envelope.badge.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.purple)
                                .symbolEffect(.bounce, value: showSuccess)
                        }
                        .padding(.top, 20)
                        
                        Text("Create New Account")
                            .font(.system(size: 28, weight: .bold))
                        
                        Text("We'll generate a secure private key for you")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    
                    Spacer()
                    
                    // Features list
                    VStack(alignment: .leading, spacing: 16) {
                        FeatureRow(icon: "lock.shield.fill", text: "End-to-end encrypted messages", color: .purple)
                        FeatureRow(icon: "key.fill", text: "Your keys stay on your device", color: .blue)
                        FeatureRow(icon: "globe", text: "Decentralized communication", color: .green)
                    }
                    .padding(.horizontal, 32)
                    
                    Spacer()
                    
                    // Error message
                    if let errorMessage = errorMessage {
                        HStack {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(.red)
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        .padding(.horizontal)
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
                                Image(systemName: "plus.circle.fill")
                                Text("Create Account")
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                    .buttonStyle(GradientButtonStyle(
                        colors: [Color.purple, Color(red: 0.7, green: 0.3, blue: 0.9)],
                        shadowColor: .purple
                    ))
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
                            .foregroundColor(.secondary)
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
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.purple.opacity(0.05),
                        Color.black.opacity(0.02)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    // Header with icon
                    VStack(spacing: 20) {
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.1))
                                .frame(width: 80, height: 80)
                            
                            Image(systemName: "key.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.blue)
                        }
                        .padding(.top, 20)
                        
                        Text("Import Account")
                            .font(.system(size: 28, weight: .bold))
                        
                        Text("Enter your private key or bunker URL")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    
                    // Login method picker
                    Picker("Login Method", selection: $loginMethod) {
                        ForEach(PostaWelcomeView.LoginMethod.allCases, id: \.self) { method in
                            Text(method.rawValue).tag(method)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal, 32)
                    
                    // Input field
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            if loginMethod == .privateKey && !showingPassword {
                                SecureField(loginMethod.placeholder, text: $loginInput)
                                    .textFieldStyle(PlainTextFieldStyle())
                            } else {
                                TextField(loginMethod.placeholder, text: $loginInput)
                                    .textFieldStyle(PlainTextFieldStyle())
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)
                            }
                            
                            if loginMethod == .privateKey {
                                Button(action: { showingPassword.toggle() }) {
                                    Image(systemName: showingPassword ? "eye.slash.fill" : "eye.fill")
                                        .font(.system(size: 16))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        
                        if loginMethod == .privateKey {
                            Text("Accepts hex format or nsec")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 8)
                        }
                    }
                    .padding(.horizontal, 32)
                    
                    // Error message
                    if let errorMessage = errorMessage {
                        HStack {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(.red)
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
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
                                Text("Import Account")
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                    .buttonStyle(GradientButtonStyle(
                        colors: [Color.blue, Color.blue.opacity(0.8)],
                        shadowColor: .blue
                    ))
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
                            .foregroundColor(.secondary)
                    }
                }
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