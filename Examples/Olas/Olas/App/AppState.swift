import SwiftUI
import NDKSwift
import Observation

// MARK: - App State
@MainActor
class AppState: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: NDKUser?
    
    // UI state
    @Published var selectedTab = 0
    @Published var isCreatingPost = false
    @Published var selectedImage: Data?
    @Published var replyingTo: NDKEvent?
    
    // Lazy reference to NostrManager
    private weak var nostrManager: NostrManager?
    
    func setNostrManager(_ manager: NostrManager) {
        self.nostrManager = manager
        
        // Observe authentication state
        Task {
            await observeAuthState()
        }
    }
    
    private func observeAuthState() async {
        guard let nostrManager = nostrManager else { return }
        
        // Update auth state based on NostrManager
        withObservationTracking {
            _ = nostrManager.isAuthenticated
        } onChange: { [weak self] in
            Task { @MainActor in
                await self?.updateAuthState()
            }
        }
        
        // Initial update
        await updateAuthState()
    }
    
    private func updateAuthState() async {
        guard let nostrManager = nostrManager else { return }
        
        isAuthenticated = nostrManager.isAuthenticated
        currentUser = await nostrManager.currentUser
    }
    
    func reset() {
        isAuthenticated = false
        currentUser = nil
        selectedImage = nil
        replyingTo = nil
        isCreatingPost = false
    }
}