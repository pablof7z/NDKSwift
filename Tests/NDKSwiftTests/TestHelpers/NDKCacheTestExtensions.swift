import Foundation
@testable import NDKSwift

// MARK: - Test Extensions for NDKCache

extension NDKCache {
    /// Save a user profile to the cache (test helper)
    func saveProfile(_ profile: NDKUserProfile, pubkey: String) async throws {
        // Convert profile to metadata dictionary
        let encoder = JSONEncoder()
        let data = try encoder.encode(profile)
        guard let metadata = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NDKError.invalidInput(message: "Failed to convert profile to metadata")
        }
        
        // Use current timestamp and generate a fake event ID
        let timestamp = Timestamp.now
        let eventId = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        
        try await saveProfileMetadata(pubkey: pubkey, metadata: metadata, updatedAt: timestamp, eventId: eventId)
    }
    
    /// Get a user profile from the cache (test helper)
    func getProfile(pubkey: String) async -> NDKUserProfile? {
        guard let (metadata, _, _) = await getProfileMetadata(pubkey: pubkey) else {
            return nil
        }
        
        // Convert metadata back to profile
        do {
            let data = try JSONSerialization.data(withJSONObject: metadata)
            return try JSONDecoder().decode(NDKUserProfile.self, from: data)
        } catch {
            return nil
        }
    }
    
    /// Observe profile changes (test helper)
    func observeProfile(pubkey: String, includeExisting: Bool = true) async -> AsyncStream<NDKUserProfile?> {
        AsyncStream { continuation in
            Task {
                // Send existing profile if requested
                if includeExisting {
                    let existingProfile = await getProfile(pubkey: pubkey)
                    continuation.yield(existingProfile)
                }
                
                // Create a filter for profile events
                let filter = NDKFilter(
                    authors: [pubkey],
                    kinds: [EventKind.metadata]
                )
                
                // Observe events matching the filter
                let eventStream = await observeEvents(matching: filter, includeExisting: false)
                
                do {
                    for try await events in eventStream {
                        // Process the latest event
                        if let latestEvent = events.sorted(by: { $0.createdAt > $1.createdAt }).first {
                            // Parse the profile from the event
                            if let data = latestEvent.content.data(using: .utf8),
                               let profile = try? JSONDecoder().decode(NDKUserProfile.self, from: data) {
                                continuation.yield(profile)
                            }
                        }
                    }
                } catch {
                    continuation.finish()
                }
            }
        }
    }
}