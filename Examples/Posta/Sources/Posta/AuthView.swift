import SwiftUI

struct AuthView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var privateKey: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingLogin = true
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Posta")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.top, 50)
                
                Spacer()
                
                if showingLogin {
                    loginView
                } else {
                    registerView
                }
                
                Spacer()
                
                Button(action: {
                    showingLogin.toggle()
                }) {
                    Text(showingLogin ? "New to Posta? Create Account" : "Already have an account? Login")
                        .foregroundColor(.blue)
                }
                .padding(.bottom, 50)
            }
            .padding()
            .navigationBarHidden(true)
        }
    }
    
    private var loginView: some View {
        VStack(spacing: 20) {
            Text("Login")
                .font(.title2)
                .fontWeight(.semibold)
            
            TextField("Private Key (hex)", text: $privateKey)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .autocapitalization(.none)
                .disableAutocorrection(true)
            
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
            }
            
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
                    Text("Login")
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
            .disabled(isLoading || privateKey.isEmpty)
        }
    }
    
    private var registerView: some View {
        VStack(spacing: 20) {
            Text("Create Account")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("We'll generate a new private key for you")
                .font(.caption)
                .foregroundColor(.gray)
            
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
            }
            
            Button(action: {
                Task {
                    await performRegister()
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
            .background(Color.green)
            .foregroundColor(.white)
            .cornerRadius(10)
            .disabled(isLoading)
        }
    }
    
    private func performLogin() async {
        isLoading = true
        errorMessage = nil
        
        do {
            try await authManager.login(privateKey: privateKey)
        } catch {
            errorMessage = "Invalid private key"
        }
        
        isLoading = false
    }
    
    private func performRegister() async {
        isLoading = true
        errorMessage = nil
        
        do {
            try await authManager.register()
        } catch {
            errorMessage = "Failed to create account"
        }
        
        isLoading = false
    }
}

#Preview {
    AuthView()
        .environmentObject(AuthManager())
}