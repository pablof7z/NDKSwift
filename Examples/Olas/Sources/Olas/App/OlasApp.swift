import SwiftUI
import NDKSwift

@main
struct OlasApp: App {
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .preferredColorScheme(.dark)
        }
    }
}

@MainActor
class AppState: ObservableObject {
    @Published var ndk: NDK?
    @Published var currentUser: NDKUser?
    @Published var isAuthenticated = false
    
    init() {
        setupNDK()
    }
    
    private func setupNDK() {
        Task {
            do {
                ndk = NDK()
                // Add default relays
                try await ndk?.addRelay("wss://relay.damus.io")
                try await ndk?.addRelay("wss://relay.nostr.band")
                try await ndk?.addRelay("wss://nos.lol")
                try await ndk?.connect()
            } catch {
                print("Failed to setup NDK: \(error)")
            }
        }
    }
}