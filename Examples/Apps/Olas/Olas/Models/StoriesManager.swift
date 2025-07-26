import Foundation
import NDKSwift
import SwiftUI

@MainActor
class StoriesManager: ObservableObject {
    @Published var userStories: [UserStoryCollection] = []
    @Published var currentUserStories: [Story] = []
    @Published var isLoading = false
    @Published var hasActiveStory = false
    
    private let nostrManager: NostrManager
    private var storiesTask: Task<Void, Never>?
    private var profileTasks: [String: Task<Void, Never>] = [:]
    
    // Use a custom kind for stories (30078 - ephemeral content)
    private let storyKind: Int = 30078
    private let storyDuration: TimeInterval = 24 * 60 * 60 // 24 hours
    
    init(nostrManager: NostrManager) {
        self.nostrManager = nostrManager
    }
    
    deinit {
        storiesTask?.cancel()
        profileTasks.values.forEach { $0.cancel() }
    }
    
    func startObservingStories() {
        storiesTask?.cancel()
        
        guard let ndk = nostrManager.ndk else { return }
        
        storiesTask = Task {
            isLoading = true
            
            // Get stories from the last 24 hours
            let since = Timestamp(Int64(Date().addingTimeInterval(-storyDuration).timeIntervalSince1970))
            
            let filter = NDKFilter(
                kinds: [storyKind],
                since: since
            )
            
            let dataSource = ndk.observe(
                filter: filter,
                maxAge: 0,
                cachePolicy: .cacheWithNetwork
            )
            
            // Group stories by author
            var storiesByAuthor: [String: [Story]] = [:]
            
            for await event in dataSource.events {
                // Check if story is not expired
                if let expirationTag = event.tags.first(where: { $0.count >= 2 && $0[0] == "expiration" }),
                   let expirationTimestamp = Int64(expirationTag[1]),
                   expirationTimestamp < Int64(Date().timeIntervalSince1970) {
                    continue // Skip expired stories
                }
                
                let story = Story(from: event)
                
                if storiesByAuthor[event.pubkey] != nil {
                    storiesByAuthor[event.pubkey]?.append(story)
                } else {
                    storiesByAuthor[event.pubkey] = [story]
                }
                
                // Update UI
                await updateUserStories(from: storiesByAuthor)
                
                // Load profile for this author
                loadProfileForAuthor(event.pubkey)
                
                // Check if current user has active story
                if let signer = ndk.signer,
                   let signerPubkey = try? await signer.pubkey,
                   event.pubkey == signerPubkey {
                    hasActiveStory = true
                }
            }
            
            isLoading = false
        }
    }
    
    private func updateUserStories(from storiesByAuthor: [String: [Story]]) async {
        var collections: [UserStoryCollection] = []
        
        // Current user's stories first
        if let ndk = nostrManager.ndk,
           let signer = ndk.signer,
           let currentUserPubkey = try? await signer.pubkey,
           let currentStories = storiesByAuthor[currentUserPubkey] {
            let sortedStories = currentStories.sorted { $0.timestamp > $1.timestamp }
            collections.append(UserStoryCollection(
                authorPubkey: currentUserPubkey,
                stories: sortedStories,
                isCurrentUser: true
            ))
        }
        
        // Other users' stories
        for (pubkey, stories) in storiesByAuthor {
            if let ndk = nostrManager.ndk,
               let signer = ndk.signer,
               let signerPubkey = try? await signer.pubkey,
               pubkey != signerPubkey {
                let sortedStories = stories.sorted { $0.timestamp > $1.timestamp }
                collections.append(UserStoryCollection(
                    authorPubkey: pubkey,
                    stories: sortedStories,
                    isCurrentUser: false
                ))
            }
        }
        
        // Sort by most recent story
        collections.sort { collection1, collection2 in
            let time1 = collection1.stories.first?.timestamp ?? Date.distantPast
            let time2 = collection2.stories.first?.timestamp ?? Date.distantPast
            return time1 > time2
        }
        
        self.userStories = collections
    }
    
    private func loadProfileForAuthor(_ pubkey: String) {
        guard let profileManager = nostrManager.ndk?.profileManager else { return }
        
        profileTasks[pubkey]?.cancel()
        
        profileTasks[pubkey] = Task {
            for await profile in await profileManager.observe(for: pubkey, maxAge: 3600) {
                if let profile = profile {
                    // Update all stories for this author
                    for index in userStories.indices {
                        if userStories[index].authorPubkey == pubkey {
                            userStories[index].authorProfile = profile
                        }
                    }
                }
                break
            }
        }
    }
    
