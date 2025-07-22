import Foundation
import NDKSwift
import Observation

@MainActor
@Observable
class NDKManager {
    var ndk: NDK?
    var isConnected = false
    var error: Error?
    
    // Data sources
    private(set) var currentUserProfileDataSource: UserProfileDataSource?
    
    static let shared = NDKManager()
    
    private init() {}
    
    func setNDK(_ ndk: NDK, userPubkey: String? = nil) {
        self.ndk = ndk
        self.error = nil
        
        // Initialize user profile data source if we have a pubkey
        if let pubkey = userPubkey {
            currentUserProfileDataSource = UserProfileDataSource(ndk: ndk, pubkey: pubkey)
        }
        
        // Monitor connection status
        Task {
            await monitorConnectionStatus()
        }
    }
    
    private func monitorConnectionStatus() async {
        guard let ndk = ndk else { return }
        
        // Check initial connection status
        let (connected, total) = await ndk.getRelayConnectionSummary()
        isConnected = connected > 0
        
        // You could add a timer here to periodically check connection status
        // For now, we'll just check on initialization
    }
    
    func updateUserPubkey(_ pubkey: String) {
        guard let ndk = ndk else { return }
        currentUserProfileDataSource = UserProfileDataSource(ndk: ndk, pubkey: pubkey)
    }
}