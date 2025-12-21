import XCTest
@testable import NDKSwiftCore

final class NDKTelemetryTests: XCTestCase {

    // MARK: - SpanContext Tests

    func testSpanContextNewRoot() {
        let context = SpanContext.newRoot()

        XCTAssertFalse(context.traceId.isEmpty)
        XCTAssertFalse(context.spanId.isEmpty)
        XCTAssertNil(context.parentSpanId)
        XCTAssertEqual(context.traceId.count, 32) // 16 bytes as hex
        XCTAssertEqual(context.spanId.count, 16) // 8 bytes as hex
    }

    func testSpanContextNewChild() {
        let parent = SpanContext.newRoot()
        let child = parent.newChild()

        XCTAssertEqual(child.traceId, parent.traceId) // Same trace
        XCTAssertNotEqual(child.spanId, parent.spanId) // Different span
        XCTAssertEqual(child.parentSpanId, parent.spanId) // Parent is set
    }

    func testSpanContextChain() {
        let root = SpanContext.newRoot()
        let child1 = root.newChild()
        let child2 = child1.newChild()

        XCTAssertEqual(root.traceId, child1.traceId)
        XCTAssertEqual(child1.traceId, child2.traceId)
        XCTAssertNil(root.parentSpanId)
        XCTAssertEqual(child1.parentSpanId, root.spanId)
        XCTAssertEqual(child2.parentSpanId, child1.spanId)
    }

    // MARK: - TelemetryConfig Tests

    func testTelemetryConfigDisabled() {
        let config = NDKTelemetryConfig.disabled

        XCTAssertFalse(config.enabled)
        XCTAssertNil(config.endpoint)
    }

    func testTelemetryConfigLocalDebug() {
        let config = NDKTelemetryConfig.localDebug()

        XCTAssertTrue(config.enabled)
        XCTAssertNil(config.endpoint)
        XCTAssertEqual(config.sampleRate, 1.0)
        XCTAssertEqual(config.enabledCategories.count, TelemetryCategory.allCases.count)
    }

    func testTelemetryConfigJaeger() {
        let endpoint = URL(string: "http://localhost:4318/v1/traces")!
        let config = NDKTelemetryConfig.jaeger(
            endpoint: endpoint,
            serviceName: "test-service",
            sampleRate: 0.5,
            resourceAttributes: ["env": "test"]
        )

        XCTAssertTrue(config.enabled)
        XCTAssertEqual(config.endpoint, endpoint)
        XCTAssertEqual(config.serviceName, "test-service")
        XCTAssertEqual(config.sampleRate, 0.5)
        XCTAssertEqual(config.resourceAttributes["env"], "test")
    }

    func testTelemetryConfigSampleRateClamping() {
        let configHigh = NDKTelemetryConfig(enabled: true, sampleRate: 1.5)
        XCTAssertEqual(configHigh.sampleRate, 1.0)

        let configLow = NDKTelemetryConfig(enabled: true, sampleRate: -0.5)
        XCTAssertEqual(configLow.sampleRate, 0.0)
    }

    // MARK: - NoOpSpan Tests

    func testNoOpSpanDoesNothing() {
        let span = NoOpSpan.instance

        // These should not crash
        span.setAttribute("key", .string("value"))
        span.setAttributes(["a": .int(1), "b": .bool(true)])
        span.addEvent("event", attributes: ["x": .double(1.5)])
        span.setStatus(.ok)
        span.end()

        let child = span.startChild(name: "child", category: .relayPool)
        XCTAssertTrue(child === NoOpSpan.instance)
    }

    // MARK: - NDKTracer Tests

    func testTracerDisabledReturnsNoOpSpan() {
        let tracer = NDKTracer(config: .disabled)

        let span = tracer.startSpan(name: "test", category: .relayPool)
        XCTAssertTrue(span is NoOpSpan)
    }