    func createStory(with imageData: Data, caption: String, filters: [String] = []) async throws {
        guard let ndk = nostrManager.ndk,
              let signer = ndk.signer else {
            throw StoryError.notAuthenticated
        }
        
        // Upload image to Blossom
        // For now, create a placeholder URL - in production this would upload to Blossom servers
        // TODO: Integrate with Blossom using BlossomClient like in CreatePostView
        let imageURL = "https://example.com/temp-story-\(UUID().uuidString).jpg"
        
        // Create story event
        let storyId = "story-\(UUID().uuidString)"
        let expiration = Int64(Date().addingTimeInterval(storyDuration).timeIntervalSince1970)
        
        var tags: [[String]] = [
            ["d", storyId],
            ["title", "Story"],
            ["image", imageURL],
            ["published_at", "\(Int64(Date().timeIntervalSince1970))"],
            ["expiration", "\(expiration)"]
        ]
        
        // Add filter tags if any
        for filter in filters {
            tags.append(["filter", filter])
        }
        
        // Add imeta tag for the image
        if let dimensions = getImageDimensions(from: imageData) {
            tags.append([
                "imeta",
                "url \(imageURL)",
                "dim \(dimensions.width)x\(dimensions.height)",
                "m image/jpeg"
            ])
        }
        
        let storyEvent = try await NDKEventBuilder(ndk: ndk)
            .kind(storyKind)
            .content(caption)
            .tags(tags)
            .build(signer: signer)
        
        _ = try await ndk.publish(storyEvent)
        
        // Update local state
        hasActiveStory = true
        
        // Trigger haptic feedback
        OlasDesign.Haptic.success()
    }
    
    func deleteStory(_ storyId: String) async throws {
        guard let ndk = nostrManager.ndk,
              let signer = ndk.signer else {
            throw StoryError.notAuthenticated
        }
        
        // Create deletion event
        let deletionEvent = try await NDKEventBuilder(ndk: ndk)
            .kind(EventKind.deletion)
            .content("Story deleted")
            .tags([
                ["e", storyId],
                ["k", "\(storyKind)"]
            ])
            .build(signer: signer)
        
        _ = try await ndk.publish(deletionEvent)
        
        // Update local state
        if let currentUserPubkey = try? await signer.pubkey {
            userStories.removeAll { collection in
                collection.authorPubkey == currentUserPubkey &&
                collection.stories.contains { $0.id == storyId }
            }
            
            // Check if user still has active stories
            hasActiveStory = userStories.contains { $0.authorPubkey == currentUserPubkey }
        }
    }
    
    func markStoryAsViewed(_ storyId: String) {
        // Store viewed state locally
        UserDefaults.standard.set(true, forKey: "story_viewed_\(storyId)")
    }
    
    func isStoryViewed(_ storyId: String) -> Bool {
        UserDefaults.standard.bool(forKey: "story_viewed_\(storyId)")
    }
    
    private func getImageDimensions(from imageData: Data) -> (width: Int, height: Int)? {
        #if os(iOS)
        if let image = UIImage(data: imageData) {
            return (width: Int(image.size.width), height: Int(image.size.height))
        }
        #elseif os(macOS)
        if let image = NSImage(data: imageData) {
            return (width: Int(image.size.width), height: Int(image.size.height))
        }
        #endif
        return nil
    }
}

// MARK: - Models

struct UserStoryCollection: Identifiable {
    let id = UUID()
    let authorPubkey: String
    var authorProfile: NDKUserProfile?
    var stories: [Story]
    let isCurrentUser: Bool
    
    var hasUnviewedStories: Bool {
        stories.contains { story in
            !UserDefaults.standard.bool(forKey: "story_viewed_\(story.id)")
        }
    }
}

struct EnhancedStory: Identifiable {
    let id: String
    let authorPubkey: String
    var authorProfile: NDKUserProfile?
    let content: String
    let mediaURLs: [String]
    let filters: [String]
    let timestamp: Date
    let expirationDate: Date
    let event: NDKEvent
    
    var isExpired: Bool {
        Date() > expirationDate
    }
    
    var timeRemaining: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: Date(), to: expirationDate) ?? "Expired"
    }
}

// MARK: - Errors

enum StoryError: LocalizedError {
    case notAuthenticated
    case uploadFailed
    case eventCreationFailed
    case deletionFailed
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be logged in to create stories"
        case .uploadFailed:
            return "Failed to upload image"
        case .eventCreationFailed:
            return "Failed to create story"
        case .deletionFailed:
            return "Failed to delete story"
        }
    }
}

// MARK: - Utilities

struct RelativeTimeFormatter {
    static func format(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}