import SwiftUI
import NDKSwift

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        if let ndk = appState.ndk {
            NDKAuthView(authManager: appState.authManager, ndk: ndk) {
                // Authenticated content
                MainTabView()
            } authenticationContent: {
                // Authentication screen
                AuthenticationView()
            }
        } else {
            // Show loading or splash screen while NDK initializes
            ProgressView()
                .scaleEffect(1.5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
        }
    }
}