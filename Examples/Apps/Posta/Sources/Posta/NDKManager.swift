import Foundation
import NDKSwift
import Observation

@MainActor
@Observable
class NDKManager {
    var ndk: NDK?
    var isConnected = false
    var error: Error?
    
    static let shared = NDKManager()
    
    private init() {}
    
    func setNDK(_ ndk: NDK) {
        self.ndk = ndk
        self.error = nil
        
        // Monitor connection status
        Task {
            await monitorConnectionStatus()
        }
    }
    
    private func monitorConnectionStatus() async {
        guard let ndk = ndk else { return }
        
        // Check initial connection status
        let (connected, _) = await ndk.getRelayConnectionSummary()
        isConnected = connected > 0
        
        // You could add a timer here to periodically check connection status
        // For now, we'll just check on initialization
    }
}