import SwiftUI
import NDKSwift

struct ContentView: View {
    @EnvironmentObject var nostrManager: NostrManager
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var blossomServerManager: BlossomServerManager
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            AuthContainer()
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
        }
        .onChange(of: nostrManager.isAuthenticated) { _, isAuthenticated in
            if isAuthenticated {
                // Load blossom servers when authenticated
                blossomServerManager.loadServers()
            }
        }
    }
}