import SwiftUI
import NDKSwift

struct ContentView: View {
    @EnvironmentObject var nostrManager: NostrManager
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var blossomServerManager: BlossomServerManager
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            Group {
                if NDKAuthManager.shared.isAuthenticated {
                    // Main app interface - shown when authenticated
                    NavigationView {
                        HomeFeedView()
                    }
                    .environment(\.ndk, nostrManager.ndk)
                } else {
                    // For now, just show the authentication screen
                    // We can add session selection later if needed
                    AuthenticationView()
                }
            }
        }
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.05, green: 0.02, blue: 0.08),
                    Color(red: 0.02, green: 0.01, blue: 0.03),
                    Color.black
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .onAppear {
            appState.setNostrManager(nostrManager)
            checkAuthentication()
        }
        .environment(\.ndk, nostrManager.ndk)
        .onChange(of: NDKAuthManager.shared.isAuthenticated) { _, isAuthenticated in
            if isAuthenticated {
                // Load blossom servers when authenticated
                blossomServerManager.loadServers()
                blossomServerManager.loadSuggestedServers()
            }
        }
    }
    
    private func checkAuthentication() {
        // Update app state based on auth manager state
        guard let session = NDKAuthManager.shared.activeSession else {
            appState.isAuthenticated = false
            appState.currentUser = nil
            return
        }
        
        appState.isAuthenticated = true
        appState.currentUser = nostrManager.ndk?.getUser(session.pubkey)
    }
}