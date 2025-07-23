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
    
    // Signer reference for reactions
    var signer: NDKSigner? {
        nostrManager?.ndk?.signer
    }
    
    // Lazy reference to NostrManager
    private weak var nostrManager: NostrManager?
    
    func setNostrManager(_ manager: NostrManager) {
        self.nostrManager = manager
    }
    
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
    
    private var ndkAuthManager: NDKAuthManager
    
    // Recommended relays for Socrates
    let defaultRelays = [
        "wss://relay.primal.net",
        "wss://relay.damus.io",
        "wss://nos.lol",
        "wss://relay.nostr.band",
        "wss://nostr.wine"
    ]
    
    init() {
        self.ndkAuthManager = NDKAuthManager.shared
        setupNDK()
    }
    
    private func setupNDK() {
        ndk = NDK(relayUrls: defaultRelays)
        
        if let ndk = ndk {
            ndkAuthManager.setNDK(ndk)
        }
        
        Task {
            await ndk?.connect()
        }
    }
    
    func login(with signer: NDKSigner) async throws {
        guard let ndk = ndk else { throw NostrError.signerRequired }
        
        // Start session with mute list support
        let sessionData = try await ndk.startSession(
            signer: signer,
            config: NDKSessionConfiguration(
                dataRequirements: [.followList, .muteList],
                preloadStrategy: .progressive
            )
        )
        
        // Create or update session with auth manager for persistence
        if let privateSigner = signer as? NDKPrivateKeySigner {
            let session = try await ndkAuthManager.createSession(
                with: privateSigner,
                requiresBiometric: false,
                isHardwareBacked: false
            )
        }
    }
    
    func logout() {
        Task {
            // Clear all sessions from keychain
            for session in ndkAuthManager.availableSessions {
                try? await ndkAuthManager.deleteSession(session)
            }
        }
        
        // Clear active authentication state
        ndkAuthManager.logout()
        
        // Clear NDK signer
        ndk?.signer = nil
    }
    
    // Check if user is authenticated via NDKAuth
    var isAuthenticated: Bool {
        ndkAuthManager.isAuthenticated
    }
    
    // Get auth manager for use in UI
    var authManager: NDKAuthManager {
        return ndkAuthManager
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