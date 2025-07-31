import Foundation
import NDKSwift
import SwiftUI
import Combine

// MARK: - Multiple Profiles Data Source

/// Data source for multiple user profiles (e.g., for contact lists)
@MainActor
public class NDKUIMultipleProfilesDataSource: ObservableObject {
    @Published public private(set) var profiles: [String: NDKUserMetadata] = [:]
    @Published public private(set) var isLoading = false
    @Published public private(set) var error: Error?
    
    private let dataSource: NDKSubscription<NDKEvent>
    private let pubkeys: Set<String>
    
    public init(ndk: NDK, pubkeys: Set<String>) {
        self.pubkeys = pubkeys
        self.dataSource = ndk.subscribe(
            filter: NDKFilter(
                authors: Array(pubkeys),
                kinds: [EventKind.metadata]
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
                var profileDict: [String: NDKUserMetadata] = [:]
                
                // Group events by author
                let eventsByAuthor = Dictionary(grouping: events) { $0.pubkey }
                
                // Get the latest profile for each author
                for (pubkey, authorEvents) in eventsByAuthor {
                    if let latestEvent = authorEvents.sorted(by: { $0.createdAt > $1.createdAt }).first {
                        profileDict[pubkey] = NDKUserMetadata(event: latestEvent)
                    }
                }
                
                return profileDict
            }
            .assign(to: &$profiles)
        
        dataSource.$isLoading.assign(to: &$isLoading)
        dataSource.$error.assign(to: &$error)
    }
    
    public func profile(for pubkey: String) -> NDKUserMetadata? {
        profiles[pubkey]
    }
}