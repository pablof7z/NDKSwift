import SwiftUI
import NDKSwift

struct AuthenticationView: View {
    @Environment(NostrManager.self) private var nostrManager
    @EnvironmentObject var appState: AppState
    @State private var showCreateAccount = false
    @State private var privateKey = ""
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                // Logo/Header
                VStack(spacing: 8) {
                    Text("Olas")
                        .font(.system(size: 72, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(hex: "667eea"), Color(hex: "764ba2")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text("Picture-First Nostr Experience")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 60)
                
                Spacer()
                
                // Login Section
                VStack(spacing: 16) {
                    TextField("Enter your private key (nsec or hex)", text: $privateKey)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .autocapitalization(.none)
                        #endif
                        .autocorrectionDisabled()
                    
                    Button(action: login) {
                        Text("Login")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                LinearGradient(
                                    colors: [Color(hex: "667eea"), Color(hex: "764ba2")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(12)
                    }
                    .disabled(privateKey.isEmpty)
                }
                .padding(.horizontal, 32)
                
                // Create Account
                Button(action: { showCreateAccount = true }) {
                    Text("Create New Account")
                        .font(.headline)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(hex: "667eea"), Color(hex: "764ba2")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
                .padding(.bottom, 60)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .sheet(isPresented: $showCreateAccount) {
                CreateAccountView()
            }
        }
    }
    
    private func login() {
        Task {
            do {
                let signer = try NDKPrivateKeySigner(privateKey: privateKey)
                nostrManager.ndk?.signer = signer
                
                let user = try NDKUser(pubkey: signer.publicKey(format: .hex))
                appState.currentUser = user
                appState.isAuthenticated = true
            } catch {
                print("Login failed: \(error)")
            }
        }
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}