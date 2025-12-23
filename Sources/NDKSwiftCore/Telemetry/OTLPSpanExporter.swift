import Foundation

/// OTLP HTTP exporter for sending spans to Jaeger/OTLP collectors
final class OTLPSpanExporter: SpanExporter, @unchecked Sendable {
    private let endpoint: URL
    private let serviceName: String
    private let resourceAttributes: [String: String]
    private let session: URLSession

    init(
        endpoint: URL,
        serviceName: String,
        resourceAttributes: [String: String]
    ) {
        self.endpoint = endpoint
        self.serviceName = serviceName
        self.resourceAttributes = resourceAttributes

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }

    func export(_ spans: [RecordedSpan]) async {
        guard !spans.isEmpty else { return }

        let payload = buildOTLPPayload(spans)

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: payload, options: [])

            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = jsonData

            let (data, response) = try await session.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode >= 400 {
                    let responseBody = String(data: data, encoding: .utf8) ?? "no body"
                    NDKLogger.log(.warning, category: .performance,
                        "Telemetry export failed with status \(httpResponse.statusCode): \(responseBody)")
                }
            }
        } catch {
            NDKLogger.log(.warning, category: .performance,
                "Telemetry export error: \(error.localizedDescription)")
        }
    }

    // MARK: - OTLP Payload Building

    private func buildOTLPPayload(_ spans: [RecordedSpan]) -> [String: Any] {
        // Group spans by trace ID for efficient resource sharing
        let spansByTrace = Dictionary(grouping: spans) { $0.context.traceId }

        var scopeSpans: [[String: Any]] = []

        for (_, traceSpans) in spansByTrace {
            let otlpSpans = traceSpans.map { buildOTLPSpan($0) }
            scopeSpans.append([
                "scope": [
                    "name": "ndk-swift",
                    "version": "1.0.0"
                ],
                "spans": otlpSpans
            ])
        }

        return [
            "resourceSpans": [
                [
                    "resource": buildResource(),
                    "scopeSpans": scopeSpans
                ]
            ]
        ]
    }

    private func buildResource() -> [String: Any] {
        var attributes: [[String: Any]] = [
            ["key": "service.name", "value": ["stringValue": serviceName]],
            ["key": "telemetry.sdk.name", "value": ["stringValue": "ndk-swift"]],
            ["key": "telemetry.sdk.language", "value": ["stringValue": "swift"]]
        ]

        for (key, value) in resourceAttributes {
            attributes.append([
                "key": key,
                "value": ["stringValue": value]
            ])
        }

        return ["attributes": attributes]
    }

    private func buildOTLPSpan(_ span: RecordedSpan) -> [String: Any] {
        var otlpSpan: [String: Any] = [
            "traceId": padTraceId(span.context.traceId),
            "spanId": padSpanId(span.context.spanId),
            "name": span.name,
            "kind": 1, // SPAN_KIND_INTERNAL
            "startTimeUnixNano": nanosFromDate(span.startTime),
            "endTimeUnixNano": nanosFromDate(span.endTime),
            "attributes": buildAttributes(span.attributes, category: span.category),
            "events": buildEvents(span.events),
            "status": buildStatus(span.status)
        ]

        if let parentId = span.context.parentSpanId {
            otlpSpan["parentSpanId"] = padSpanId(parentId)
        }

        return otlpSpan
    }

    private func buildAttributes(_ attributes: [String: SpanAttributeValue], category: TelemetryCategory) -> [[String: Any]] {
        var result: [[String: Any]] = [
            ["key": "ndk.category", "value": ["stringValue": category.rawValue]]
        ]

        for (key, value) in attributes {
            result.append([
                "key": key,
                "value": buildAttributeValue(value)
            ])
        }

        return result
    }

    private func buildAttributeValue(_ value: SpanAttributeValue) -> [String: Any] {
        switch value {
        case .string(let v):
            return ["stringValue": v]
        case .int(let v):
            return ["intValue": String(v)]
        case .int64(let v):
            return ["intValue": String(v)]
        case .double(let v):
            return ["doubleValue": v]
        case .bool(let v):
            return ["boolValue": v]
        case .stringArray(let v):
            return ["arrayValue": ["values": v.map { ["stringValue": $0] }]]
        case .intArray(let v):
            return ["arrayValue": ["values": v.map { ["intValue": String($0)] }]]
        }
    }

    private func buildEvents(_ events: [SpanEvent]) -> [[String: Any]] {
        events.map { event in
            var result: [String: Any] = [
                "timeUnixNano": nanosFromDate(event.timestamp),
                "name": event.name
            ]

            if !event.attributes.isEmpty {
                result["attributes"] = event.attributes.map { key, value in
                    ["key": key, "value": buildAttributeValue(value)]
                }
            }

            return result
        }
    }

    private func buildStatus(_ status: SpanStatus) -> [String: Any] {
        switch status {
        case .unset:
            return ["code": 0] // STATUS_CODE_UNSET
        case .ok:
            return ["code": 1] // STATUS_CODE_OK
        case .error(let message):
            return ["code": 2, "message": message] // STATUS_CODE_ERROR
        }
    }

    // MARK: - Helpers

    private func nanosFromDate(_ date: Date) -> String {
        let nanos = Int64(date.timeIntervalSince1970 * 1_000_000_000)
        return String(nanos)
    }

    /// Pad trace ID to 32 hex chars (16 bytes)
    private func padTraceId(_ hex: String) -> String {
        if hex.count < 32 {
            return String(repeating: "0", count: 32 - hex.count) + hex
        }
        return hex
    }

    /// Pad span ID to 16 hex chars (8 bytes)
    private func padSpanId(_ hex: String) -> String {
        if hex.count < 16 {
            return String(repeating: "0", count: 16 - hex.count) + hex
        }
        return hex
    }
}
