import SwiftUI
import NDKSwiftCore

/// Displays a live feed of relay intelligence activity
/// Polls HintIndex for changes and displays them as they occur
public struct LiveIntelligenceFeedView: View {
    let ndk: NDK

    @State private var events: [IntelligenceEventItem] = []
    @State private var isPaused = false
    @State private var filterType: EventFilterType = .all
    @State private var lastStats: HintIndexStatistics?
    @State private var pollTask: Task<Void, Never>?

    private let maxEvents = 500

    enum EventFilterType: String, CaseIterable {
        case all = "All"
        case hints = "Hints"
        case relays = "Relays"
    }

    public init(ndk: NDK) {
        self.ndk = ndk
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Controls bar
            HStack {
                // Filter picker
                Picker("Filter", selection: $filterType) {
                    ForEach(EventFilterType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)

                Spacer()

                // Event count
                Text("\(filteredEvents.count) events")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Pause/Resume button
                Button(action: { isPaused.toggle() }) {
                    Image(systemName: isPaused ? "play.fill" : "pause.fill")
                }
                .buttonStyle(.bordered)

                // Clear button
                Button(action: { events.removeAll() }) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.05))

            // Event list
            if filteredEvents.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("Waiting for activity...")
                        .foregroundColor(.secondary)
                    Text("Browse content to see hints being learned")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    List {
                        ForEach(filteredEvents) { event in
                            EventRow(event: event)
                                .id(event.id)
                                .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                        }
                    }
                    .listStyle(.plain)
                    .onChange(of: filteredEvents.count) { _, _ in
                        if let lastEvent = filteredEvents.last {
                            withAnimation {
                                proxy.scrollTo(lastEvent.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
        .task {
            await startPolling()
        }
        .onDisappear {
            pollTask?.cancel()
        }
    }

    private var filteredEvents: [IntelligenceEventItem] {
        switch filterType {
        case .all:
            return events
        case .hints:
            return events.filter { $0.type.isHintEvent }
        case .relays:
            return events.filter { $0.type.isRelayEvent }
        }
    }

    private func startPolling() async {
        pollTask?.cancel()
        pollTask = Task {
            // Get initial stats
            lastStats = await ndk.hintIndex.statistics

            // Add initial status event
            await addEvent(.init(
                type: .status,
                message: "Started monitoring relay intelligence",
                detail: nil,
                timestamp: Date()
            ))

            // Poll every 500ms for changes
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))

                guard !isPaused else { continue }

                let currentStats = await ndk.hintIndex.statistics

                // Check for changes
                if let last = lastStats {
                    // New pubkey hints
                    if currentStats.pubkeyCount > last.pubkeyCount {
                        let diff = currentStats.pubkeyCount - last.pubkeyCount
                        await addEvent(.init(
                            type: .hintPubkey,
                            message: "Learned \(diff) new pubkey hint\(diff > 1 ? "s" : "")",
                            detail: "Total: \(currentStats.pubkeyCount) pubkeys",
                            timestamp: Date()
                        ))
                    }

                    // New event ID hints
                    if currentStats.eventIdCount > last.eventIdCount {
                        let diff = currentStats.eventIdCount - last.eventIdCount
                        await addEvent(.init(
                            type: .hintEvent,
                            message: "Learned \(diff) new event hint\(diff > 1 ? "s" : "")",
                            detail: "Total: \(currentStats.eventIdCount) events",
                            timestamp: Date()
                        ))
                    }

                    // New addresses
                    if currentStats.addressCount > last.addressCount {
                        let diff = currentStats.addressCount - last.addressCount
                        await addEvent(.init(
                            type: .hintAddress,
                            message: "Learned \(diff) new address hint\(diff > 1 ? "s" : "")",
                            detail: "Total: \(currentStats.addressCount) addresses",
                            timestamp: Date()
                        ))
                    }

                    // New relays discovered
                    if currentStats.uniqueRelayCount > last.uniqueRelayCount {
                        let diff = currentStats.uniqueRelayCount - last.uniqueRelayCount
                        await addEvent(.init(
                            type: .relayDiscovered,
                            message: "Discovered \(diff) new relay\(diff > 1 ? "s" : "")",
                            detail: "Total: \(currentStats.uniqueRelayCount) known relays",
                            timestamp: Date()
                        ))
                    }

                    // Total entries changed significantly
                    if currentStats.totalEntries > last.totalEntries + 5 {
                        let diff = currentStats.totalEntries - last.totalEntries
                        await addEvent(.init(
                            type: .hintBatch,
                            message: "Batch: +\(diff) hints recorded",
                            detail: "Total: \(currentStats.totalEntries) entries",
                            timestamp: Date()
                        ))
                    }
                }

                lastStats = currentStats
            }
        }
    }

    @MainActor
    private func addEvent(_ event: IntelligenceEventItem) {
        events.append(event)
        // Trim to max events (ring buffer)
        if events.count > maxEvents {
            events.removeFirst(events.count - maxEvents)
        }
    }
}

// MARK: - Event Item

struct IntelligenceEventItem: Identifiable {
    let id = UUID()
    let type: EventType
    let message: String
    let detail: String?
    let timestamp: Date

    enum EventType {
        case status
        case hintPubkey
        case hintEvent
        case hintAddress
        case hintBatch
        case relayDiscovered
        case relayConnected
        case relayDisconnected
        case relaySelected

        var icon: String {
            switch self {
            case .status: return "info.circle"
            case .hintPubkey: return "person.fill"
            case .hintEvent: return "doc.text.fill"
            case .hintAddress: return "link"
            case .hintBatch: return "square.stack.3d.up.fill"
            case .relayDiscovered: return "antenna.radiowaves.left.and.right"
            case .relayConnected: return "checkmark.circle.fill"
            case .relayDisconnected: return "xmark.circle.fill"
            case .relaySelected: return "arrow.triangle.branch"
            }
        }

        var color: Color {
            switch self {
            case .status: return .gray
            case .hintPubkey: return .blue
            case .hintEvent: return .purple
            case .hintAddress: return .orange
            case .hintBatch: return .green
            case .relayDiscovered: return .teal
            case .relayConnected: return .green
            case .relayDisconnected: return .red
            case .relaySelected: return .indigo
            }
        }

        var isHintEvent: Bool {
            switch self {
            case .hintPubkey, .hintEvent, .hintAddress, .hintBatch:
                return true
            default:
                return false
            }
        }

        var isRelayEvent: Bool {
            switch self {
            case .relayDiscovered, .relayConnected, .relayDisconnected, .relaySelected:
                return true
            default:
                return false
            }
        }
    }
}

// MARK: - Event Row

struct EventRow: View {
    let event: IntelligenceEventItem

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Icon
            Image(systemName: event.type.icon)
                .foregroundColor(event.type.color)
                .font(.caption)
                .frame(width: 16)

            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(event.message)
                    .font(.caption)
                    .fontWeight(.medium)

                if let detail = event.detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Timestamp
            Text(timeFormatter.string(from: event.timestamp))
                .font(.caption2.monospacedDigit())
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#if DEBUG
struct LiveIntelligenceFeedView_Previews: PreviewProvider {
    static var previews: some View {
        LiveIntelligenceFeedView(ndk: NDK())
    }
}
#endif
