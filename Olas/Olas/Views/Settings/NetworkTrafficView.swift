import SwiftUI
import NDKSwift

struct NetworkTrafficView: View {
    @State private var messages: [NDKNetworkMessage] = []
    @State private var selectedRelay: String?
    @State private var selectedDirection: NDKNetworkMessage.Direction?
    @State private var selectedMessageType: String?
    @State private var isLive = true
    @State private var isLoading = true
    @State private var selectedMessage: NDKNetworkMessage?

    private let messageTypes = ["REQ", "EVENT", "EOSE", "OK", "NOTICE", "AUTH", "CLOSE", "COUNT"]

    var body: some View {
        VStack(spacing: 0) {
            // Logging toggle
            HStack {
                Text("Network Logging")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { NDKLogger.logNetworkTraffic },
                    set: { NDKLogger.logNetworkTraffic = $0 }
                ))
                .labelsHidden()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(.systemGroupedBackground))

            // Filters
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Direction filter
                    Menu {
                        Button("All Directions") { selectedDirection = nil }
                        Divider()
                        Button {
                            selectedDirection = .inbound
                        } label: {
                            Label("Inbound", systemImage: "arrow.down")
                        }
                        Button {
                            selectedDirection = .outbound
                        } label: {
                            Label("Outbound", systemImage: "arrow.up")
                        }
                    } label: {
                        TrafficFilterChip(
                            label: selectedDirection?.rawValue ?? "Direction",
                            isActive: selectedDirection != nil,
                            color: selectedDirection == .inbound ? .green : (selectedDirection == .outbound ? .blue : .secondary)
                        )
                    }

                    // Message type filter
                    Menu {
                        Button("All Types") { selectedMessageType = nil }
                        Divider()
                        ForEach(messageTypes, id: \.self) { type in
                            Button(type) {
                                selectedMessageType = type
                            }
                        }
                    } label: {
                        TrafficFilterChip(
                            label: selectedMessageType ?? "Type",
                            isActive: selectedMessageType != nil,
                            color: .purple
                        )
                    }

                    // Live toggle
                    Button {
                        isLive.toggle()
                    } label: {
                        TrafficFilterChip(
                            label: isLive ? "Live" : "Paused",
                            isActive: isLive,
                            color: isLive ? .green : .orange
                        )
                    }

                    Spacer()

                    // Clear button
                    Button {
                        Task {
                            await NDKLogBuffer.shared.clearNetworkMessages()
                            await loadMessages()
                        }
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 8)

            Divider()

            // Messages
            if !NDKLogger.logNetworkTraffic {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Network logging is disabled")
                        .foregroundStyle(.secondary)
                    Text("Enable it above to capture traffic")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            } else if isLoading {
                Spacer()
                ProgressView("Loading...")
                Spacer()
            } else if filteredMessages.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No network messages")
                        .foregroundStyle(.secondary)
                    Text("Messages will appear here as they're sent/received")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            } else {
                List {
                    ForEach(filteredMessages) { message in
                        NetworkMessageRow(message: message)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedMessage = message
                            }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Network Traffic")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await loadMessages()
            isLoading = false
        }
        .task(id: isLive) {
            guard isLive else { return }
            // Poll for updates when live mode is enabled
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                await loadMessages()
            }
        }
        .refreshable {
            await loadMessages()
        }
        .sheet(item: $selectedMessage) { message in
            NavigationStack {
                NetworkMessageDetailView(message: message)
            }
        }
    }

    private var filteredMessages: [NDKNetworkMessage] {
        var result = messages

        if let direction = selectedDirection {
            result = result.filter { $0.direction == direction }
        }

        if let type = selectedMessageType {
            result = result.filter { $0.messageType == type }
        }

        if let relay = selectedRelay {
            result = result.filter { $0.relay == relay }
        }

        return result
    }

    private func loadMessages() async {
        messages = await NDKLogBuffer.shared.getNetworkMessages()
    }
}

// MARK: - Supporting Views

private struct TrafficFilterChip: View {
    let label: String
    let isActive: Bool
    let color: Color

    var body: some View {
        Text(label)
            .font(.caption)
            .fontWeight(isActive ? .semibold : .regular)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isActive ? color.opacity(0.2) : Color(.tertiarySystemGroupedBackground))
            .foregroundStyle(isActive ? color : .primary)
            .cornerRadius(16)
    }
}

private struct NetworkMessageRow: View {
    let message: NDKNetworkMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                // Direction indicator
                Image(systemName: message.direction == .inbound ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                    .foregroundStyle(message.direction == .inbound ? .green : .blue)
                    .font(.caption)

                // Message type badge
                Text(message.messageType)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(typeColor.opacity(0.2))
                    .foregroundStyle(typeColor)
                    .cornerRadius(4)

                // Timestamp
                Text(formatTimestamp(message.timestamp))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)

                Spacer()
            }

            // Relay
            Text(message.relay)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)

            // Message preview
            Text(message.raw.prefix(100) + (message.raw.count > 100 ? "..." : ""))
                .font(.system(.caption, design: .monospaced))
                .lineLimit(2)
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 4)
    }

    private var typeColor: Color {
        switch message.messageType {
        case "EVENT": return .blue
        case "REQ": return .purple
        case "EOSE": return .green
        case "OK": return .teal
        case "NOTICE": return .orange
        case "AUTH": return .red
        case "CLOSE": return .gray
        case "COUNT": return .yellow
        default: return .secondary
        }
    }

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }
}

private struct NetworkMessageDetailView: View {
    let message: NDKNetworkMessage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section("Message Info") {
                LabeledContent("Direction") {
                    HStack(spacing: 4) {
                        Image(systemName: message.direction == .inbound ? "arrow.down" : "arrow.up")
                        Text(message.direction == .inbound ? "Inbound" : "Outbound")
                    }
                    .foregroundStyle(message.direction == .inbound ? .green : .blue)
                }

                LabeledContent("Type") {
                    Text(message.messageType)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.semibold)
                }

                LabeledContent("Relay") {
                    Text(message.relay)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }

                LabeledContent("Timestamp") {
                    Text(formatFullTimestamp(message.timestamp))
                        .font(.caption)
                }
            }

            Section("Raw Message") {
                Text(message.raw)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }

            if let prettyJSON = prettyPrintJSON(message.raw) {
                Section("Formatted JSON") {
                    Text(prettyJSON)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }

            Section {
                Button {
                    UIPasteboard.general.string = message.raw
                } label: {
                    Label("Copy Raw Message", systemImage: "doc.on.doc")
                }

                if let prettyJSON = prettyPrintJSON(message.raw) {
                    Button {
                        UIPasteboard.general.string = prettyJSON
                    } label: {
                        Label("Copy Formatted JSON", systemImage: "doc.on.doc")
                    }
                }
            }
        }
        .navigationTitle("Message Details")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }

    private func formatFullTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    private func prettyPrintJSON(_ raw: String) -> String? {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let pretty = String(data: prettyData, encoding: .utf8) else {
            return nil
        }
        return pretty
    }
}

