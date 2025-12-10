/// Helper protocol for events that can be created and published
public protocol NDKPublishableEvent {
    var event: NDKEvent { get }
    init(event: NDKEvent)
}

/// Generic helper to eliminate duplicate createAndPublish patterns
public enum EventPublishingHelper {

    /// Generic createAndPublish method that works with any NDKPublishableEvent
    /// - Parameters:
    ///   - type: The type of event to create
    ///   - ndk: NDK instance for publishing
    ///   - logPrefix: Prefix for logging (e.g., "NDKCashuTokenEvent")
    ///   - createClosure: Closure that creates the event
    /// - Returns: The created and published event
    @discardableResult
    public static func createAndPublish<T: NDKPublishableEvent>(
        type: T.Type,
        ndk: NDK,
        logPrefix: String,
        createClosure: () async throws -> T
    ) async throws -> T {
        let createdEvent = try await createClosure()

        let publishedRelays = try await ndk.publish(createdEvent.event)
        NDKLogger.log(.info, category: .event, "\(logPrefix) - Published to \(publishedRelays.count) relays")

        return createdEvent
    }

    /// Variant that logs the event ID
    @discardableResult
    public static func createAndPublishWithId<T: NDKPublishableEvent>(
        type: T.Type,
        ndk: NDK,
        logPrefix: String,
        createClosure: () async throws -> T
    ) async throws -> T {
        let createdEvent = try await createClosure()

        _ = try await ndk.publish(createdEvent.event)
        NDKLogger.log(.info, category: .event, "\(logPrefix) - Published event: \(createdEvent.event.id)")

        return createdEvent
    }
}