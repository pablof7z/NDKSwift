import Foundation
import NDKSwift
import SwiftUI
import Combine

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

// MARK: - User Profile Data Source

/// Data source for user profile metadata
@MainActor
public class UserProfileDataSource: ObservableObject {
    @Published public private(set) var profile: NDKUserProfile?
    @Published public private(set) var isLoading = false
    @Published public private(set) var error: Error?
    
    private let ndk: NDK
    private let pubkey: String
    private var profileTask: Task<Void, Never>?
    
    public init(ndk: NDK, pubkey: String) {
        self.ndk = ndk
        self.pubkey = pubkey
        
        // Start observing immediately - no loading states
        profileTask = Task {
            await observeProfile()
        }
    }
    
    deinit {
        profileTask?.cancel()
    }
    
    private func observeProfile() async {
        // Use NDKProfileManager for best practices
        for await profileUpdate in await ndk.profileManager.observe(for: pubkey, maxAge: TimeConstants.hour) {
            await MainActor.run {
                self.profile = profileUpdate
                self.isLoading = false
            }
        }
    }
}

// MARK: - Multiple Profiles Data Source

/// Data source for multiple user profiles (e.g., for contact lists)
@MainActor
public class MultipleProfilesDataSource: ObservableObject {
    @Published public private(set) var profiles: [String: NDKUserProfile] = [:]
    @Published public private(set) var isLoading = false
    @Published public private(set) var error: Error?
    
    private let dataSource: NDKDataSource<NDKEvent>
    private let pubkeys: Set<String>
    
    public init(ndk: NDK, pubkeys: Set<String>) {
        self.pubkeys = pubkeys
        self.dataSource = ndk.observe(
            filter: NDKFilter(
                authors: Array(pubkeys),
                kinds: [0]
            ),
            maxAge: 0,  // Real-time updates
            cachePolicy: .cacheWithNetwork
        )
        
        Task {
            await observeProfiles()
        }
    }
    
    private func observeProfiles() async {
        dataSource.$data
            .map { events in
                var profileDict: [String: NDKUserProfile] = [:]
                
                // Group events by author
                let eventsByAuthor = Dictionary(grouping: events) { $0.pubkey }
                
                // Get the latest profile for each author
                for (pubkey, authorEvents) in eventsByAuthor {
                    if let latestEvent = authorEvents.sorted(by: { $0.createdAt > $1.createdAt }).first,
                       let profile = JSONCoding.safeDecode(NDKUserProfile.self, from: latestEvent.content.data(using: .utf8) ?? Data()) {
                        profileDict[pubkey] = profile
                    }
                }
                
                return profileDict
            }
            .assign(to: &$profiles)
        
        dataSource.$isLoading.assign(to: &$isLoading)
        dataSource.$error.assign(to: &$error)
    }
    
    public func profile(for pubkey: String) -> NDKUserProfile? {
        profiles[pubkey]
    }
}

// MARK: - Follow List Data Source

/// Data source for user's follow list (kind:3 events)
@MainActor
public class FollowListDataSource: ObservableObject {
    @Published public private(set) var followList: Set<String> = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var error: Error?
    @Published public private(set) var lastUpdate: Date?
    
    private let dataSource: NDKDataSource<NDKEvent>
    
    public init(ndk: NDK, pubkey: String) {
        self.dataSource = ndk.observe(
            filter: NDKFilter(
                authors: [pubkey],
                kinds: [EventKind.contacts],
                limit: 1
            ),
            maxAge: 0,
            cachePolicy: .cacheWithNetwork
        )
        
        Task {
            await observeFollowList()
        }
    }
    
