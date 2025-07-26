import SwiftUI
import NDKSwift

@main
struct OlasApp: App {
    @State private var nostrManager: NostrManager
    @StateObject private var appState = AppState()
    @StateObject private var blossomServerManager: BlossomServerManager
    
    init() {
        let manager = NostrManager()
        self._nostrManager = State(initialValue: manager)
        self._appState = StateObject(wrappedValue: AppState())
        self._blossomServerManager = StateObject(wrappedValue: BlossomServerManager(ndk: manager.ndk))
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(nostrManager)
                .environmentObject(appState)
                .environmentObject(blossomServerManager)
                .preferredColorScheme(.dark)
        }
    }
}