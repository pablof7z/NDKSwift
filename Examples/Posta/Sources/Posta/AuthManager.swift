import Foundation
import NDKSwift

@MainActor
class AuthManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: NDKUser?
    
    private var ndk: NDK?
    private var signer: NDKPrivateKeySigner?
    
    init() {
        checkAuthStatus()
    }
    
    func login(privateKey: String) async throws {
        let signer = try NDKPrivateKeySigner(privateKey: privateKey)
        let ndk = NDK(relayUrls: [
            "wss://relay.damus.io",
            "wss://nos.lol",
            "wss://relay.snort.social"
        ])
        ndk.signer = signer
        
        self.signer = signer
        self.ndk = ndk
        
        let user = try await signer.user()
        self.currentUser = user
        self.isAuthenticated = true
        
        saveAuthData(privateKey: privateKey)
    }
    
    func register() async throws {
        let privateKey = Crypto.generatePrivateKey()
        let signer = try NDKPrivateKeySigner(privateKey: privateKey)
        let ndk = NDK(relayUrls: [
            "wss://relay.damus.io",
            "wss://nos.lol",
            "wss://relay.snort.social"
        ])
        ndk.signer = signer
        
        self.signer = signer
        self.ndk = ndk
        
        let user = try await signer.user()
        self.currentUser = user
        self.isAuthenticated = true
        
        saveAuthData(privateKey: privateKey)
    }
    
    func logout() {
        isAuthenticated = false
        currentUser = nil
        signer = nil
        ndk = nil
        clearAuthData()
    }
    
    func getNDK() -> NDK? {
        return ndk
    }
    
    private func checkAuthStatus() {
        if let privateKey = UserDefaults.standard.string(forKey: "private_key") {
            Task {
                try? await login(privateKey: privateKey)
            }
        }
    }
    
    private func saveAuthData(privateKey: String) {
        UserDefaults.standard.set(privateKey, forKey: "private_key")
    }
    
    private func clearAuthData() {
        UserDefaults.standard.removeObject(forKey: "private_key")
    }
}

enum AuthError: Error {
    case invalidPrivateKey
    case networkError
}