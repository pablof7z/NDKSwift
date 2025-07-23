import Foundation
import NDKSwift
import Observation

@MainActor
@Observable
class SubscriptionManager {
    // Published state
    var notes: [NDKEvent] = []
    var isLoadingFollows: Bool = false
    var isLoadingNotes: Bool = false
    var isSyncing = false
    var syncStatus: String = ""
    var error: Error?
    var newNotesCount: Int = 0
    var lastViewedNoteId: String?
    
    // Session data
    var sessionData: NDKSessionData? {
        didSet {
            if let sessionData = sessionData {
                observeSessionData(sessionData)
            }
        }
    }
    
    // Subscriptions
    private var notesTask: Task<Void, Never>?
    
    private var ndk: NDK?
    private var currentUserPubkey: String?
    
    init() {}
    
    func initialize(ndk: NDK, userPubkey: String) async {
        self.ndk = ndk
        self.currentUserPubkey = userPubkey
        
        print("SubscriptionManager - Initializing for user: \(userPubkey)")
        
        // Ensure we have connected relays before starting
        let (connected, total) = await ndk.getRelayConnectionSummary()
        print("SubscriptionManager - Connected relays: \(connected)/\(total)")
        
        if connected == 0 {
            print("SubscriptionManager - No connected relays, waiting...")
            // Wait a bit for relays to connect
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            let (retriedConnected, retriedTotal) = await ndk.getRelayConnectionSummary()
            print("SubscriptionManager - After wait, connected relays: \(retriedConnected)/\(retriedTotal)")
        }
        
        // Start session with follow list requirement
        do {
            let sessionData = try await ndk.startSession(
                signer: ndk.signer!,
                config: NDKSessionConfiguration(
                    dataRequirements: [.followList],
                    preloadStrategy: .progressive
                )
            )
            self.sessionData = sessionData
        } catch {
            print("SubscriptionManager - Failed to start session: \(error)")
            self.error = error
        }
    }
    
    func cleanup() async {
        notesTask?.cancel()
        notesTask = nil
        notes = []
        sessionData = nil
    }
    
    private func observeSessionData(_ sessionData: NDKSessionData) {
        // Observe follow list state changes
        Task { @MainActor in
            switch sessionData.followListState {
            case .loading:
                isLoadingFollows = true
            case .ready(let follows, _), .updating(let follows, _):
                isLoadingFollows = false
                print("SubscriptionManager - Follow list ready with \(follows.count) follows")
                await startNotesSubscription()
            case .error(let error):
                isLoadingFollows = false
                self.error = error
                print("SubscriptionManager - Error loading follows: \(error)")
            }
        }
    }
    
    private func startNotesSubscription() async {
        guard let ndk = ndk else { return }
        
        // Cancel existing subscription
        notesTask?.cancel()
        
        print("SubscriptionManager - Starting reactive notes subscription")
        
        isLoadingNotes = true
        
        // Create reactive filter that depends on follow list
        let reactiveFilter = ReactiveFilter(
            dependencies: [.followList],
            builder: { sessionData in
                NDKFilter(
                    authors: Array(sessionData.followList),
                    kinds: [EventKind.textNote],
                    limit: 100
                )
            }
        )
        
        // Start observing notes - automatically updates when follows change
        notesTask = Task {
            for await note in ndk.observe(reactiveFilter) {
                // Check if it's a reply
                let isReply = note.tags.contains { tag in
                    tag.count >= 2 && tag[0] == "e"
                }
                
                if !isReply {
                    // Add to notes array if not already present
                    if !notes.contains(where: { $0.id == note.id }) {
                        notes.append(note)
                        // Keep sorted by timestamp
                        notes.sort { $0.createdAt > $1.createdAt }
                        // Limit to reasonable number
                        if notes.count > 200 {
                            notes = Array(notes.prefix(200))
                        }
                    }
                }
                
                // After first few notes, mark as not loading
                if notes.count >= 5 && isLoadingNotes {
                    isLoadingNotes = false
                }
            }
        }
    }
    
    // Remove loadProfiles - profiles should be loaded on-demand by views
    
    func triggerSync() async {
        guard !isSyncing else { return }
        
        isSyncing = true
        syncStatus = "Syncing..."
        
        // Force refresh by recreating data sources
        if let ndk = ndk, let userPubkey = currentUserPubkey {
            await cleanup()
            await initialize(ndk: ndk, userPubkey: userPubkey)
        }
        
        // Wait a moment for sync to complete
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        syncStatus = "Sync complete"
        isSyncing = false
        
        // Clear status after a moment
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            if !isSyncing {
                syncStatus = ""
            }
        }
    }
    
    // Create an observable profile source for a specific pubkey
    func observeProfile(for pubkey: String) -> AsyncStream<NDKUserProfile?> {
        guard let ndk = ndk else {
            return AsyncStream { continuation in
                continuation.finish()
            }
        }
        
        return AsyncStream { continuation in
            Task {
                let profileStream = await ndk.profileManager.observe(for: pubkey, maxAge: 3600)
                for await profile in profileStream {
                    continuation.yield(profile)
                }
                continuation.finish()
            }
        }
    }
    
    func resetNewNotesCount() {
        newNotesCount = 0
        if let firstNote = notes.first {
            lastViewedNoteId = firstNote.id
        }
    }
}