import Foundation

// MARK: - Span Context

/// Unique identifier for a trace (groups related spans)
public typealias TraceID = String

/// Unique identifier for a span within a trace
public typealias SpanID = String

/// Context that links spans together in a trace hierarchy
public struct SpanContext: Sendable, Equatable {
    public let traceId: TraceID
    public let spanId: SpanID
    public let parentSpanId: SpanID?

    public init(traceId: TraceID, spanId: SpanID, parentSpanId: SpanID? = nil) {
        self.traceId = traceId
        self.spanId = spanId
        self.parentSpanId = parentSpanId
    }

    /// Create a new root context (no parent)
    public static func newRoot() -> SpanContext {
        SpanContext(
            traceId: UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(),
            spanId: generateSpanId()
        )
    }

    /// Create a child context from this context
    public func newChild() -> SpanContext {
        SpanContext(
            traceId: traceId,
            spanId: Self.generateSpanId(),
            parentSpanId: spanId
        )
    }

    private static func generateSpanId() -> SpanID {
        let bytes = (0..<8).map { _ in UInt8.random(in: 0...255) }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Span Status

/// Status of a span indicating success or failure
public enum SpanStatus: Sendable {
    case unset
    case ok
    case error(String)
}

// MARK: - Span Attribute Value

/// Values that can be attached as span attributes
public enum SpanAttributeValue: Sendable, Equatable {
    case string(String)
    case int(Int)
    case int64(Int64)
    case double(Double)
    case bool(Bool)
    case stringArray([String])
    case intArray([Int])

    public var jsonValue: Any {
        switch self {
        case .string(let v): return v
        case .int(let v): return v
        case .int64(let v): return v
        case .double(let v): return v
        case .bool(let v): return v
        case .stringArray(let v): return v
        case .intArray(let v): return v
        }
    }
}

// MARK: - Span Event

/// An event that occurred during a span's lifetime
public struct SpanEvent: Sendable {
    public let name: String
    public let timestamp: Date
    public let attributes: [String: SpanAttributeValue]

    public init(name: String, timestamp: Date = Date(), attributes: [String: SpanAttributeValue] = [:]) {
        self.name = name
        self.timestamp = timestamp
        self.attributes = attributes
    }
}

// MARK: - Telemetry Category

/// Categories for telemetry spans - allows selective enabling/disabling
public enum TelemetryCategory: String, CaseIterable, Sendable {
    case relayPool = "relay.pool"
    case relayConnection = "relay.connection"
    case relaySelection = "relay.selection"
    case subscription = "subscription"
    case subscriptionGrouping = "subscription.grouping"
    case eventRouting = "event.routing"
    case publishing = "publishing"
    case cache = "cache"
    case signatureVerification = "signature"
    case security = "security"
    case lifecycle = "lifecycle"
    case network = "network"
    case auth = "auth"
}

// MARK: - Telemetry Configuration

/// Configuration for NDK telemetry
public struct NDKTelemetryConfig: Sendable {
    /// Whether telemetry is enabled
    public let enabled: Bool

    /// OTLP HTTP endpoint for exporting spans (e.g., "http://localhost:4318/v1/traces")
    public let endpoint: URL?

    /// Service name reported in traces
    public let serviceName: String

    /// Sample rate (0.0 to 1.0) - 1.0 means capture everything
    public let sampleRate: Double

    /// How often to batch export spans (in seconds)
    public let exportInterval: TimeInterval

    /// Maximum spans to buffer before forcing export
    public let maxBufferSize: Int

    /// Which categories to capture (empty means all)
    public let enabledCategories: Set<TelemetryCategory>

    /// Additional resource attributes to include in all spans
    public let resourceAttributes: [String: String]

    public init(
        enabled: Bool = false,
        endpoint: URL? = nil,
        serviceName: String = "ndk-swift",
        sampleRate: Double = 1.0,
        exportInterval: TimeInterval = 5.0,
        maxBufferSize: Int = 1000,
        enabledCategories: Set<TelemetryCategory> = Set(TelemetryCategory.allCases),
        resourceAttributes: [String: String] = [:]
    ) {
        self.enabled = enabled
        self.endpoint = endpoint
        self.serviceName = serviceName
        self.sampleRate = min(1.0, max(0.0, sampleRate))
        self.exportInterval = exportInterval
        self.maxBufferSize = maxBufferSize
        self.enabledCategories = enabledCategories
        self.resourceAttributes = resourceAttributes
    }

    /// Disabled configuration (default)
    public static let disabled = NDKTelemetryConfig(enabled: false)

    /// Local debugging configuration (logs to console, no export)
    public static func localDebug(categories: Set<TelemetryCategory> = Set(TelemetryCategory.allCases)) -> NDKTelemetryConfig {
        NDKTelemetryConfig(
            enabled: true,
            endpoint: nil,
            serviceName: "ndk-swift-debug",
            sampleRate: 1.0,
            enabledCategories: categories
        )
    }

    /// Production configuration with Jaeger endpoint
    public static func jaeger(
        endpoint: URL,
        serviceName: String,
        sampleRate: Double = 1.0,
        resourceAttributes: [String: String] = [:]
    ) -> NDKTelemetryConfig {
        NDKTelemetryConfig(
            enabled: true,
            endpoint: endpoint,
            serviceName: serviceName,
            sampleRate: sampleRate,
            resourceAttributes: resourceAttributes
        )
    }
}

// MARK: - Recorded Span Data

/// Immutable snapshot of a completed span for export
public struct RecordedSpan: Sendable {
    public let context: SpanContext
    public let name: String
    public let category: TelemetryCategory
    public let startTime: Date
    public let endTime: Date
    public let status: SpanStatus
    public let attributes: [String: SpanAttributeValue]
    public let events: [SpanEvent]

    public var durationNanos: UInt64 {
        UInt64(endTime.timeIntervalSince(startTime) * 1_000_000_000)
    }
}