    func testTracerEnabledReturnsRealSpan() {
        let config = NDKTelemetryConfig(enabled: true, endpoint: nil)
        let tracer = NDKTracer(config: config)

        let span = tracer.startSpan(name: "test", category: .relayPool)
        XCTAssertTrue(span is NDKSpan)

        span.end()
        tracer.shutdown()
    }

    func testTracerCategoryFiltering() {
        let config = NDKTelemetryConfig(
            enabled: true,
            endpoint: nil,
            enabledCategories: [.relayPool, .publishing]
        )
        let tracer = NDKTracer(config: config)

        let enabledSpan = tracer.startSpan(name: "test", category: .relayPool)
        XCTAssertTrue(enabledSpan is NDKSpan)

        let disabledSpan = tracer.startSpan(name: "test", category: .cache)
        XCTAssertTrue(disabledSpan is NoOpSpan)

        enabledSpan.end()
        tracer.shutdown()
    }

    func testTracerParentContextPropagation() {
        let config = NDKTelemetryConfig(enabled: true, endpoint: nil)
        let tracer = NDKTracer(config: config)

        let parentSpan = tracer.startSpan(name: "parent", category: .relayPool)
        let childSpan = tracer.startSpan(name: "child", category: .relayPool, parent: parentSpan.context)

        XCTAssertEqual(parentSpan.context.traceId, childSpan.context.traceId)
        XCTAssertEqual(childSpan.context.parentSpanId, parentSpan.context.spanId)

        childSpan.end()
        parentSpan.end()
        tracer.shutdown()
    }

    // MARK: - NDKSpan Tests

    func testSpanSetAttributes() async {
        let config = NDKTelemetryConfig(enabled: true, endpoint: nil)
        let tracer = NDKTracer(config: config)

        let span = tracer.startSpan(name: "test", category: .relayPool) as! NDKSpan

        span.set("string_key", "value")
        span.set("int_key", 42)
        span.set("bool_key", true)
        span.set("double_key", 3.14)
        span.set("array_key", ["a", "b", "c"])

        span.end()

        // Give time for async recording
        try? await Task.sleep(nanoseconds: 100_000_000)
        tracer.shutdown()
    }

    func testSpanAddEvents() async {
        let config = NDKTelemetryConfig(enabled: true, endpoint: nil)
        let tracer = NDKTracer(config: config)

        let span = tracer.startSpan(name: "test", category: .relayPool) as! NDKSpan

        span.addEvent("event1", attributes: nil)
        span.addEvent("event2", attributes: ["key": .string("value")])

        span.end()

        try? await Task.sleep(nanoseconds: 100_000_000)
        tracer.shutdown()
    }

    func testSpanRecordError() async {
        let config = NDKTelemetryConfig(enabled: true, endpoint: nil)
        let tracer = NDKTracer(config: config)

        let span = tracer.startSpan(name: "test", category: .relayPool) as! NDKSpan

        struct TestError: Error, LocalizedError {
            var errorDescription: String? { "Test error message" }
        }

        span.recordError(TestError())
        span.end()

        try? await Task.sleep(nanoseconds: 100_000_000)
        tracer.shutdown()
    }

    // MARK: - withSpan Tests

    func testWithSpanSync() {
        let config = NDKTelemetryConfig(enabled: true, endpoint: nil)
        let tracer = NDKTracer(config: config)

        let result = tracer.withSpan(name: "sync-op", category: .publishing) { span in
            span.set("step", "processing")
            return 42
        }

        XCTAssertEqual(result, 42)
        tracer.shutdown()
    }

    func testWithSpanAsync() async {
        let config = NDKTelemetryConfig(enabled: true, endpoint: nil)
        let tracer = NDKTracer(config: config)

        let result = await tracer.withSpan(name: "async-op", category: .publishing) { span in
            span.set("step", "processing")
            try? await Task.sleep(nanoseconds: 10_000_000)
            return "done"
        }

        XCTAssertEqual(result, "done")
        tracer.shutdown()
    }

