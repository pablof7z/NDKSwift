import SwiftUI
import NDKSwift

struct AuthContainer: View {
    @EnvironmentObject var nostrManager: NostrManager
    @EnvironmentObject var appState: AppState
    @State private var showingSessionSelection = false
    
    var body: some View {
        Group {
            if nostrManager.isAuthenticated {
                // Main app interface - shown when authenticated
                NavigationView {
                    HomeFeedView()
                }
                .environment(\.ndk, nostrManager.ndk)
            } else if showingSessionSelection && nostrManager.authManager.hasSessions {
                // Session selection view
                SessionSelectionView(showingSessionSelection: $showingSessionSelection)
            } else {
                // Authentication screen
                AuthenticationView()
            }
        }
        .onAppear {
            checkForExistingSessions()
        }
        .onChange(of: nostrManager.authManager.authenticationState) { _, newState in
            // Update app state based on authentication state
            switch newState {
            case .authenticated:
                if let session = nostrManager.authManager.activeSession {
                    appState.isAuthenticated = true
                    appState.currentUser = nostrManager.ndk?.getUser(session.pubkey)
                }
            case .unauthenticated:
                appState.isAuthenticated = false
                appState.currentUser = nil
                checkForExistingSessions()
            default:
                break
            }
        }
    }
    
    private func checkForExistingSessions() {
        // Only show session selection if we have sessions but no active session
        showingSessionSelection = nostrManager.authManager.hasSessions && 
                                 nostrManager.authManager.activeSession == nil
    }
}