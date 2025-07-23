import SwiftUI
import NDKSwift

@main
struct SocratesApp: App {
    @StateObject private var nostrManager = NostrManager()
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.colorScheme, .dark)
                .preferredColorScheme(.dark)
                .environmentObject(nostrManager)
                .environmentObject(appState)
        }
    }
}

// MARK: - App State
@MainActor
class AppState: ObservableObject {
    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var loadingProgress: Double = 0
    @Published var loadingMessage = "Getting things ready..."
    @Published var webOfTrust: [String: Double] = [:]
    @Published var followLists: [String: Set<String>] = [:]
    @Published var syncProgress: Double = 0
    @Published var currentUser: NDKUser?
    
    // Audio state
    @Published var isRecording = false
    @Published var currentlyPlayingId: String?
    @Published var recordingStartTime: Date?
    
    func reset() {
        isAuthenticated = false
        isLoading = false
        loadingProgress = 0
        webOfTrust = [:]
        followLists = [:]
        syncProgress = 0
        currentUser = nil
        isRecording = false
        currentlyPlayingId = nil
    }
}

// MARK: - Nostr Manager
@MainActor
class NostrManager: ObservableObject {
    @Published var ndk: NDK?
    @Published var session: NDKSession?
    
    // Recommended relays for Socrates
    let defaultRelays = [
        "wss://relay.primal.net",
        "wss://relay.damus.io",
        "wss://nos.lol",
        "wss://relay.nostr.band",
        "wss://nostr.wine"
    ]
    
    init() {
        setupNDK()
    }
    
    private func setupNDK() {
        ndk = NDK(relayUrls: defaultRelays)
        Task {
            await ndk?.addRelays(defaultRelays)
            await ndk?.connect()
        }
    }
    
    func login(with signer: NDKSigner) async throws {
        guard let ndk = ndk else { throw NostrError.signerRequired }
        
        let pubkey = try await signer.pubkey
        let user = NDKUser(pubkey: pubkey)
        
        session = NDKSession(
            pubkey: pubkey,
            signerType: "privatekey"
        )
        
        ndk.signer = signer
    }
    
    func logout() {
        session = nil
        ndk?.signer = nil
    }
}

// MARK: - Errors
enum NostrError: LocalizedError {
    case signerRequired
    case invalidKey
    case networkError
    
    var errorDescription: String? {
        switch self {
        case .signerRequired:
            return "No signer available"
        case .invalidKey:
            return "Invalid private key"
        case .networkError:
            return "Network connection failed"
        }
    }
}