import SwiftUI
import NDKSwift

struct AuthenticationView: View {
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
                try await appState.login(with: privateKey)
            } catch {
                print("Login failed: \(error)")
                // TODO: Show error alert
            }
        }
    }
}