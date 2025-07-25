import SwiftUI
import NDKSwift

/// A view that loads and displays content based on a user profile
struct ProfileLoader<Content: View>: View {
    let pubkey: String
    let content: (NDKUserProfile?) -> Content
    
    @Environment(NDKManager.self) var ndkManager
    @State private var profile: NDKUserProfile?
    @State private var profileTask: Task<Void, Never>?
    
    var body: some View {
        content(profile)
            .onAppear {
                loadProfile()
            }
            .onDisappear {
                profileTask?.cancel()
            }
    }
    
    private func loadProfile() {
        guard let ndk = ndkManager.ndk else { return }
        
        profileTask = Task {
            let profileStream = await ndk.profileManager.observe(for: pubkey, maxAge: TimeConstants.hour)
            
            for await profile in profileStream {
                if let profile = profile {
                    await MainActor.run {
                        self.profile = profile
                    }
                    break
                }
            }
        }
    }
}