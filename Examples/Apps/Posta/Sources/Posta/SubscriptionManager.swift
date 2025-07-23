import Foundation
import NDKSwift
import Observation

@MainActor
@Observable
class SubscriptionManager {
    // Published state
    var notes: [NDKEvent] = []
    var latestFollowList: Set<String> = []
    var isLoadingFollows: Bool = false
    var isLoadingNotes: Bool = false
    var isSyncing = false
    var syncStatus: String = ""
    var error: Error?
    var newNotesCount: Int = 0
    var lastViewedNoteId: String?
    
    // Subscriptions
    private var followListTask: Task<Void, Never>?
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
        
        // Start loading follow list
        await loadFollowList(userPubkey: userPubkey)
    }
    
    func cleanup() async {
        followListTask?.cancel()
        notesTask?.cancel()
        followListTask = nil
        notesTask = nil
        notes = []
        latestFollowList = []
    }
    
    private func loadFollowList(userPubkey: String) async {
        guard let ndk = ndk else { return }
        
        isLoadingFollows = true
        
        // Fetch follow list
        let filter = NDKFilter(
            authors: [userPubkey],
            kinds: [EventKind.contacts],
            limit: 1
        )
        
        let dataSource = ndk.observe(filter: filter, maxAge: 300) // 5 min cache
        
        for await contactEvent in dataSource.events {
            let pubkeys = contactEvent.tags
                .filter { $0.count >= 2 && $0[0] == "p" }
                .map { $0[1] }
            latestFollowList = Set(pubkeys)
            
            print("SubscriptionManager - Loaded \(latestFollowList.count) follows")
            
            // Now load notes from follows
            await startNotesSubscription()
            break // Only need the first/latest contact list
        }
        
        isLoadingFollows = false
    }
    
    private func startNotesSubscription() async {
        guard let ndk = ndk else { return }
        
        let follows = Array(latestFollowList)
        guard !follows.isEmpty else {
            print("SubscriptionManager - No follows to load notes for")
            return
        }
        
        print("SubscriptionManager - Starting notes subscription for \(follows.count) follows")
        
        isLoadingNotes = true
        
        // Create filter for notes from follows
        let notesFilter = NDKFilter(
            authors: follows,
            kinds: [EventKind.textNote],
            limit: 100
        )
        
        // Start observing notes - this runs continuously
        notesTask = Task {
            let notesDataSource = ndk.observe(filter: notesFilter, maxAge: 60) // 1 min cache
            
            for await note in notesDataSource.events {
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