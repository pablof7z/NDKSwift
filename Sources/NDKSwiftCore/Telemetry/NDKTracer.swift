import Foundation
import os

// MARK: - Span Buffer Actor

/// Actor that manages the span buffer for thread-safe access
private actor SpanBuffer {
    private var spans: [RecordedSpan] = []
    private let maxSize: Int

    init(maxSize: Int) {
        self.maxSize = maxSize
    }

    func append(_ span: RecordedSpan) -> [RecordedSpan]? {
        spans.append(span)

        // Return spans to export if buffer is full
        if spans.count >= maxSize {
            let toExport = spans
            spans.removeAll()
            return toExport
        }
        return nil
    }

    func drain() -> [RecordedSpan] {
        let toExport = spans
        spans.removeAll()
        return toExport
    }

    var count: Int { spans.count }
}

// MARK: - Tracer

/// The main tracer for creating and managing spans
public final class NDKTracer: @unchecked Sendable {
    private let config: NDKTelemetryConfig
    private let exporter: SpanExporter?
    private let spanBuffer: SpanBuffer

    private let stateLock = OSAllocatedUnfairLock()
    private var exportTask: Task<Void, Never>?
    private var isShutdown = false

    /// Current active span context (task-local storage for automatic propagation)
    @TaskLocal public static var currentContext: SpanContext?

    /// Session span that's active for the lifetime of the tracer
    private var sessionSpan: NDKSpan?
    private var sessionContext: SpanContext?

    public init(config: NDKTelemetryConfig) {
        self.config = config
        self.spanBuffer = SpanBuffer(maxSize: config.maxBufferSize)

        if config.enabled, let endpoint = config.endpoint {
            self.exporter = OTLPSpanExporter(
                endpoint: endpoint,
                serviceName: config.serviceName,
                resourceAttributes: config.resourceAttributes
            )
        } else if config.enabled {
            // Console exporter for local debugging
            self.exporter = ConsoleSpanExporter()
        } else {
            self.exporter = nil
        }

        if config.enabled {
            startExportLoop()
            startSessionSpan()
        }
    }

    deinit {
        shutdown()
    }

    // MARK: - Session Management

    private func startSessionSpan() {
        let context = SpanContext.newRoot()
        let span = NDKSpan(
            name: "ndk.session",
            category: .lifecycle,
            context: context,
            tracer: self
        )
        span.set("service.name", config.serviceName)
        span.set("telemetry.sdk.name", "ndk-swift")
        span.set("telemetry.sdk.language", "swift")

        // Add resource attributes
        for (key, value) in config.resourceAttributes {
            span.set(key, value)
        }

        stateLock.withLock {
            sessionContext = context
            sessionSpan = span
        }
    }

    /// Get the current session's trace ID
    public var sessionTraceId: TraceID? {
        stateLock.withLock { sessionContext?.traceId }
    }

    // MARK: - Span Creation

    /// Start a new span
    public func startSpan(
        name: String,
        category: TelemetryCategory,
        parent: SpanContext? = nil
    ) -> Span {
        guard config.enabled else { return NoOpSpan.instance }
        guard config.enabledCategories.isEmpty || config.enabledCategories.contains(category) else {
            return NoOpSpan.instance
        }

        // Apply sampling
        if config.sampleRate < 1.0 && Double.random(in: 0..<1) > config.sampleRate {
            return NoOpSpan.instance
        }

        let (shutdown, storedContext) = stateLock.withLock { (isShutdown, sessionContext) }
        if shutdown {
            return NoOpSpan.instance
        }

        let context: SpanContext
        if let parent = parent {
            context = parent.newChild()
        } else if let taskLocalContext = Self.currentContext {
            // Use TaskLocal context if available
            context = taskLocalContext.newChild()
        } else if let sessionContext = storedContext {
            context = sessionContext.newChild()
        } else {
            context = SpanContext.newRoot()
        }

        return NDKSpan(
            name: name,
            category: category,
            context: context,
            tracer: self
        )
    }

    /// Start a span that's a child of the current TaskLocal context
    public func startSpanInContext(name: String, category: TelemetryCategory) -> Span {
        startSpan(name: name, category: category, parent: Self.currentContext)
    }

    /// Execute a block with a span, automatically ending it and propagating context
    public func withSpan<T>(
        name: String,
        category: TelemetryCategory,
        parent: SpanContext? = nil,
        _ operation: (Span) throws -> T
    ) rethrows -> T {
        let span = startSpan(name: name, category: category, parent: parent)
        return try Self.$currentContext.withValue(span.context) {
            do {
                let result = try operation(span)
                span.success()
                span.end()
                return result
            } catch {
                span.recordError(error)
                span.end()
                throw error
            }
        }
    }