    func testWithSpanPropagatesError() {
        let config = NDKTelemetryConfig(enabled: true, endpoint: nil)
        let tracer = NDKTracer(config: config)

        struct TestError: Error {}

        XCTAssertThrowsError(try tracer.withSpan(name: "error-op", category: .publishing) { _ -> Int in
            throw TestError()
        })

        tracer.shutdown()
    }

    // MARK: - SpanAttributes Tests

    func testSpanAttributeKeys() {
        // Just verify the constants exist and are non-empty
        XCTAssertFalse(SpanAttributes.relayUrl.isEmpty)
        XCTAssertFalse(SpanAttributes.eventId.isEmpty)
        XCTAssertFalse(SpanAttributes.subscriptionId.isEmpty)
        XCTAssertFalse(SpanAttributes.decisionReason.isEmpty)
    }

    // MARK: - TelemetryCategory Tests

    func testAllCategoriesHaveRawValues() {
        for category in TelemetryCategory.allCases {
            XCTAssertFalse(category.rawValue.isEmpty)
        }
    }

    // MARK: - RecordedSpan Tests

    func testRecordedSpanDuration() {
        let context = SpanContext.newRoot()
        let start = Date()
        let end = start.addingTimeInterval(0.5) // 500ms

        let recorded = RecordedSpan(
            context: context,
            name: "test",
            category: .relayPool,
            startTime: start,
            endTime: end,
            status: .ok,
            attributes: [:],
            events: []
        )

        // 500ms = 500,000,000 nanoseconds
        XCTAssertEqual(recorded.durationNanos, 500_000_000, accuracy: 1000)
    }

    // MARK: - Integration Tests

    func testNDKWithTelemetryConfig() async {
        let config = NDKTelemetryConfig.localDebug(categories: [.relayPool])

        let ndk = NDK(
            relayURLs: [],
            telemetryConfig: config
        )

        XCTAssertTrue(ndk.telemetryConfig.enabled)
        XCTAssertEqual(ndk.telemetryConfig.enabledCategories.count, 1)
        XCTAssertTrue(ndk.telemetryConfig.enabledCategories.contains(.relayPool))
    }

    func testSpanCreatedFromNDK() async {
        let ndk = NDK(
            relayURLs: [],
            telemetryConfig: .localDebug()
        )

        let span = ndk.startSpan("test.span", category: .relayPool)
        XCTAssertTrue(span is NDKSpan)

        span.set("test_attr", "value")
        span.end()

        // Flush and shutdown to avoid cleanup issues
        await ndk.tracer.flush()
        ndk.tracer.shutdown()
    }

    func testSpanHierarchyFromNDK() async {
        let ndk = NDK(
            relayURLs: [],
            telemetryConfig: .localDebug()
        )

        let parentSpan = ndk.startSpan("parent", category: .relayPool)
        let childSpan = ndk.startSpan("child", category: .relayPool, parent: parentSpan.context)

        XCTAssertEqual(parentSpan.context.traceId, childSpan.context.traceId)
        XCTAssertEqual(childSpan.context.parentSpanId, parentSpan.context.spanId)

        childSpan.end()
        parentSpan.end()

        // Flush and shutdown to avoid cleanup issues
        await ndk.tracer.flush()
        ndk.tracer.shutdown()
    }
}

// MARK: - Mock Exporter for Testing

actor MockSpanExporterStorage {
    var spans: [RecordedSpan] = []

    func append(_ newSpans: [RecordedSpan]) {
        spans.append(contentsOf: newSpans)
    }

    func getAll() -> [RecordedSpan] {
        return spans
    }

    func clear() {
        spans.removeAll()
    }
}

final class MockSpanExporter: SpanExporter, Sendable {
    private let storage = MockSpanExporterStorage()

    func export(_ spans: [RecordedSpan]) async {
        await storage.append(spans)
    }

    func getSpans() async -> [RecordedSpan] {
        await storage.getAll()
    }

    func clear() async {
        await storage.clear()
    }
}
