import SwiftUI
import NDKSwiftCore
import NDKSwiftNostrDB

struct UnpublishedEventsView: View {
    @Environment(ChirpState.self) private var state
    @State private var unpublishedRecords: [String: UnpublishedStore.UnpublishedEventRecord] = [:]
    @State private var isRetrying: Set<String> = []
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if unpublishedRecords.isEmpty {
                ContentUnavailableView(
                    "No Unpublished Events",
                    systemImage: "checkmark.circle",
                    description: Text("All events have been successfully published")
                )
            } else {
                List {
                    ForEach(Array(unpublishedRecords.keys.sorted()), id: \.self) { eventId in
                        if let record = unpublishedRecords[eventId] {
                            UnpublishedEventRow(
                                eventId: eventId,
                                record: record,
                                isRetrying: isRetrying.contains(eventId),
                                onRetry: {
                                    await retryEvent(eventId: eventId, record: record)
                                },
                                onDelete: {
                                    await deleteEvent(eventId: eventId)
                                }
                            )
                        }
                    }
                }

                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding()
                }
            }
        }
        .navigationTitle("Unpublished Events")
        .task {
            await loadUnpublishedEvents()
        }
    }

    private func loadUnpublishedEvents() async {
        guard let cache = state.ndk.cache as? NDKNostrDBCache else {
            errorMessage = "Unpublished events tracking not available"
            return
        }

        unpublishedRecords = await cache.getAllUnpublishedRecords()
    }

    private func retryEvent(eventId: String, record: UnpublishedStore.UnpublishedEventRecord) async {
        isRetrying.insert(eventId)
        defer { isRetrying.remove(eventId) }

        guard let data = record.event.data(using: .utf8),
              let event = try? JSONCoding.decode(NDKEvent.self, from: data) else {
            errorMessage = "Failed to decode event"
            return
        }

        let pendingRelays = Set(record.pendingRelays.keys)
        let ndk = state.ndk
        do {
            _ = try await Task { @MainActor in
                try await ndk.publish(event, to: pendingRelays)
            }.value
            await loadUnpublishedEvents()
        } catch {
            errorMessage = "Failed to retry: \(error.localizedDescription)"
        }
    }

    private func deleteEvent(eventId: String) async {
        guard let cache = state.ndk.cache as? NDKNostrDBCache else {
            return
        }

        do {
            try await cache.removeUnpublishedEvent(eventId: eventId)
            await loadUnpublishedEvents()
        } catch {
            errorMessage = "Failed to delete: \(error.localizedDescription)"
        }
    }
}

struct UnpublishedEventRow: View {
    let eventId: String
    let record: UnpublishedStore.UnpublishedEventRecord
    let isRetrying: Bool
    let onRetry: () async -> Void
    let onDelete: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Event ID:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(String(eventId.prefix(16)) + "...")
                    .font(.caption.monospaced())
                    .foregroundStyle(.primary)
            }

            if let kind = record.kind {
                Text("Kind \(kind)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !record.publishedRelays.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Published:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(record.publishedRelays, id: \.self) { relay in
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                            Text(relay)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !record.pendingRelays.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Failed:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(Array(record.pendingRelays.keys.sorted()), id: \.self) { relay in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.red)
                                    .font(.caption)
                                Text(relay)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let reason = record.pendingRelays[relay], !reason.isEmpty {
                                Text(reason)
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                                    .padding(.leading, 16)
                            }
                        }
                    }
                }
            }

            HStack {
                Button {
                    Task {
                        await onRetry()
                    }
                } label: {
                    if isRetrying {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Retry", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(isRetrying)
                .buttonStyle(.bordered)

                Button(role: .destructive) {
                    Task {
                        await onDelete()
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    let ndk = NDK(relayURLs: [])
    let authManager = NDKAuthManager(ndk: ndk)
    let relayCollection = NDKRelayCollection(ndk: ndk)
    let state = ChirpState(ndk: ndk, authManager: authManager, relayCollection: relayCollection)

    return NavigationStack {
        UnpublishedEventsView()
            .environment(state)
    }
}
