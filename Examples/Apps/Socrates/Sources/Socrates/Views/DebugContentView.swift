import SwiftUI
import NDKSwift

struct DebugContentView: View {
    @EnvironmentObject var nostrManager: NostrManager
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var blossomServerManager: BlossomServerManager
    
    var body: some View {
        NavigationView {
            HomeFeedView()
        }
        .preferredColorScheme(.dark)
        .task {
            // Setup NDK with test credentials
            if nostrManager.ndk == nil {
                nostrManager.ndk = NDK(relayUrls: nostrManager.defaultRelays)
            }
            
            // Connect to relays
            if let ndk = nostrManager.ndk {
                await ndk.connect()
                
                // Create test signer
                if let testKey = try? NDKPrivateKeySigner(privateKey: "af3f2d4ec0d3c7b9f92d5c3b2b0a4e1c9c6e8a5c7f8d1a3e4b9f2c7d5a8e1b3d2f") {
                    ndk.signer = testKey
                    appState.isAuthenticated = true
                    
                    // Create test user
                    if let user = try? await testKey.user() {
                        appState.currentUser = user
                    }
                }
            }
        }
    }
}