    /// Execute an async block with a span, propagating context through async boundaries
    public func withSpan<T>(
        name: String,
        category: TelemetryCategory,
        parent: SpanContext? = nil,
        _ operation: (Span) async throws -> T
    ) async rethrows -> T {
        let span = startSpan(name: name, category: category, parent: parent)
        do {
            // Propagate context through async boundary
            let result = try await Self.$currentContext.withValue(span.context) {
                try await operation(span)
            }
            span.success()
            span.end()
            return result
        } catch {
            span.recordError(error)
            span.end()
            throw error
        }
    }

    // MARK: - Span Recording

    func recordSpan(_ span: RecordedSpan) {
        let shouldRecord = stateLock.withLock { !isShutdown }
        guard shouldRecord else { return }

        let buffer = spanBuffer
        let spanExporter = exporter
        Task {
            if let spansToExport = await buffer.append(span) {
                await spanExporter?.export(spansToExport)
            }
        }
    }

    // MARK: - Export Loop

    private func startExportLoop() {
        let task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64((self?.config.exportInterval ?? 5.0) * 1_000_000_000))

                guard let self = self else { break }
                let shutdown = self.stateLock.withLock { self.isShutdown }
                guard !shutdown else { break }

                let spansToExport = await self.spanBuffer.drain()
                if !spansToExport.isEmpty {
                    await self.exporter?.export(spansToExport)
                }
            }
        }
        stateLock.withLock { exportTask = task }
    }

    // MARK: - Shutdown

    /// Flush remaining spans and shutdown the tracer
    public func shutdown() {
        let (sessionSpanToEnd, taskToCancel, shouldShutdown): (NDKSpan?, Task<Void, Never>?, Bool) = stateLock.withLock {
            if isShutdown {
                return (nil, nil, false)
            }
            isShutdown = true
            let span = sessionSpan
            let task = exportTask
            sessionSpan = nil
            sessionContext = nil
            exportTask = nil
            return (span, task, true)
        }
        guard shouldShutdown else { return }

        // End session span
        sessionSpanToEnd?.end()
        taskToCancel?.cancel()

        // Final flush - only if we have an exporter
        guard let exporter = exporter else { return }
        let buffer = spanBuffer
        Task {
            let spansToExport = await buffer.drain()
            if !spansToExport.isEmpty {
                await exporter.export(spansToExport)
            }
        }
    }

    /// Force flush all buffered spans
    public func flush() async {
        let spansToExport = await spanBuffer.drain()
        if !spansToExport.isEmpty {
            await exporter?.export(spansToExport)
        }
    }
}

// MARK: - Span Exporter Protocol

protocol SpanExporter: Sendable {
    func export(_ spans: [RecordedSpan]) async
}

// MARK: - Console Exporter (for debugging)

final class ConsoleSpanExporter: SpanExporter, Sendable {
    // Use a nonisolated static formatter to avoid retain issues
    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    func export(_ spans: [RecordedSpan]) async {
        for span in spans {
            let durationMs = Double(span.durationNanos) / 1_000_000
            let parentInfo = span.context.parentSpanId.map { " parent=\($0.prefix(8))" } ?? ""
            let timestamp = Self.dateFormatter.string(from: span.startTime)

            var lines: [String] = []

            // Header line
            var header = "📊 [\(timestamp)] [\(span.category.rawValue)] \(span.name)"
            header += " trace=\(span.context.traceId.prefix(8))"
            header += " span=\(span.context.spanId.prefix(8))"
            header += parentInfo
            header += " duration=\(String(format: "%.2f", durationMs))ms"

            // Status indicator
            switch span.status {
            case .ok:
                header += " ✅"
            case .error(let msg):
                header += " ❌ \(msg)"
            case .unset:
                break
            }
            lines.append(header)

            // All attributes (no truncation)
            if !span.attributes.isEmpty {
                lines.append("   Attributes:")
                for (key, value) in span.attributes.sorted(by: { $0.key < $1.key }) {
                    lines.append("     \(key): \(formatValue(value))")
                }
            }

            // All events
            if !span.events.isEmpty {
                lines.append("   Events:")
                for event in span.events {
                    let eventTime = Self.dateFormatter.string(from: event.timestamp)
                    var eventLine = "     [\(eventTime)] \(event.name)"
                    if !event.attributes.isEmpty {
                        let attrs = event.attributes.map { "\($0.key)=\(formatValue($0.value))" }.joined(separator: ", ")
                        eventLine += " {\(attrs)}"
                    }
                    lines.append(eventLine)
                }
            }

            print(lines.joined(separator: "\n"))
        }
    }

    private func formatValue(_ value: SpanAttributeValue) -> String {
        switch value {
        case .string(let v): return "\"\(v)\""
        case .int(let v): return String(v)
        case .int64(let v): return String(v)
        case .double(let v): return String(format: "%.3f", v)
        case .bool(let v): return v ? "true" : "false"
        case .stringArray(let v): return "[\(v.map { "\"\($0)\"" }.joined(separator: ", "))]"
        case .intArray(let v): return "[\(v.map { String($0) }.joined(separator: ", "))]"
        }
    }
}
