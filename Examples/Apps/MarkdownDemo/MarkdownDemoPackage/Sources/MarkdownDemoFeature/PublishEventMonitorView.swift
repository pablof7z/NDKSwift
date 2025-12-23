import SwiftUI
import NDKSwiftCore

/// Example view demonstrating how to observe per-relay publish events
@MainActor
public struct PublishEventMonitorView: View {
    let ndk: NDK

    @State private var publishEvents: [PublishEventEntry] = []
    @State private var isMonitoring = false
    @State private var monitorTask: Task<Void, Never>?
    @State private var testEventId: String = ""
    @State private var isPublishing = false

    struct PublishEventEntry: Identifiable {
        let id = UUID()
        let eventId: String
        let relayUrl: String
        let success: Bool
        let message: String?
        let timestamp: Date

        var displayEventId: String {
            String(eventId.prefix(8))
        }

        var displayRelayUrl: String {
            relayUrl.replacingOccurrences(of: "wss://", with: "")
                   .replacingOccurrences(of: "ws://", with: "")
        }
    }

    public init(ndk: NDK) {
        self.ndk = ndk
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header with status
            HStack {
                Circle()
                    .fill(isMonitoring ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                Text(isMonitoring ? "Monitoring" : "Not Monitoring")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(publishEvents.count) events")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.05))

            // Test publish section
            VStack(spacing: 12) {
                Text("Test Event Publishing")
                    .font(.headline)

                Button(action: testPublish) {
                    HStack {
                        if isPublishing {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "paperplane.fill")
                        }
                        Text(isPublishing ? "Publishing..." : "Publish Test Event")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isPublishing || !isMonitoring)

                if !testEventId.isEmpty {
                    Text("Last event: \(String(testEventId.prefix(8)))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.08))

            // Events list
            if publishEvents.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No publish events yet")
                        .foregroundColor(.secondary)
                    if !isMonitoring {
                        Text("Start monitoring to see events")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(publishEvents.reversed()) { entry in
                        PublishEventRow(entry: entry)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Publish Events")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: toggleMonitoring) {
                    Image(systemName: isMonitoring ? "stop.circle.fill" : "play.circle.fill")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button("Clear") {
                    publishEvents.removeAll()
                }
                .disabled(publishEvents.isEmpty)
            }
        }
        .onDisappear {
            stopMonitoring()
        }
    }

    private func toggleMonitoring() {
        if isMonitoring {
            stopMonitoring()
        } else {
            startMonitoring()
        }
    }

    private func startMonitoring() {
        isMonitoring = true

        monitorTask = Task {
            for await publishEvent in await ndk.pool.publishEvents {
                guard !Task.isCancelled else { break }

                let entry = PublishEventEntry(
                    eventId: publishEvent.eventId,
                    relayUrl: publishEvent.relayUrl,
                    success: publishEvent.success,
                    message: publishEvent.message,
                    timestamp: publishEvent.timestamp
                )

                publishEvents.append(entry)

                // Keep only the last 100 events
                if publishEvents.count > 100 {
                    publishEvents.removeFirst()
                }
            }
        }
    }

    private func stopMonitoring() {
        isMonitoring = false
        monitorTask?.cancel()
        monitorTask = nil
    }

    private func testPublish() {
        isPublishing = true

        Task {
            defer { isPublishing = false }

            do {
                let event = NDKEvent(
                    content: "Test event from PublishEventMonitorView at \(Date())",
                    kind: 1
                )

                try await event.sign(with: ndk.requireSigner())
                testEventId = event.id

                let relays = try await ndk.eventManager.publish(event)
                print("Published test event to \(relays.count) relays")
            } catch {
                print("Failed to publish test event: \(error)")
            }
        }
    }
}

struct PublishEventRow: View {
    let entry: PublishEventMonitorView.PublishEventEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header: status and event ID
            HStack {
                Image(systemName: entry.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(entry.success ? .green : .red)
                    .font(.caption)

                Text("Event \(entry.displayEventId)")
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.medium)

                Spacer()

                Text(entry.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Relay URL
            HStack(spacing: 4) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Text(entry.displayRelayUrl)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Error message if present
            if !entry.success, let message = entry.message {
                Text(message)
                    .font(.caption2)
                    .foregroundColor(.red)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        PublishEventMonitorView(ndk: NDK(relays: [RelayConstants.damus]))
    }
}
