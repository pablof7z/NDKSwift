import Foundation

/// Actor that manages metadata for NDK events
///
/// This actor handles all the mutable metadata that was previously stored
/// in the NDKEvent class itself, such as relay tracking, publish statuses,
/// and OK messages. This separation allows events to remain immutable while
/// still tracking their lifecycle and relay interactions.
///
/// ## Usage
/// ```swift
/// let tracker = NDKEventTracker()
///
/// // Track that an event was seen on a relay
/// await tracker.markSeen(eventId: event.id, relay: RelayConstants.damus)
///
/// // Update publish status
/// await tracker.updatePublishStatus(eventId: event.id, relay: RelayConstants.damus, status: .succeeded)
///
/// // Get relay information
/// let relays = await tracker.getSeenOnRelays(eventId: event.id)
/// ```
public actor NDKEventTracker {
    /// Tracks which relays each event has been seen on
    private var seenOnRelays: [EventID: Set<String>] = [:]

    /// Tracks publish status for each event on each relay
    private var relayPublishStatuses: [EventID: [String: RelayPublishStatus]] = [:]

    /// Tracks OK messages from relays for each event
    private var relayOKMessages: [EventID: [String: OKMessage]] = [:]

    /// Tracks which relay each event was originally received from
    private var sourceRelays: [EventID: String] = [:]

    /// Custom properties for events (extensibility)
    private var customProperties: [EventID: [String: Any]] = [:]

    /// Tracks when events were first seen (for cleanup)
    private var firstSeenTimestamps: [EventID: Date] = [:]

    // MARK: - Relay Tracking

    /// Mark an event as seen on a specific relay
    /// - Parameters:
    ///   - eventId: The event ID
    ///   - relay: The relay URL
    public func markSeen(eventId: EventID, relay: String) {
        seenOnRelays[eventId, default: Set()].insert(relay)

        // Track first seen timestamp if not already tracked
        if firstSeenTimestamps[eventId] == nil {
            firstSeenTimestamps[eventId] = Date()
        }
    }

    /// Get all relays where an event has been seen
    /// - Parameter eventId: The event ID
    /// - Returns: Set of relay URLs where the event was seen
    public func getSeenOnRelays(eventId: EventID) -> Set<String> {
        return seenOnRelays[eventId] ?? Set()
    }

    /// Set the source relay for an event (where it was originally received)
    /// - Parameters:
    ///   - eventId: The event ID
    ///   - relay: The relay URL
    public func setSourceRelay(eventId: EventID, relay: String) {
        sourceRelays[eventId] = relay
        markSeen(eventId: eventId, relay: relay)
    }

    /// Get the source relay for an event
    /// - Parameter eventId: The event ID
    /// - Returns: The relay URL where the event was originally received, if any
    public func getSourceRelay(eventId: EventID) -> String? {
        return sourceRelays[eventId]
    }

    // MARK: - Publish Status Tracking

    /// Update the publish status for an event on a specific relay
    /// - Parameters:
    ///   - eventId: The event ID
    ///   - relay: The relay URL
    ///   - status: The publish status
    public func updatePublishStatus(eventId: EventID, relay: String, status: RelayPublishStatus) {
        relayPublishStatuses[eventId, default: [:]][relay] = status
    }

    /// Get the publish status for an event on a specific relay
    /// - Parameters:
    ///   - eventId: The event ID
    ///   - relay: The relay URL
    /// - Returns: The publish status, if any
    public func getPublishStatus(eventId: EventID, relay: String) -> RelayPublishStatus? {
        return relayPublishStatuses[eventId]?[relay]
    }

    /// Get all publish statuses for an event
    /// - Parameter eventId: The event ID
    /// - Returns: Dictionary mapping relay URLs to their publish statuses
    public func getRelayPublishStatuses(eventId: EventID) -> [String: RelayPublishStatus] {
        return relayPublishStatuses[eventId] ?? [:]
    }

    /// Get all relays where an event was successfully published
    /// - Parameter eventId: The event ID
    /// - Returns: Array of relay URLs where publishing succeeded
    public func getSuccessfullyPublishedRelays(eventId: EventID) -> [String] {
        let statuses = getRelayPublishStatuses(eventId: eventId)
        return statuses.compactMap { relay, status in
            switch status {
            case .succeeded:
                return relay
            default:
                return nil
            }
        }
    }

    /// Get all relays where publishing failed for an event
    /// - Parameter eventId: The event ID
    /// - Returns: Array of relay URLs where publishing failed
    public func getFailedPublishRelays(eventId: EventID) -> [String] {
        let statuses = getRelayPublishStatuses(eventId: eventId)
        return statuses.compactMap { relay, status in
            switch status {
            case .failed:
                return relay
            default:
                return nil
            }
        }
    }

    /// Check if an event was successfully published to at least one relay
    /// - Parameter eventId: The event ID
    /// - Returns: True if the event was published to at least one relay
    public func wasPublished(eventId: EventID) -> Bool {
        return !getSuccessfullyPublishedRelays(eventId: eventId).isEmpty
    }

    // MARK: - OK Message Tracking

    /// Store an OK message from a relay for an event
    /// - Parameters:
    ///   - eventId: The event ID
    ///   - relay: The relay URL
    ///   - accepted: Whether the relay accepted the event
    ///   - message: Optional message from the relay
    public func addOKMessage(eventId: EventID, relay: String, accepted: Bool, message: String?) {
        let okMessage = OKMessage(accepted: accepted, message: message, receivedAt: Date())
        relayOKMessages[eventId, default: [:]][relay] = okMessage
    }

    /// Get OK messages for an event from all relays
    /// - Parameter eventId: The event ID
    /// - Returns: Dictionary mapping relay URLs to their OK messages
    public func getRelayOKMessages(eventId: EventID) -> [String: OKMessage] {
        return relayOKMessages[eventId] ?? [:]
    }

    /// Get the OK message for an event from a specific relay
    /// - Parameters:
    ///   - eventId: The event ID
    ///   - relay: The relay URL
    /// - Returns: The OK message, if any
    public func getOKMessage(eventId: EventID, relay: String) -> OKMessage? {
        return relayOKMessages[eventId]?[relay]
    }

    // MARK: - Custom Properties

    /// Set a custom property for an event
    /// - Parameters:
    ///   - eventId: The event ID
    ///   - key: The property key
    ///   - value: The property value
    public func setCustomProperty(eventId: EventID, key: String, value: Any) {
        customProperties[eventId, default: [:]][key] = value
    }

    /// Get a custom property for an event
    /// - Parameters:
    ///   - eventId: The event ID
    ///   - key: The property key
    /// - Returns: The property value, if any
    public func getCustomProperty(eventId: EventID, key: String) -> Any? {
        return customProperties[eventId]?[key]
    }

    /// Get all custom properties for an event
    /// - Parameter eventId: The event ID
    /// - Returns: Dictionary of custom properties
    public func getCustomProperties(eventId: EventID) -> [String: Any] {
        return customProperties[eventId] ?? [:]
    }

    /// Get the timestamp when an event was first seen
    /// - Parameter eventId: The event ID
    /// - Returns: The date when the event was first seen, if tracked
    public func getFirstSeenTimestamp(eventId: EventID) -> Date? {
        return firstSeenTimestamps[eventId]
    }

    // MARK: - Cleanup

    /// Remove all tracking data for an event
    /// - Parameter eventId: The event ID to clean up
    public func removeEvent(eventId: EventID) {
        seenOnRelays.removeValue(forKey: eventId)
        relayPublishStatuses.removeValue(forKey: eventId)
        relayOKMessages.removeValue(forKey: eventId)
        sourceRelays.removeValue(forKey: eventId)
        customProperties.removeValue(forKey: eventId)
        firstSeenTimestamps.removeValue(forKey: eventId)
    }

    /// Remove tracking data for events older than the specified date
    /// - Parameter cutoffDate: Events older than this date will be removed
    public func cleanupOldEvents(cutoffDate: Date) {
        // Find events older than the cutoff date
        let eventIdsToRemove = firstSeenTimestamps.compactMap { eventId, timestamp in
            timestamp < cutoffDate ? eventId : nil
        }

        // Remove old events
        for eventId in eventIdsToRemove {
            removeEvent(eventId: eventId)
        }

        if !eventIdsToRemove.isEmpty {
            NDKLogger.log(.debug, category: .event, "Cleaned up \(eventIdsToRemove.count) events older than \(cutoffDate)")
        }
    }

    /// Get statistics about tracked events
    /// - Returns: Dictionary with tracking statistics
    public func getStats() -> [String: Any] {
        return [
            "trackedEvents": seenOnRelays.count,
            "totalSeenRelays": seenOnRelays.values.reduce(0) { $0 + $1.count },
            "eventsWithPublishStatus": relayPublishStatuses.count,
            "eventsWithOKMessages": relayOKMessages.count,
            "eventsWithCustomProperties": customProperties.count,
            "eventsWithTimestamps": firstSeenTimestamps.count
        ]
    }
}
