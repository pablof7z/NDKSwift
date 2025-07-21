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
    
    private var followSubscription: NDKSubscription?
    private var notesSubscription: NDKSubscription?
    
    private var hasEOSEd = false
    private var mostRecentFollowEvent: NDKEvent?
    
    init() {}
    
    func initialize(ndk: NDK, userPubkey: String) async {
        self.ndk = ndk
        self.currentUserPubkey = userPubkey
        
        // Start the follow list subscription
        await startFollowSubscription()
    }
    
    func cleanup() async {
        await followSubscription?.close()
        await notesSubscription?.close()
        followSubscription = nil
        notesSubscription = nil
        hasEOSEd = false
        mostRecentFollowEvent = nil
        notes.removeAll()
        latestFollowList.removeAll()
    }
    
    private func startFollowSubscription() async {
        guard let ndk = ndk, let userPubkey = currentUserPubkey else { return }
        
        isLoadingFollows = true
        
        // Create filter for kind:3 (follow list) events from the current user
        let followFilter = NDKFilter(
            authors: [userPubkey],
            kinds: [EventKind.contacts]
        )
        
        // Subscribe to follow list events
        followSubscription = await ndk.subscribe(
            filters: [followFilter],
            closeOnEose: false  // Keep subscription open for updates
        )
        
        Task {
            do {
                for try await event in followSubscription! {
                    await processFollowEvent(event)
                }
            } catch {
                print("Follow subscription error: \(error)")
            }
        }
        
        // Listen for EOSE
        Task {
            await followSubscription!.waitForEOSE()
            await handleFollowEOSE()
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
        
        // Start the notes subscription now that we have the follow list
        await startNotesSubscription()
        
        // Perform negentropy sync now that we have the follow list
        await performNegentropySync()
    }
    
    private func startNotesSubscription() async {
        guard let ndk = ndk, !latestFollowList.isEmpty else { return }
        
        isLoadingNotes = true
        
        // Close existing notes subscription if any
        await notesSubscription?.close()
        
        // Create filter for kind:1 notes from followed users
        let notesFilter = NDKFilter(
            authors: Array(latestFollowList),
            kinds: [EventKind.textNote]
        )
        
        // Subscribe to notes
        notesSubscription = await ndk.subscribe(
            filters: [notesFilter],
            closeOnEose: false  // Keep subscription open for real-time updates
        )
        
        Task {
            do {
                for try await event in notesSubscription! {
                    await processNoteEvent(event)
                }
            } catch {
                print("Notes subscription error: \(error)")
            }
        }
        
        // Set loading to false after initial EOSE
        Task {
            await notesSubscription!.waitForEOSE()
            isLoadingNotes = false
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
                0,     // Profile metadata (kind:0)
                10002  // Relay list metadata (kind:10002)
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
            let relayListCount = eventsByKind[10002] ?? 0
            
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