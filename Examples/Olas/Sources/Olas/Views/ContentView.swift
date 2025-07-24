import SwiftUI
import NDKSwift

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        if let ndk = appState.ndk {
            Group {
                if appState.authManager.isAuthenticated {
                    // Authenticated content
                    MainTabView()
                } else {
                    // Authentication screen
                    AuthenticationView()
                }
            }
            .environment(\.ndk, ndk)
        } else {
            // Show loading or splash screen while NDK initializes
            ProgressView()
                .scaleEffect(1.5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
        }
    }
}