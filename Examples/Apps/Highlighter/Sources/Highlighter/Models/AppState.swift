import Foundation
import NDKSwift
import Combine

@MainActor
class AppState: ObservableObject {
    // NDK Core
    @Published private(set) var ndk: NDK?
    
    // Auth Manager
    @Published private var authManager = NDKAuthManager.shared
    
    // User State
    @Published private(set) var currentUserProfile: NDKUserProfile?
    
    // Content State  
    @Published private(set) var highlights: [HighlightEvent] = []
    @Published private(set) var curations: [ArticleCuration] = []
    @Published private(set) var followPacks: [FollowPack] = []
    @Published private(set) var following: Set<String> = []
    
    // UI State
    @Published var selectedTab = 0
    @Published var errorMessage: String?
    
    // Data Sources
    private var highlightDataSource: NDKDataSource<NDKEvent>?
    private var curationDataSource: NDKDataSource<NDKEvent>?
    private var followPackDataSource: NDKDataSource<NDKEvent>?
    private var streamingTasks: [Task<Void, Never>] = []
    
    var isAuthenticated: Bool {
        authManager.isAuthenticated
    }
    
    var activeSigner: NDKSigner? {
        authManager.activeSigner
    }
    
    init() {}
    
    func initialize() async {
        do {
            // Setup NDK with cache
            let cache = try await NDKSQLiteCache(path: nil)
            ndk = NDK(
                relayUrls: [
                    "wss://relay.damus.io",
                    "wss://relay.nostr.band", 
                    "wss://nos.lol",
                    "wss://relay.primal.net"
                ],
                cache: cache
            )
            
            // Connect to relays asynchronously
            Task {
                await ndk?.connect()
            }
            
            // Set NDK instance in auth manager
            authManager.setNDK(ndk!)
            
            // Restore session from keychain (handles automatic session switching)
            authManager.restoreSession()
            
            // Start NIP-77 sync in background
            Task {
                await syncHighlights()
            }
            
            // If authenticated after restore, start streaming immediately
            if authManager.isAuthenticated {
                // Start streaming data
                await startDataStreams()
                
                // Load user profile in background
                Task {
                    await loadUserProfile()
                }
            }
        } catch {
            errorMessage = "Failed to initialize: \(error.localizedDescription)"
        }
    }
    
    func createAccount() async throws {
        let signer = try NDKPrivateKeySigner.generate()
        
        let session = try await authManager.createSession(
            with: signer,
            requiresBiometric: true
        )
        
        try await authManager.switchToSession(session)
        
        // Start streaming data
        await startDataStreams()
    }
    
    func importAccount(nsec: String) async throws {
        let signer = try NDKPrivateKeySigner(nsec: nsec)
        
        let session = try await authManager.createSession(
            with: signer,
            requiresBiometric: true
        )
        
        try await authManager.switchToSession(session)
        
        // Start streaming data
        await startDataStreams()
        
        // Load user profile
        await loadUserProfile()
    }
    
    func logout() async {
        // Cancel all streaming tasks first
        stopAllStreams()
        
        // Clear state
        highlights = []
        curations = []
        followPacks = []
        following = []
        currentUserProfile = nil
        
        // Proper logout implementation - clear cache and delete sessions from keychain
        Task {
            // Clear cache data
            if let cache = ndk?.cache {
                try? await cache.clear()
            }
            
            // Delete ALL sessions from keychain - this is critical!
            for session in authManager.availableSessions {
                try? await authManager.deleteSession(session)
            }
        }
        
        // Clear memory state
        authManager.logout()
    }
    
    // MARK: - Private Methods
    
    private func syncHighlights() async {
        guard let ndk = ndk else { return }
        
        do {
            // Create filter for kind 9802 (highlights)
            let highlightFilter = NDKFilter(kinds: [9802])
            
            print("Starting NIP-77 sync for highlights from relay.damus.io...")
            
            // Perform NIP-77 sync with relay.damus.io
            let syncResult = try await ndk.syncEvents(
                filter: highlightFilter,
                relay: "wss://relay.damus.io",
                direction: .receive // Only download, don't upload
            )
            
            print("NIP-77 sync completed:")
            print("- Local events: \(syncResult.localEventCount)")
            print("- Downloaded: \(syncResult.downloadedEvents.count) events")
            print("- Rounds: \(syncResult.messageRounds)")
            print("- Bytes transferred: \(syncResult.bytesTransferred)")
            print("- Efficiency: \(syncResult.efficiencyRatio)%")
            
            // Convert downloaded events to HighlightEvent objects
            for event in syncResult.downloadedEvents {
                if let highlight = try? HighlightEvent(from: event) {
                    await MainActor.run {
                        if !highlights.contains(where: { $0.id == highlight.id }) {
                            highlights.append(highlight)
                        }
                    }
                }
            }
            
            // Sort highlights by creation date
            await MainActor.run {
                highlights.sort { $0.createdAt > $1.createdAt }
            }
            
        } catch {
            print("NIP-77 sync failed: \(error)")
            // Don't show error to user, continue with normal operation
        }
    }
    
