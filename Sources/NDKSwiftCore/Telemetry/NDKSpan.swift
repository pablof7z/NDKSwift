import Foundation

// MARK: - Span Protocol

/// A span represents a single operation within a trace
public protocol Span: AnyObject, Sendable {
    /// The span's context containing trace and span IDs
    var context: SpanContext { get }

    /// The span's name
    var name: String { get }

    /// The category this span belongs to
    var category: TelemetryCategory { get }

    /// Set an attribute on the span
    func setAttribute(_ key: String, _ value: SpanAttributeValue)

    /// Set multiple attributes at once
    func setAttributes(_ attributes: [String: SpanAttributeValue])

    /// Add an event to the span
    func addEvent(_ name: String, attributes: [String: SpanAttributeValue]?)

    /// Set the span's status
    func setStatus(_ status: SpanStatus)

    /// End the span (records end time and exports)
    func end()

    /// Create a child span
    func startChild(name: String, category: TelemetryCategory) -> Span
}

// MARK: - Span Implementation

/// Thread-safe span implementation
public final class NDKSpan: Span, @unchecked Sendable {
    public let context: SpanContext
    public let name: String
    public let category: TelemetryCategory

    private let lock = NSLock()
    private let startTime: Date
    private var endTime: Date?
    private var _status: SpanStatus = .unset
    private var _attributes: [String: SpanAttributeValue] = [:]
    private var _events: [SpanEvent] = []
    private var hasEnded = false

    private weak var tracer: NDKTracer?

    init(
        name: String,
        category: TelemetryCategory,
        context: SpanContext,
        tracer: NDKTracer?
    ) {
        self.name = name
        self.category = category
        self.context = context
        self.startTime = Date()
        self.tracer = tracer
    }

    public func setAttribute(_ key: String, _ value: SpanAttributeValue) {
        lock.lock()
        defer { lock.unlock() }
        guard !hasEnded else { return }
        _attributes[key] = value
    }

    public func setAttributes(_ attributes: [String: SpanAttributeValue]) {
        lock.lock()
        defer { lock.unlock() }
        guard !hasEnded else { return }
        for (key, value) in attributes {
            _attributes[key] = value
        }
    }

    public func addEvent(_ name: String, attributes: [String: SpanAttributeValue]? = nil) {
        lock.lock()
        defer { lock.unlock() }
        guard !hasEnded else { return }
        _events.append(SpanEvent(name: name, attributes: attributes ?? [:]))
    }

    public func setStatus(_ status: SpanStatus) {
        lock.lock()
        defer { lock.unlock() }
        guard !hasEnded else { return }
        _status = status
    }

    public func end() {
        let recorded: RecordedSpan?

        lock.lock()
        if hasEnded {
            lock.unlock()
            return
        }
        hasEnded = true
        endTime = Date()

        recorded = RecordedSpan(
            context: context,
            name: name,
            category: category,
            startTime: startTime,
            endTime: endTime!,
            status: _status,
            attributes: _attributes,
            events: _events
        )
        lock.unlock()

        // Export the span
        if let recorded = recorded {
            tracer?.recordSpan(recorded)
        }
    }

    public func startChild(name: String, category: TelemetryCategory) -> Span {
        tracer?.startSpan(name: name, category: category, parent: context) ?? NoOpSpan.instance
    }
}

// MARK: - No-Op Span

/// A span that does nothing - used when telemetry is disabled
public final class NoOpSpan: Span, @unchecked Sendable {
    public static let instance = NoOpSpan()

    public let context = SpanContext(traceId: "0", spanId: "0")
    public let name = ""
    public let category = TelemetryCategory.relayPool

    private init() {}

    public func setAttribute(_: String, _: SpanAttributeValue) {}
    public func setAttributes(_: [String: SpanAttributeValue]) {}
    public func addEvent(_: String, attributes _: [String: SpanAttributeValue]?) {}
    public func setStatus(_: SpanStatus) {}
    public func end() {}
    public func startChild(name _: String, category _: TelemetryCategory) -> Span { self }
}

// MARK: - Span Convenience Extensions

public extension Span {
    /// Set a string attribute
    func set(_ key: String, _ value: String) {
        setAttribute(key, .string(value))
    }

    /// Set an integer attribute
    func set(_ key: String, _ value: Int) {
        setAttribute(key, .int(value))
    }

    /// Set a boolean attribute
    func set(_ key: String, _ value: Bool) {
        setAttribute(key, .bool(value))
    }

    /// Set a double attribute
    func set(_ key: String, _ value: Double) {
        setAttribute(key, .double(value))
    }

    /// Set a string array attribute
    func set(_ key: String, _ value: [String]) {
        setAttribute(key, .stringArray(value))
    }

    /// Record an error on the span
    func recordError(_ error: Error) {
        addEvent("exception", attributes: [
            "exception.type": .string(String(describing: type(of: error))),
            "exception.message": .string(error.localizedDescription)
        ])
        setStatus(.error(error.localizedDescription))
    }

    /// Mark span as successful
    func success() {
        setStatus(.ok)
    }
}
