import SwiftUI
import NDKSwift

struct AuthenticationView: View {
    @Environment(NostrManager.self) private var nostrManager
    @EnvironmentObject var appState: AppState
    @State private var showOnboarding = false
    @State private var privateKey = ""
    @State private var showLoginSheet = false
    @State private var keyboardHeight: CGFloat = 0
    @State private var animateGradient = false
    @State private var hasSeenOnboarding = UserDefaults.standard.bool(forKey: "hasSeenOnboarding")
    
    var body: some View {
        ZStack {
            // Animated gradient background
            TimeBasedGradient()
                .ignoresSafeArea()
            
            if !hasSeenOnboarding || showOnboarding {
                OnboardingView()
                    .onDisappear {
                        UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
                        hasSeenOnboarding = true
                    }
            } else {
                mainAuthView
            }
        }
    }
    
    var mainAuthView: some View {
        VStack {
            Spacer()
            
            // Animated Logo
            VStack(spacing: OlasDesign.Spacing.lg) {
                ZStack {
                    // Glow effect
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: OlasDesign.Colors.primaryGradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 120, height: 120)
                        .blur(radius: 40)
                        .scaleEffect(animateGradient ? 1.2 : 0.8)
                        .animation(
                            .easeInOut(duration: 3).repeatForever(autoreverses: true),
                            value: animateGradient
                        )
                    
                    Text("Olas")
                        .font(.system(size: 72, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                
                Text("Welcome back")
                    .font(.system(size: 24, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
            }
            
            Spacer()
            
            // Action buttons
            VStack(spacing: OlasDesign.Spacing.md) {
                Button {
                    showOnboarding = true
                    #if os(iOS)
                    OlasDesign.Haptic.impact(.medium)
                    #else
                    OlasDesign.Haptic.impact(0)
                    #endif
                } label: {
                    HStack {
                        Image(systemName: "sparkles")
                        Text("I'm New Here")
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
                    showLoginSheet = true
                    OlasDesign.Haptic.selection()
                } label: {
                    Text("I Have an Account")
                    .font(OlasDesign.Typography.bodyBold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.white.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(.white.opacity(0.2), lineWidth: 1)
                            )
                    )
                }
            }
            .padding(.horizontal, OlasDesign.Spacing.xl)
            .padding(.bottom, OlasDesign.Spacing.xxxl)
        }
        .sheet(isPresented: $showLoginSheet) {
            LoginSheet()
        }
        .onAppear {
            animateGradient = true
        }
    }
    
}

// MARK: - Login Sheet
struct LoginSheet: View {
    @Environment(NostrManager.self) private var nostrManager
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @State private var privateKey = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isLoading = false
    @FocusState private var isKeyFieldFocused: Bool
    
    var body: some View {
        ZStack {
            // Gradient background
            LinearGradient(
                colors: [Color(hex: "1a1a2e"), Color(hex: "0f0f1e")],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Handle bar
                Capsule()
                    .fill(.white.opacity(0.3))
                    .frame(width: 40, height: 4)
                    .padding(.top, OlasDesign.Spacing.sm)
                    .padding(.bottom, OlasDesign.Spacing.xl)
                
                ScrollView {
                    VStack(spacing: OlasDesign.Spacing.xl) {
                        // Header
                        VStack(spacing: OlasDesign.Spacing.md) {
                            Image(systemName: "key.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: OlasDesign.Colors.primaryGradient,
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            
                            Text("Welcome Back")
                                .font(.system(size: 28, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                            
                            Text("Enter your private key to continue")
                                .font(OlasDesign.Typography.body)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        .padding(.top, OlasDesign.Spacing.lg)
                        
                        // Key input
                        VStack(alignment: .leading, spacing: OlasDesign.Spacing.sm) {
                            Text("Private Key")
                                .font(OlasDesign.Typography.caption)
                                .foregroundStyle(.white.opacity(0.6))
                            
                            SecureField("nsec1... or hex format", text: $privateKey)
                                .font(OlasDesign.Typography.body)
                                .foregroundStyle(.white)
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(.white.opacity(0.1))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(.white.opacity(0.2), lineWidth: 1)
                                        )
                                )
                                .focused($isKeyFieldFocused)
                                #if os(iOS)
                                .autocapitalization(.none)
                                #endif
                                .autocorrectionDisabled()
                        }
                        .padding(.horizontal, OlasDesign.Spacing.xl)
                        
                        // Login button
                        Button(action: login) {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Text("Login")
                                    .font(OlasDesign.Typography.bodyBold)
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            LinearGradient(
                                colors: privateKey.isEmpty ? [.gray] : OlasDesign.Colors.primaryGradient,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .disabled(privateKey.isEmpty || isLoading)
                        .padding(.horizontal, OlasDesign.Spacing.xl)
                        
                        // Additional options
                        VStack(spacing: OlasDesign.Spacing.md) {
                            Button {
                                // TODO: Implement NIP-07 login
                                OlasDesign.Haptic.selection()
                            } label: {
                                HStack {
                                    Image(systemName: "globe")
                                    Text("Login with Browser Extension")
                                }
                                .font(OlasDesign.Typography.body)
                                .foregroundStyle(.white.opacity(0.8))
                            }
                            
                            Button {
                                // TODO: Implement key import
                                OlasDesign.Haptic.selection()
                            } label: {
                                HStack {
                                    Image(systemName: "qrcode")
                                    Text("Scan QR Code")
                                }
                                .font(OlasDesign.Typography.body)
                                .foregroundStyle(.white.opacity(0.8))
                            }
                        }
                        .padding(.top, OlasDesign.Spacing.lg)
                    }
                    .padding(.bottom, OlasDesign.Spacing.xxxl)
                }
            }
        }
        .alert("Login Failed", isPresented: $showError) {
            Button("OK") {
                errorMessage = ""
            }
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isKeyFieldFocused = true
            }
        }
    }
    
    private func login() {
        isLoading = true
        OlasDesign.Haptic.selection()
        
        Task {
            do {
                try await nostrManager.login(with: privateKey)
                OlasDesign.Haptic.success()
                dismiss()
            } catch {
                isLoading = false
                errorMessage = error.localizedDescription
                showError = true
                OlasDesign.Haptic.error()
            }
        }
    }
}