    private func observeFollowList() async {
        // Break complex expression into simpler parts
        let latestEventPublisher = dataSource.$data
            .map { events -> NDKEvent? in
                let sorted = events.sorted { $0.createdAt > $1.createdAt }
                return sorted.first
            }
            .compactMap { $0 }
        
        let followListPublisher = latestEventPublisher
            .map { event -> Set<String> in
                let pubkeys = event.tags
                    .filter { tag in
                        tag.count >= 2 && tag[0] == "p"
                    }
                    .map { tag in
                        tag[1]
                    }
                return Set(pubkeys)
            }
        
        followListPublisher.assign(to: &$followList)
        
        let timestampPublisher = latestEventPublisher
            .map { event -> Date? in
                Date(timeIntervalSince1970: TimeInterval(event.createdAt))
            }
        
        timestampPublisher.assign(to: &$lastUpdate)
        
        dataSource.$isLoading.assign(to: &$isLoading)
        dataSource.$error.assign(to: &$error)
    }
}

// MARK: - Notes Data Source

/// Data source for text notes (kind:1 events)
@MainActor
public class NotesDataSource: ObservableObject {
    @Published public private(set) var notes: [NDKEvent] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var error: Error?
    @Published public private(set) var hasEOSE = false
    
    private let dataSource: NDKDataSource<NDKEvent>
    private var eoseTask: Task<Void, Never>?
    
    public init(ndk: NDK, filter: NDKFilter) {
        self.dataSource = ndk.observe(
            filter: filter,
            maxAge: 0,
            cachePolicy: .cacheWithNetwork
        )
        
        Task {
            await observeNotes()
        }
    }
    
    deinit {
        eoseTask?.cancel()
    }
    
    private func observeNotes() async {
        // Monitor EOSE status
        eoseTask = Task {
            for await update in dataSource.relayUpdates {
                if case .eose = update {
                    hasEOSE = true
                }
            }
        }
        
        dataSource.$data
            .map { events in
                events.sorted { $0.createdAt > $1.createdAt }
            }
            .assign(to: &$notes)
        
        dataSource.$isLoading.assign(to: &$isLoading)
        dataSource.$error.assign(to: &$error)
    }
}

// MARK: - Session Notes Data Source

/// Data source for notes from followed users with session management
@MainActor
public class SessionNotesDataSource: ObservableObject {
    @Published public private(set) var notes: [NDKEvent] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var error: Error?
    @Published public private(set) var hasEOSE = false
    @Published public private(set) var sessionData: NDKSessionData?
    
    private var dataSource: NDKDataSource<NDKEvent>?
    private var eoseTask: Task<Void, Never>?
    private var signerMonitorTask: Task<Void, Never>?
    public let ndk: NDK
    
    public init(ndk: NDK) {
        self.ndk = ndk
        
        // Start monitoring for signer availability
        signerMonitorTask = Task {
            await monitorSignerAndSetup()
        }
    }
    
    /// Initialize with immediate setup if signer is available
    public static func createWithSetup(ndk: NDK) async -> SessionNotesDataSource {
        let dataSource = SessionNotesDataSource(ndk: ndk)
        await dataSource.setupSession()
        return dataSource
    }
    
    deinit {
        eoseTask?.cancel()
        signerMonitorTask?.cancel()
    }
    
    private func monitorSignerAndSetup() async {
        // If signer is already available, set up immediately
        if ndk.signer != nil {
            await setupSession()
            return
        }
        
        // Otherwise, monitor for signer availability
        // This is a placeholder - ideally NDK would provide a proper async stream for signer changes
        // For now, we'll check periodically but this should be improved in NDK
        while ndk.signer == nil {
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
        }
        
        await setupSession()
    }
    