    private func startDataStreams() async {
        guard let ndk = ndk else { return }
        
        // Cancel existing tasks
        stopAllStreams()
        
        // Start all streams concurrently for better performance
        async let highlightStream = startHighlightStream(ndk: ndk)
        async let curationStream = startCurationStream(ndk: ndk)
        async let followPackStream = startFollowPackStream(ndk: ndk)
        
        // Await all streams
        _ = await (highlightStream, curationStream, followPackStream)
    }
    
    private func stopAllStreams() {
        for task in streamingTasks {
            task.cancel()
        }
        streamingTasks.removeAll()
    }
    
    private func startHighlightStream(ndk: NDK) async {
        let highlightFilter = NDKFilter(kinds: [9802], limit: 100)
        highlightDataSource = ndk.observe(
            filter: highlightFilter,
            maxAge: 300, // 5 minute cache
            cachePolicy: .cacheWithNetwork
        )
        
        let task = Task {
            guard let source = highlightDataSource else { return }
            for await event in source.events {
                if let highlight = try? HighlightEvent(from: event) {
                    await addHighlight(highlight)
                }
            }
        }
        streamingTasks.append(task)
    }
    
    private func startCurationStream(ndk: NDK) async {
        let curationFilter = NDKFilter(kinds: [30004], limit: 50)
        curationDataSource = ndk.observe(
            filter: curationFilter,
            maxAge: 600, // 10 minute cache
            cachePolicy: .cacheWithNetwork
        )
        
        let task = Task {
            guard let source = curationDataSource else { return }
            for await event in source.events {
                if let curation = try? ArticleCuration(from: event) {
                    await addCuration(curation)
                }
            }
        }
        streamingTasks.append(task)
    }
    
    private func startFollowPackStream(ndk: NDK) async {
        let followPackFilter = NDKFilter(kinds: [39089], limit: 20)
        followPackDataSource = ndk.observe(
            filter: followPackFilter,
            maxAge: 3600, // 1 hour cache
            cachePolicy: .cacheWithNetwork
        )
        
        let task = Task {
            guard let source = followPackDataSource else { return }
            for await event in source.events {
                if let pack = try? FollowPack(from: event) {
                    await addFollowPack(pack)
                }
            }
        }
        streamingTasks.append(task)
    }
    
    @MainActor
    private func addHighlight(_ highlight: HighlightEvent) {
        if !highlights.contains(where: { $0.id == highlight.id }) {
            highlights.append(highlight)
            highlights.sort { $0.createdAt > $1.createdAt }
        }
    }
    
    @MainActor
    private func addCuration(_ curation: ArticleCuration) {
        if !curations.contains(where: { $0.id == curation.id }) {
            curations.append(curation)
            curations.sort { $0.updatedAt > $1.updatedAt }
        }
    }
    
    @MainActor
    private func addFollowPack(_ pack: FollowPack) {
        if !followPacks.contains(where: { $0.id == pack.id }) {
            followPacks.append(pack)
        }
    }
    
    private func loadUserProfile() async {
        guard let ndk = ndk, let signer = activeSigner else { return }
        
        let pubkey: String
        do {
            pubkey = try await signer.pubkey
        } catch {
            print("Failed to get pubkey: \(error)")
            return
        }
        
        // Use profile manager for efficient caching
        let profileTask = Task {
            for await profile in await ndk.profileManager.observe(for: pubkey, maxAge: 3600) {
                await MainActor.run {
                    self.currentUserProfile = profile
                }
                break // Only need current value
            }
        }
        streamingTasks.append(profileTask)
    }
    
    // MARK: - Publishing Methods
    
    func publishHighlight(_ highlight: HighlightEvent) async throws {
        guard let ndk = ndk, let signer = activeSigner else {
            throw AuthError.noSigner
        }
        
        let event = try await HighlightEvent.create(
            ndk: ndk,
            content: highlight.content,
            context: highlight.context,
            url: highlight.url,
            referencedEvent: highlight.referencedEvent,
            attributedAuthors: highlight.attributedAuthors,
            comment: highlight.comment,
            signer: signer
        )
        
        // Publish with optimistic updates
        _ = try await ndk.publish(event)
    }
    
    func createCuration(name: String, title: String, description: String?, image: String?) async throws {
        guard let ndk = ndk, let signer = activeSigner else {
            throw AuthError.noSigner
        }
        
        let event = try await ArticleCuration.create(
            ndk: ndk,
            name: name,
            title: title,
            description: description,
            image: image,
            articles: [],
            signer: signer
        )
        
        _ = try await ndk.publish(event)
    }
}

enum AuthError: LocalizedError {
    case invalidPrivateKey
    case noSigner
    
    var errorDescription: String? {
        switch self {
        case .invalidPrivateKey:
            return "Invalid private key format"
        case .noSigner:
            return "No signer configured"
        }
    }
}
