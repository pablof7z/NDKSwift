import SwiftUI
import NDKSwift

struct ContentView: View {
    @Environment(NostrManager.self) private var nostrManager
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var blossomServerManager: BlossomServerManager
    
    var body: some View {
        Group {
            if let ndk = nostrManager.ndk {
                if nostrManager.isAuthenticated && appState.isAuthenticated {
                    // Authenticated content
                    MainTabView()
                } else {
                    // Authentication screen
                    AuthenticationView()
                }
            } else {
                // Show loading or splash screen while NDK initializes
                VStack(spacing: 20) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.white)
                    
                    ProgressView()
                        .scaleEffect(1.2)
                        .tint(.white)
                    
                    Text("Olas")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
            }
        }
        .onAppear {
            // Link AppState to NostrManager
            appState.setNostrManager(nostrManager)
        }
    }
}