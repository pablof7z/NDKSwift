import SwiftUI

struct AuthView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var privateKey: String = ""
    @State private var bunkerUrl: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingLogin = true
    @State private var loginMethod: LoginMethod = .privateKey
    
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
            
            // Login method picker
            Picker("Login Method", selection: $loginMethod) {
                ForEach(LoginMethod.allCases, id: \.self) { method in
                    Text(method.rawValue).tag(method)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)
            
            // Input field based on login method
            switch loginMethod {
            case .privateKey:
                TextField(loginMethod.placeholder, text: $privateKey)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
            case .nip46:
                TextField(loginMethod.placeholder, text: $bunkerUrl)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
            }
            
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
            .disabled(isLoading || (loginMethod == .privateKey ? privateKey.isEmpty : bunkerUrl.isEmpty))
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
            switch loginMethod {
            case .privateKey:
                try await authManager.login(privateKey: privateKey)
            case .nip46:
                try await authManager.loginWithBunker(bunkerUrl: bunkerUrl)
            }
        } catch {
            switch loginMethod {
            case .privateKey:
                errorMessage = "Invalid private key or nsec"
            case .nip46:
                errorMessage = "Failed to connect to bunker: \(error.localizedDescription)"
            }
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