import Foundation
import NDKSwift
import Observation

@MainActor
@Observable
class SubscriptionManager {
    // Published state
    var notes: [NDKEvent] {
        notesDataSource?.notes ?? []
    }
    var latestFollowList: Set<String> {
        followListDataSource?.followList ?? []
    }
    var isLoadingFollows: Bool {
        followListDataSource?.isLoading ?? true
    }
    var isLoadingNotes: Bool {
        notesDataSource?.isLoading ?? false
    }
    var isSyncing = false
    var syncStatus: String = ""
    var error: Error? {
        followListDataSource?.error ?? notesDataSource?.error
    }
    
    // Data sources
    private var followListDataSource: FollowListDataSource?
    private var notesDataSource: NotesDataSource?
    private var contactsMetadataDataSource: MultipleProfilesDataSource?
    
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
        
        // Initialize follow list data source
        followListDataSource = FollowListDataSource(ndk: ndk, pubkey: userPubkey)
        
        // Wait for follow list to load
        await waitForFollowList()
    }
    
    func cleanup() async {
        followListDataSource = nil
        notesDataSource = nil
        contactsMetadataDataSource = nil
    }
    
    private func waitForFollowList() async {
        guard let followListDataSource = followListDataSource else { return }
        
        // Give the follow list a moment to load
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        // Once we have a follow list, start loading notes
        if !followListDataSource.followList.isEmpty {
            await startNotesSubscription()
        } else {
            // Keep checking for follow list updates
            Task {
                while followListDataSource.followList.isEmpty && !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                }
                if !Task.isCancelled {
                    await startNotesSubscription()
                }
            }
        }
    }
    
    private func startNotesSubscription() async {
        guard let ndk = ndk, let followListDataSource = followListDataSource else { return }
        
        let follows = Array(followListDataSource.followList)
        guard !follows.isEmpty else {
            print("SubscriptionManager - No follows to load notes for")
            return
        }
        
        print("SubscriptionManager - Starting notes subscription for \(follows.count) follows")
        
        // Create filter for notes from follows
        let notesFilter = NDKFilter(
            authors: follows,
            kinds: [EventKind.textNote],
            limit: 100
        )
        
        // Initialize notes data source
        notesDataSource = NotesDataSource(ndk: ndk, filter: notesFilter)
        
        // Initialize metadata data source for profiles
        contactsMetadataDataSource = MultipleProfilesDataSource(
            ndk: ndk,
            pubkeys: Set(follows)
        )
    }
    
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
    
    // Profile lookup helper
    func profile(for pubkey: String) -> NDKUserProfile? {
        contactsMetadataDataSource?.profile(for: pubkey)
    }
}