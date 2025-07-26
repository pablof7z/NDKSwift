import Foundation
import NDKSwift
import SwiftUI
import Combine

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
                kinds: [EventKind.metadata]
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

// MARK: - Image Feed Data Source

/// Data source for image posts (kind 1 with image tags)
@MainActor
public class ImageFeedDataSource: ObservableObject {
    @Published public private(set) var posts: [NDKEvent] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var error: Error?
    
    private let dataSource: NDKDataSource<NDKEvent>
    
    public init(ndk: NDK, authors: [String]? = nil, limit: Int = 50) {
        var filter = NDKFilter(kinds: [EventKind.textNote])
        filter.authors = authors
        filter.limit = limit
        
        self.dataSource = ndk.observe(
            filter: filter,
            maxAge: 0,  // Real-time updates
            cachePolicy: .cacheWithNetwork
        )
        
        Task {
            await observePosts()
        }
    }
    
    private func observePosts() async {
        dataSource.$data
            .map { events in
                // Filter for events with image tags
                events.filter { event in
                    event.tags.contains { tag in
                        tag.count >= 2 && (tag[0] == "imeta" || 
                                         (tag[0] == "r" && tag[1].hasSuffix(".jpg")) ||
                                         (tag[0] == "r" && tag[1].hasSuffix(".jpeg")) ||
                                         (tag[0] == "r" && tag[1].hasSuffix(".png")) ||
                                         (tag[0] == "r" && tag[1].hasSuffix(".gif")) ||
                                         (tag[0] == "r" && tag[1].hasSuffix(".webp")))
                    }
                }.sorted { $0.createdAt > $1.createdAt }
            }
            .assign(to: &$posts)
        
        dataSource.$isLoading.assign(to: &$isLoading)
        dataSource.$error.assign(to: &$error)
    }
}

// MARK: - Hashtag Feed Data Source

/// Data source for posts with specific hashtags
@MainActor
public class HashtagFeedDataSource: ObservableObject {
    @Published public private(set) var posts: [NDKEvent] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var error: Error?
    
    private let dataSource: NDKDataSource<NDKEvent>
    private let hashtag: String
    
    public init(ndk: NDK, hashtag: String, limit: Int = 50) {
        self.hashtag = hashtag.lowercased().replacingOccurrences(of: "#", with: "")
        
        let filter = NDKFilter(
            kinds: [EventKind.textNote],
            limit: limit,
            tags: ["t": Set([self.hashtag])]
        )
        
        self.dataSource = ndk.observe(
            filter: filter,
            maxAge: 0,  // Real-time updates
            cachePolicy: .cacheWithNetwork
        )
        
        Task {
            await observePosts()
        }
    }
    
    private func observePosts() async {
        dataSource.$data
            .map { events in
                events.sorted { $0.createdAt > $1.createdAt }
            }
            .assign(to: &$posts)
        
        dataSource.$isLoading.assign(to: &$isLoading)
        dataSource.$error.assign(to: &$error)
    }
}

// MARK: - User Posts Data Source

/// Data source for a specific user's posts
@MainActor
public class UserPostsDataSource: ObservableObject {
    @Published public private(set) var posts: [NDKEvent] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var error: Error?
    
    private let dataSource: NDKDataSource<NDKEvent>
    
    public init(ndk: NDK, pubkey: String, includeReplies: Bool = false) {
        var filter = NDKFilter(
            authors: [pubkey],
            kinds: [EventKind.textNote]
        )
        
        if !includeReplies {
            // This would filter out replies if NDK supported it
            // For now, we'll filter client-side
        }
        
        self.dataSource = ndk.observe(
            filter: filter,
            maxAge: 0,  // Real-time updates
            cachePolicy: .cacheWithNetwork
        )
        
        Task {
            await observePosts(includeReplies: includeReplies)
        }
    }
    
    private func observePosts(includeReplies: Bool) async {
        dataSource.$data
            .map { events in
                var filtered = events
                
                if !includeReplies {
                    // Filter out replies (events with "e" or "p" tags that indicate replies)
                    filtered = events.filter { event in
                        !event.isReply
                    }
                }
                
                // Filter for events with images
                return filtered.filter { event in
                    event.tags.contains { tag in
                        tag.count >= 2 && (tag[0] == "imeta" || 
                                         (tag[0] == "r" && self.isImageURL(tag[1])))
                    }
                }.sorted { $0.createdAt > $1.createdAt }
            }
            .assign(to: &$posts)
        
        dataSource.$isLoading.assign(to: &$isLoading)
        dataSource.$error.assign(to: &$error)
    }
    
    private func isImageURL(_ url: String) -> Bool {
        let imageExtensions = [".jpg", ".jpeg", ".png", ".gif", ".webp"]
        return imageExtensions.contains { url.lowercased().hasSuffix($0) }
    }
}

// MARK: - Extensions

extension NDKEvent {
    var isReply: Bool {
        // Check for reply markers
        tags.contains { tag in
            (tag.count >= 2 && tag[0] == "e" && tag.count >= 4 && tag[3] == "reply") ||
            (tag.count >= 2 && tag[0] == "e" && !tags.contains { $0[0] == "e" && $0.count >= 4 && $0[3] == "root" })
        }
    }
}