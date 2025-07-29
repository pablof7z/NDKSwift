import Foundation
import NDKSwift
import SwiftUI
import Combine

// MARK: - Follow List Data Source

/// Data source for user's follow list (kind:3 events)
@MainActor
public class NDKUIFollowListDataSource: ObservableObject {
    @Published public private(set) var followList: Set<String> = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var error: Error?
    @Published public private(set) var lastUpdate: Date?
    
    private let dataSource: NDKDataSource<NDKEvent>
    
    public init(ndk: NDK, pubkey: String) {
        self.dataSource = ndk.observe(
            filter: NDKFilter(
                authors: [pubkey],
                kinds: [EventKind.contacts]
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
    
    public func isFollowing(_ pubkey: String) -> Bool {
        followList.contains(pubkey)
    }
}