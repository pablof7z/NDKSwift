import SwiftUI
import NDKSwift

@Observable
@MainActor
final class CollectionsManager {
    private(set) var collections: [NDKPictureCurationSet] = []
    private(set) var isLoading = false

    private let ndk: NDK
    private var subscriptionTask: Task<Void, Never>?

    init(ndk: NDK) {
        self.ndk = ndk
    }

    func startSubscription() {
        subscriptionTask?.cancel()
        subscriptionTask = Task {
            guard let currentUser = await ndk.currentUser else { return }
            isLoading = true

            let filter = NDKFilter(
                authors: [currentUser.pubkey],
                kinds: [OlasConstants.EventKinds.pictureCurationSet]
            )

            let subscription = ndk.subscribe(filter: filter, cachePolicy: .cacheWithNetwork)

            for await event in subscription.events {
                guard !Task.isCancelled else { break }
                let set = NDKPictureCurationSet(event: event)

                // Replace if same identifier exists (newer version), otherwise add
                if let existingIndex = collections.firstIndex(where: { $0.identifier == set.identifier }) {
                    if set.createdAt > collections[existingIndex].createdAt {
                        collections[existingIndex] = set
                    }
                } else {
                    collections.append(set)
                }

                // Sort by createdAt descending
                collections.sort { $0.createdAt > $1.createdAt }
                isLoading = false
            }

            isLoading = false
        }
    }

    func stopSubscription() {
        subscriptionTask?.cancel()
        subscriptionTask = nil
    }

    /// Fetch collections for any user (not just current user)
    /// Returns a stream that the caller can iterate over
    func subscribeToCollections(for pubkey: String) -> AsyncStream<[NDKPictureCurationSet]> {
        AsyncStream { continuation in
            let task = Task {
                let filter = NDKFilter(
                    authors: [pubkey],
                    kinds: [OlasConstants.EventKinds.pictureCurationSet]
                )

                var results: [String: NDKPictureCurationSet] = [:]
                let subscription = ndk.subscribe(filter: filter, cachePolicy: .cacheWithNetwork)

                for await event in subscription.events {
                    guard !Task.isCancelled else { break }
                    let set = NDKPictureCurationSet(event: event)
                    let identifier = set.identifier ?? event.id

                    // Keep newest version of each collection
                    if let existing = results[identifier] {
                        if set.createdAt > existing.createdAt {
                            results[identifier] = set
                        }
                    } else {
                        results[identifier] = set
                    }

                    // Yield updated sorted array
                    let sorted = Array(results.values).sorted { $0.createdAt > $1.createdAt }
                    continuation.yield(sorted)
                }

                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// Create a new collection
    func createCollection(title: String, description: String? = nil) async throws -> NDKPictureCurationSet {
        // Generate unique identifier from title + timestamp
        let identifier = title.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .appending("-\(Int(Date().timeIntervalSince1970))")

        let (event, _) = try await ndk.publish { builder in
            var b = builder
                .kind(OlasConstants.EventKinds.pictureCurationSet)
                .dTag(identifier)
                .tag([NostrConstants.TagName.title, title])
                .content("")

            if let description, !description.isEmpty {
                b = b.tag([NostrConstants.TagName.description, description])
            }

            return b
        }

        let newSet = NDKPictureCurationSet(event: event)
        collections.insert(newSet, at: 0)
        return newSet
    }

    /// Add a picture to a collection
    func addPicture(_ pictureEvent: NDKEvent, to collection: NDKPictureCurationSet) async throws {
        // Don't add duplicates
        guard !collection.contains(eventId: pictureEvent.id) else { return }

        let (event, _) = try await ndk.publish { builder in
            var b = builder
                .kind(OlasConstants.EventKinds.pictureCurationSet)
                .dTag(collection.identifier ?? "")
                .content(collection.content)

            // Copy existing tags
            for tag in collection.tags {
                // Skip the d tag since we already set it
                if tag.first == NostrConstants.TagName.identifier { continue }
                b = b.tag(tag)
            }

            // Add the new picture reference
            b = b.tag([NostrConstants.TagName.event, pictureEvent.id])

            return b
        }

        // Update local state
        let updatedSet = NDKPictureCurationSet(event: event)
        if let index = collections.firstIndex(where: { $0.identifier == collection.identifier }) {
            collections[index] = updatedSet
        }
    }

    /// Remove a picture from a collection
    func removePicture(_ pictureEventId: EventID, from collection: NDKPictureCurationSet) async throws {
        let (event, _) = try await ndk.publish { builder in
            var b = builder
                .kind(OlasConstants.EventKinds.pictureCurationSet)
                .dTag(collection.identifier ?? "")
                .content(collection.content)

            // Copy existing tags except the one being removed
            for tag in collection.tags {
                if tag.first == NostrConstants.TagName.identifier { continue }
                if tag.first == NostrConstants.TagName.event && tag.count > 1 && tag[1] == pictureEventId {
                    continue
                }
                b = b.tag(tag)
            }

            return b
        }

        let updatedSet = NDKPictureCurationSet(event: event)
        if let index = collections.firstIndex(where: { $0.identifier == collection.identifier }) {
            collections[index] = updatedSet
        }
    }

    /// Update collection cover image
    func setCoverImage(_ imageUrl: String, for collection: NDKPictureCurationSet) async throws {
        let (event, _) = try await ndk.publish { builder in
            var b = builder
                .kind(OlasConstants.EventKinds.pictureCurationSet)
                .dTag(collection.identifier ?? "")
                .content(collection.content)

            // Copy existing tags except image tag
            for tag in collection.tags {
                if tag.first == NostrConstants.TagName.identifier { continue }
                if tag.first == NostrConstants.TagName.image { continue }
                b = b.tag(tag)
            }

            // Add new image tag
            b = b.tag([NostrConstants.TagName.image, imageUrl])

            return b
        }

        let updatedSet = NDKPictureCurationSet(event: event)
        if let index = collections.firstIndex(where: { $0.identifier == collection.identifier }) {
            collections[index] = updatedSet
        }
    }

    /// Delete a collection (publish empty version)
    func deleteCollection(_ collection: NDKPictureCurationSet) async throws {
        // For parameterized replaceable events, publish with same d-tag but no items
        _ = try await ndk.publish { builder in
            builder
                .kind(OlasConstants.EventKinds.pictureCurationSet)
                .dTag(collection.identifier ?? "")
                .content("")
        }

        collections.removeAll { $0.identifier == collection.identifier }
    }
}
