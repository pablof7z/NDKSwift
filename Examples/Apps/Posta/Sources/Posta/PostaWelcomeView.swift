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
    @State private var pulseScale: CGFloat = 1
    @State private var glowOpacity: Double = 0
    @State private var electricityOffset: CGFloat = -100
    
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
                
                // Logo container
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
                                endRadius: 120
                            )
                        )
                        .frame(width: 280, height: 280)
                        .blur(radius: 30)
                        .scaleEffect(pulseScale)
                        .opacity(logoOpacity * 0.7)
                    
                    // Inner glow
                    Circle()
                        .fill(
                            RadialGradient(
                                gradient: Gradient(colors: [
                                    Color.orange,
                                    Color.orange.opacity(0.3),
                                    Color.clear
                                ]),
                                center: .center,
                                startRadius: 5,
                                endRadius: 80
                            )
                        )
                        .frame(width: 200, height: 200)
                        .blur(radius: 20)
                        .opacity(logoOpacity)
                    
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
                        .frame(width: 140, height: 140)
                        .shadow(color: Color.orange.opacity(0.5), radius: 20, x: 0, y: 5)
                        .scaleEffect(logoScale)
                        .opacity(logoOpacity)
                        .rotationEffect(.degrees(logoRotation))
                    
                    // Lightning bolt icon
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 80, weight: .bold))
                        .foregroundColor(.white)
                        .scaleEffect(logoScale)
                        .opacity(logoOpacity)
                        .rotationEffect(.degrees(logoRotation))
                }
                .frame(height: 200)
                
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
                        .shadow(color: Color.orange.opacity(0.3), radius: 10, x: 0, y: 2)
                        .offset(y: titleOffset)
                        .opacity(titleOpacity)
                    
                    Text("POWERED BY NOSTR")
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
                        // Create new wallet button
                        Button(action: {
                            withAnimation(.spring()) {
                                showCreateAccount = true
                            }
                        }) {
                            HStack {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 20))
                                Text("Create New Wallet")
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
                        
                        // Info text
                        Text("Your keys, your coins")
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
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Create New Wallet")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.top, 20)
                
                Text("We'll generate a new private key for you")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                }
                
                Button(action: {
                    Task {
                        await createAccount()
                    }
                }) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(0.8)
                    } else {
                        Text("Create Account")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.orange)
                .foregroundColor(.white)
                .cornerRadius(10)
                .disabled(isLoading)
                
                Spacer()
            }
            .padding()
            .navigationBarItems(
                leading: Button("Cancel") { dismiss() }
            )
        }
    }
    
    private func createAccount() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let signer = try NDKPrivateKeySigner.generate()
            _ = try await authManager.createSession(with: signer)
        } catch {
            errorMessage = "Failed to create account: \(error.localizedDescription)"
        }
        
        isLoading = false
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
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Import Existing Account")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.top, 20)
                
                // Login method picker
                Picker("Login Method", selection: $loginMethod) {
                    ForEach(PostaWelcomeView.LoginMethod.allCases, id: \.self) { method in
                        Text(method.rawValue).tag(method)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)
                
                // Input field based on login method
                TextField(loginMethod.placeholder, text: $loginInput)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                }
                
                Spacer()
                
                Button(action: {
                    Task {
                        await performLogin()
                    }
                }) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(0.8)
                    } else {
                        Text("Import")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
                .disabled(isLoading || loginInput.isEmpty)
            }
            .padding()
            .navigationBarItems(
                leading: Button("Cancel") { dismiss() }
            )
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