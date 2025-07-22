import Foundation
import NDKSwift

@MainActor
class SubscriptionManager: ObservableObject {
    @Published var notes: [NDKEvent] = []
    @Published var latestFollowList: Set<String> = []
    @Published var isLoadingFollows = true
    @Published var isLoadingNotes = false
    @Published var isSyncing = false
    @Published var syncStatus: String = ""
    
    private var ndk: NDK?
    private var currentUserPubkey: String?
    
    private var followDataSource: NDKDataSource<NDKEvent>?
    private var notesDataSource: NDKDataSource<NDKEvent>?
    private var followTask: Task<Void, Never>?
    private var notesTask: Task<Void, Never>?
    
    private var hasEOSEd = false
    private var mostRecentFollowEvent: NDKEvent?
    
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
        
        // Start the follow list subscription
        await startFollowSubscription()
    }
    
    func cleanup() async {
        followTask?.cancel()
        notesTask?.cancel()
        followDataSource = nil
        notesDataSource = nil
        hasEOSEd = false
        mostRecentFollowEvent = nil
        notes.removeAll()
        latestFollowList.removeAll()
    }
    
    private func startFollowSubscription() async {
        guard let ndk = ndk, let userPubkey = currentUserPubkey else { return }
        
        isLoadingFollows = true
        
        print("SubscriptionManager - Starting follow subscription for user: \(userPubkey)")
        
        // Create filter for kind:3 (follow list) events from the current user
        let followFilter = NDKFilter(
            authors: [userPubkey],
            kinds: [EventKind.contacts],
            limit: 1  // We only need the latest contact list
        )
        
        // Subscribe to follow list events using observe
        // Use .networkOnly to ensure we get fresh data
        followDataSource = ndk.observe(
            filter: followFilter,
            cachePolicy: .networkOnly
        )
        
        // Start observing events
        followTask = Task {
            // Wait for the first kind:3 event
            for await event in followDataSource!.events {
                print("SubscriptionManager - Received kind:3 event with \(event.tags.count) tags")
                await processFollowEvent(event)
                
                // After processing the first event, we have our contact list
                await handleFollowEOSE()
                
                // Continue listening for updates to the contact list
                // (The loop continues to catch any future updates)
            }
        }
    }
    
    private func processFollowEvent(_ event: NDKEvent) async {
        // Check if this is the most recent follow event
        if mostRecentFollowEvent == nil || event.createdAt > mostRecentFollowEvent!.createdAt {
            mostRecentFollowEvent = event
            
            // Parse the follow list from tags
            var newFollowList = Set<String>()
            for tag in event.tags {
                if tag.count >= 2 && tag[0] == "p" {
                    newFollowList.insert(tag[1])
                }
            }
            
            print("SubscriptionManager - Parsed \(newFollowList.count) contacts from kind:3 event")
            latestFollowList = newFollowList
            
            // If we've already EOSEd, restart the notes subscription
            if hasEOSEd {
                await restartNotesSubscription()
            }
        }
    }
    
    private func handleFollowEOSE() async {
        hasEOSEd = true
        isLoadingFollows = false
        
        print("SubscriptionManager - Follow list loaded, starting notes subscription")
        
        // Start the notes subscription now that we have the follow list
        await startNotesSubscription()
        
        // Perform negentropy sync now that we have the follow list
        await performNegentropySync()
    }
    
    private func startNotesSubscription() async {
        guard let ndk = ndk, !latestFollowList.isEmpty else { 
            print("SubscriptionManager - Cannot start notes subscription: ndk=\(ndk != nil), followList=\(latestFollowList.count)")
            return 
        }
        
        print("SubscriptionManager - Starting notes subscription for \(latestFollowList.count) authors")
        isLoadingNotes = true
        
        // Cancel existing notes task if any
        notesTask?.cancel()
        
        // Create filter for kind:1 notes from followed users
        let notesFilter = NDKFilter(
            authors: Array(latestFollowList),
            kinds: [EventKind.textNote]
        )
        
        // Subscribe to notes using observe
        notesDataSource = ndk.observe(
            filter: notesFilter,
            cachePolicy: .cacheWithNetwork
        )
        
        // Start observing notes
        notesTask = Task {
            var receivedInitialEvents = false
            for await event in notesDataSource!.events {
                await processNoteEvent(event)
                
                // After receiving some events, set loading to false
                if !receivedInitialEvents {
                    receivedInitialEvents = true
                    Task {
                        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                        isLoadingNotes = false
                    }
                }
            }
        }
    }
    
    private func restartNotesSubscription() async {
        print("Restarting notes subscription with updated follow list")
        await startNotesSubscription()
    }
    
    private func processNoteEvent(_ event: NDKEvent) async {
        // Check if it's a root post (not a reply)
        let isReply = event.tags.contains { tag in
            tag.count >= 2 && tag[0] == "e"
        }
        
        if !isReply {
            // Add to notes array if not already present
            if !notes.contains(where: { $0.id == event.id }) {
                notes.append(event)
                // Sort by timestamp (newest first)
                notes.sort { $0.createdAt > $1.createdAt }
            }
        }
    }
    
    // MARK: - Negentropy Sync
    
    /// Perform NIP-77 negentropy sync for contacts' metadata and relay lists
    func performNegentropySync() async {
        guard let ndk = ndk, !latestFollowList.isEmpty else {
            print("SubscriptionManager - Cannot perform sync: NDK not ready or no follow list")
            return
        }
        
        isSyncing = true
        syncStatus = "Starting sync..."
        
        print("SubscriptionManager - Starting negentropy sync for \(latestFollowList.count) contacts...")
        
        // Create filter for contacts' metadata and relay lists
        let contactsFilter = NDKFilter(
            authors: Array(latestFollowList),
            kinds: [
                EventKind.metadata,     // Profile metadata (kind:0)
                EventKind.relayList    // Relay list metadata (kind:10002)
            ]
        )
        
        do {
            // Sync with all connected relays
            syncStatus = "Syncing profiles..."
            let results = try await ndk.syncWithAllRelays(filter: contactsFilter)
            
            var totalDownloaded = 0
            var totalEfficiency = 0
            var eventsByKind: [Int: Int] = [:]
            
            for (relay, result) in results {
                totalDownloaded += result.downloadedEvents.count
                totalEfficiency += result.efficiencyRatio
                
                // Count events by kind for detailed logging
                for event in result.downloadedEvents {
                    eventsByKind[event.kind, default: 0] += 1
                }
                
                print("SubscriptionManager - Sync on \(relay): \(result.downloadedEvents.count) new events, \(result.efficiencyRatio)% efficient")
            }
            
            let avgEfficiency = results.isEmpty ? 0 : totalEfficiency / results.count
            let metadataCount = eventsByKind[0] ?? 0
            let relayListCount = eventsByKind[EventKind.relayList] ?? 0
            
            syncStatus = "Sync complete: \(metadataCount) profiles, \(relayListCount) relay lists"
            print("SubscriptionManager - Sync completed: \(totalDownloaded) total events (\(metadataCount) metadata, \(relayListCount) relay lists), \(avgEfficiency)% avg efficiency")
            
            // Clear sync status after a delay
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
                syncStatus = ""
                isSyncing = false
            }
            
        } catch {
            print("SubscriptionManager - Error during negentropy sync: \(error)")
            syncStatus = "Sync failed"
            isSyncing = false
        }
    }
    
    /// Manually trigger a sync (can be called from UI)
    func triggerSync() async {
        await performNegentropySync()
    }
}