    private func setupSession() async {
        do {
            isLoading = true
            
            // Properly wait for signer without sleep loops
            guard let signer = ndk.signer else {
                // Don't treat missing signer as an error - just wait for it
                print("📱 [SessionNotesDataSource] Waiting for authentication...")
                isLoading = false
                return
            }
            
            // Start session with proper configuration
            let config = NDKSessionConfiguration(
                dataRequirements: [.followList, .muteList, .webOfTrust(depth: 2)],
                preloadStrategy: .progressive
            )
            
            let sessionData = try await ndk.startSession(signer: signer, config: config)
            self.sessionData = sessionData
            
            print("📱 [SessionNotesDataSource] Session started for pubkey: \(sessionData.pubkey)")
            print("📱 [SessionNotesDataSource] Follow list count: \(sessionData.followList.count)")
            print("📱 [SessionNotesDataSource] First 5 follows: \(Array(sessionData.followList.prefix(5)))")
            
            // Create reactive filter for notes from followed users
            _ = ReactiveFilter(
                dependencies: [.followList],
                builder: { sessionData in
                    let follows = Array(sessionData.followList)
                    return NDKFilter(
                        authors: follows + [sessionData.pubkey],
                        kinds: [1], // text notes
                        limit: 100
                    )
                }
            )
            
            // For now, observe with a static filter based on initial session data
            // TODO: Implement proper reactive filter support in NDK
            var authors = Array(sessionData.followList) + [sessionData.pubkey]
            
            // If user has no follows, add some popular accounts to bootstrap the feed
            if sessionData.followList.isEmpty {
                print("📱 [SessionNotesDataSource] User has no follows, adding popular accounts to bootstrap feed")
                // Add some popular Nostr accounts
                let popularAccounts = [
                    "82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2", // jack
                    "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d", // fiatjaf
                    "04c915daefee38317fa734444acee390a8269fe5810b2241e5e6dd343dfbecc9", // ODELL
                    "6e468422dfb74a5738702a8823b9b28168abab8655faacb6853cd0ee15deee93", // Gigi
                    "e88a691e98d9987c964521dff60025f60700378a4879180dcbbb4a5027850411" // nvk
                ]
                authors.append(contentsOf: popularAccounts)
            }
            
            print("📱 [SessionNotesDataSource] Creating filter for \(authors.count) authors")
            
            // Fetch notes from the last 24 hours to ensure we get some content
            let since = Timestamp(Date().timeIntervalSince1970 - 86400) // 24 hours ago
            
            let initialFilter = NDKFilter(
                authors: authors,
                kinds: [1], // text notes
                since: since,
                limit: 200
            )
            
            dataSource = ndk.observe(
                filter: initialFilter,
                maxAge: 0,
                cachePolicy: .cacheWithNetwork
            )
            
            print("📱 [SessionNotesDataSource] Started observing notes with filter")
            
            await observeNotes()
            
        } catch {
            self.error = error
            isLoading = false
        }
    }
    
    private func observeNotes() async {
        guard let dataSource = dataSource else { return }
        
        // Monitor EOSE status
        eoseTask = Task {
            for await update in dataSource.relayUpdates {
                switch update {
                case .eose(let relay):
                    hasEOSE = true
                    print("📱 [SessionNotesDataSource] EOSE received from relay: \(relay)")
                case .event(let event, let relay):
                    print("📱 [SessionNotesDataSource] Event received from \(relay): kind=\(event.kind), content=\(String(event.content.prefix(50)))...")
                case .closed(let relay):
                    print("📱 [SessionNotesDataSource] Subscription closed on relay: \(relay)")
                }
            }
        }
        
        dataSource.$data
            .map { events in
                print("📱 [SessionNotesDataSource] Received \(events.count) notes total")
                if events.isEmpty {
                    print("📱 [SessionNotesDataSource] No notes found - check if follow list is empty or relays are connected")
                }
                return events.sorted { $0.createdAt > $1.createdAt }
            }
            .assign(to: &$notes)
        
        dataSource.$isLoading.assign(to: &$isLoading)
        dataSource.$error.assign(to: &$error)
    }
    
    /// Refresh the feed by clearing and re-fetching
    public func refresh() async {
        notes.removeAll()
        hasEOSE = false
        
        // Force network fetch by recreating the data source
        if let sessionData = sessionData {
            let since = Timestamp(Date().timeIntervalSince1970 - 86400) // 24 hours ago
            let filter = NDKFilter(
                authors: Array(sessionData.followList) + [sessionData.pubkey],
                kinds: [1], // text notes
                since: since,
                limit: 200
            )
            
            dataSource = ndk.observe(
                filter: filter,
                maxAge: 0,
                cachePolicy: .networkOnly
            )
            await observeNotes()
        }
    }
}