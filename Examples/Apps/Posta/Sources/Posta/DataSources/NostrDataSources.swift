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
    
    private let dataSource: NDKDataSource<NDKEvent>
    
    public init(ndk: NDK, pubkey: String) {
        self.dataSource = ndk.observe(
            filter: NDKFilter(
                authors: [pubkey],
                kinds: [0]
            ),
            maxAge: 0,  // Real-time updates
            cachePolicy: .cacheWithNetwork
        )
        
        Task {
            await observeProfile()
        }
    }
    
    private func observeProfile() async {
        dataSource.$data
            .compactMap { events in
                events.sorted { $0.createdAt > $1.createdAt }.first
            }
            .map { event in
                JSONCoding.safeDecode(NDKUserProfile.self, from: event.content.data(using: .utf8) ?? Data())
            }
            .assign(to: &$profile)
        
        dataSource.$isLoading.assign(to: &$isLoading)
        dataSource.$error.assign(to: &$error)
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
    public let ndk: NDK
    
    public init(ndk: NDK) {
        self.ndk = ndk
        
        Task {
            await setupSession()
        }
    }
    
    deinit {
        eoseTask?.cancel()
    }
    
    private func setupSession() async {
        guard let signer = ndk.signer else {
            self.error = NostrError.signerRequired
            return
        }
        
        do {
            isLoading = true
            
            // Start session with proper configuration
            let config = NDKSessionConfiguration(
                dataRequirements: [.followList, .muteList, .webOfTrust(depth: 2)],
                preloadStrategy: .progressive
            )
            
            let sessionData = try await ndk.startSession(signer: signer, config: config)
            self.sessionData = sessionData
            
            // Create reactive filter for notes from followed users
            let filter = ReactiveFilter(
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
            let initialFilter = NDKFilter(
                authors: Array(sessionData.followList) + [sessionData.pubkey],
                kinds: [1], // text notes
                limit: 100
            )
            
            dataSource = ndk.observe(
                filter: initialFilter,
                maxAge: 0,
                cachePolicy: .cacheWithNetwork
            )
            
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
    
    /// Refresh the feed by clearing and re-fetching
    public func refresh() async {
        notes.removeAll()
        hasEOSE = false
        
        // Force network fetch by recreating the data source
        if let sessionData = sessionData {
            let filter = NDKFilter(
                authors: Array(sessionData.followList) + [sessionData.pubkey],
                kinds: [1], // text notes
                limit: 100
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