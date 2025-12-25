import Foundation

// MARK: - NDK Telemetry Extension

public extension NDK {
    /// Start a new telemetry span
    func startSpan(
        _ name: String,
        category: TelemetryCategory,
        parent: SpanContext? = nil
    ) -> Span {
        tracer.startSpan(name: name, category: category, parent: parent)
    }

    /// Execute an operation with a telemetry span
    func withSpan<T>(
        _ name: String,
        category: TelemetryCategory,
        parent: SpanContext? = nil,
        _ operation: (Span) throws -> T
    ) rethrows -> T {
        try tracer.withSpan(name: name, category: category, parent: parent, operation)
    }

    /// Execute an async operation with a telemetry span
    func withSpan<T>(
        _ name: String,
        category: TelemetryCategory,
        parent: SpanContext? = nil,
        _ operation: (Span) async throws -> T
    ) async rethrows -> T {
        try await tracer.withSpan(name: name, category: category, parent: parent, operation)
    }
}

// MARK: - Common Span Attribute Keys

/// Standard attribute keys for NDK telemetry spans
public enum SpanAttributes {
    // Relay attributes
    public static let relayUrl = "relay.url"
    public static let relayUrls = "relay.urls"
    public static let relayCount = "relay.count"
    public static let relayOrigin = "relay.origin"
    public static let relayState = "relay.state"
    public static let relayConnected = "relay.connected"
    public static let relayHealthScore = "relay.health_score"

    // Event attributes
    public static let eventId = "event.id"
    public static let eventKind = "event.kind"
    public static let eventPubkey = "event.pubkey"
    public static let eventSize = "event.size_bytes"
    public static let eventPTagCount = "event.p_tag_count"
    public static let eventETagCount = "event.e_tag_count"

    // Subscription attributes
    public static let subscriptionId = "subscription.id"
    public static let subscriptionFingerprint = "subscription.fingerprint"
    public static let subscriptionGroupable = "subscription.groupable"
    public static let subscriptionCloseOnEose = "subscription.close_on_eose"

    // Filter attributes
    public static let filterAuthors = "filter.authors"
    public static let filterKinds = "filter.kinds"
    public static let filterLimit = "filter.limit"

    // Selection/decision attributes
    public static let decisionReason = "decision.reason"
    public static let decisionOutcome = "decision.outcome"
    public static let selectionSource = "selection.source"
    public static let selectionCount = "selection.count"
    public static let selectionCandidates = "selection.candidates"

    // Performance attributes
    public static let durationMs = "duration_ms"
    public static let latencyMs = "latency_ms"
    public static let responseTimeMs = "response_time_ms"

    // Error attributes
    public static let errorType = "error.type"
    public static let errorMessage = "error.message"

    // Grouping attributes
    public static let groupId = "group.id"
    public static let groupSize = "group.size"
    public static let groupMerged = "group.merged"
    public static let groupSavedMessages = "group.saved_messages"

    // Verification attributes
    public static let verificationSampled = "verification.sampled"
    public static let verificationValid = "verification.valid"
    public static let verificationSampleRatio = "verification.sample_ratio"

    // Cache attributes
    public static let cacheHit = "cache.hit"
    public static let cachePolicy = "cache.policy"
    public static let cacheAge = "cache.age_ms"

    // Connection attributes
    public static let connectionTrigger = "connection.trigger"
    public static let connectionState = "connection.state"
    public static let connectionAttempt = "connection.attempt"

    // Pool attributes
    public static let poolSize = "pool.size"
    public static let poolConnectedCount = "pool.connected_count"

    // Auth attributes
    public static let authRequired = "auth.required"
    public static let authMethod = "auth.method"
    public static let authSuccess = "auth.success"
}

// MARK: - Relay Origin Telemetry

extension NDKRelayOrigin {
    var telemetryValue: String {
        switch self {
        case .appRelays: return "app_relays"
        case .outbox: return "outbox"
        case .discovery: return "discovery"
        }
    }
}
