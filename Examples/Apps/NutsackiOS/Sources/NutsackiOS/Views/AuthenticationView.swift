import SwiftUI
import NDKSwift

struct AuthenticationView: View {
    @Environment(NostrManager.self) private var nostrManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var showCreateAccount = false
    @State private var showImportAccount = false
    @State private var logoScale: CGFloat = 0.9
    @State private var glowOpacity: Double = 0.5
    
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
            
            VStack(spacing: 0) {
                Spacer()
                
                // Logo and title section
                VStack(spacing: 30) {
                    // Logo with glow
                    ZStack {
                        // Glow effect
                        Circle()
                            .fill(
                                RadialGradient(
                                    gradient: Gradient(colors: [
                                        Color.orange.opacity(0.6),
                                        Color.orange.opacity(0.2),
                                        Color.clear
                                    ]),
                                    center: .center,
                                    startRadius: 10,
                                    endRadius: 80
                                )
                            )
                            .frame(width: 180, height: 180)
                            .blur(radius: 20)
                            .opacity(glowOpacity)
                        
                        // Logo background
                        Circle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.orange,
                                        Color(red: 0.8, green: 0.4, blue: 0.1)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 120, height: 120)
                            .shadow(color: Color.orange.opacity(0.4), radius: 15, x: 0, y: 5)
                            .scaleEffect(logoScale)
                        
                        // Nut logo
                        NutLogoView(size: 70, color: .white)
                            .scaleEffect(logoScale)
                    }
                    .onAppear {
                        withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                            logoScale = 1.05
                            glowOpacity = 0.8
                        }
                    }
                    
                    VStack(spacing: 10) {
                        Text("NUTSACK")
                            .font(.system(size: 42, weight: .black))
                            .tracking(3)
                            .foregroundColor(.white)
                            .shadow(color: Color.orange.opacity(0.3), radius: 8, x: 0, y: 2)
                        
                        Text("A WALLET FOR THE RELAYS")
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .tracking(1.5)
                            .foregroundColor(Color.white.opacity(0.6))
                    }
                }
                
                Spacer()
                
                // Auth buttons section
                VStack(spacing: 16) {
                    // Create new account button
                    Button(action: { showCreateAccount = true }) {
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
                    Button(action: { showImportAccount = true }) {
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
                
                Spacer()
                    .frame(height: 60)
            }
        }
        .sheet(isPresented: $showCreateAccount) {
            CreateAccountView()
        }
        .sheet(isPresented: $showImportAccount) {
            ImportAccountView()
        }
    }
}

struct AuthenticationView_Previews: PreviewProvider {
    static var previews: some View {
        AuthenticationView()
            .environment(NostrManager(from: "Preview"))
    }
}