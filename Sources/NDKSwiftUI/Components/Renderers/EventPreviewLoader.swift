import NDKSwiftCore
import SwiftUI

/// A generic view that loads events by reference and renders them using the provided EventRenderer
public struct EventPreviewLoader<Event: EventRenderer>: View {
    public enum Reference: Hashable {
        case eventId(String)
        case note(String)
        case nevent(String)
        case naddr(String)
    }

    let reference: Reference
    let onTap: EventTapHandler?

    @Environment(\.ndk) private var ndk
    @State private var event: NDKEvent?
    @State private var isLoading = true
    @State private var showRelaySheet = false
    @State private var triedRelays: [String] = []
    @State private var manualRelayInput: String = ""

    public init(reference: Reference, onTap: EventTapHandler? = nil) {
        self.reference = reference
        self.onTap = onTap
    }

    /// Relay hints embedded in nevent/naddr references
    private var relayHints: [String] {
        switch reference {
        case .nevent(let nevent):
            if let decoded = try? ContentTagger.decodeNostrEntity(nevent) {
                return decoded.relays ?? []
            }
        case .naddr(let naddr):
            if let decoded = try? ContentTagger.decodeNostrEntity(naddr) {
                return decoded.relays ?? []
            }
        default:
            break
        }
        return []
    }

    /// Display-friendly event ID or address
    private var displayEventId: String? {
        switch reference {
        case .eventId(let id):
            return id
        case .note(let note):
            return try? Bech32.eventId(from: note)
        case .nevent(let nevent):
            return try? ContentTagger.decodeNostrEntity(nevent).eventId
        case .naddr(let naddr):
            if let decoded = try? ContentTagger.decodeNostrEntity(naddr) {
                if let kind = decoded.kind, let pubkey = decoded.pubkey, let identifier = decoded.identifier {
                    return "\(kind):\(pubkey):\(identifier)"
                }
            }
            return nil
        }
    }

    public var body: some View {
        Group {
            if let event {
                Event(event: event, onTap: onTap)
            } else if isLoading {
                Button {
                    showRelaySheet = true
                } label: {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Loading event...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            if let eventId = displayEventId {
                                Text(String(eventId.prefix(16)) + "...")
                                    .font(.caption2)
                                    .foregroundColor(.secondary.opacity(0.7))
                                    .monospaced()
                            }
                        }
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            } else {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text("Event not found")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .task {
            await loadEvent()
        }
        .sheet(isPresented: $showRelaySheet) {
            RelaySelectionSheet(
                eventId: displayEventId,
                triedRelays: triedRelays,
                relayHints: relayHints,
                manualRelayInput: $manualRelayInput,
                onRetry: { relays in
                    showRelaySheet = false
                    Task { await retryWithRelays(relays) }
                }
            )
        }
    }

    private func loadEvent() async {
        guard let ndk = ndk else {
            await MainActor.run { isLoading = false }
            return
        }

        let filter: NDKFilter

        // Handle naddr differently - they use kind/author/d-tag, not event IDs
        if case .naddr(let naddr) = reference {
            guard let decoded = try? ContentTagger.decodeNostrEntity(naddr),
                  let kind = decoded.kind,
                  let pubkey = decoded.pubkey,
                  let identifier = decoded.identifier else {
                await MainActor.run { isLoading = false }
                return
            }

            filter = NDKFilter(
                authors: [pubkey],
                kinds: [kind],
                tags: ["d": Set([identifier])]
            )
        } else {
            // For eventId/note/nevent, extract the event ID
            guard let eventId = extractEventId() else {
                await MainActor.run { isLoading = false }
                return
            }
            filter = NDKFilter(ids: [eventId])
        }

        let dataSource = ndk.subscribe(filter: filter)

        for await batch in dataSource.events {
            if let firstEvent = batch.first {
                await MainActor.run {
                    self.event = firstEvent
                    self.isLoading = false
                }
                break
            }
        }

        await MainActor.run {
            if self.event == nil {
                self.isLoading = false
            }
        }
    }

    private func extractEventId() -> String? {
        switch reference {
        case .eventId(let id):
            return id
        case .note(let note):
            return try? Bech32.eventId(from: note)
        case .nevent(let nevent):
            if let decoded = try? ContentTagger.decodeNostrEntity(nevent) {
                return decoded.eventId
            }
            return nil
        case .naddr:
            // naddr is handled separately in loadEvent()
            return nil
        }
    }

    private func buildFilter() -> NDKFilter? {
        if case .naddr(let naddr) = reference {
            guard let decoded = try? ContentTagger.decodeNostrEntity(naddr),
                  let kind = decoded.kind,
                  let pubkey = decoded.pubkey,
                  let identifier = decoded.identifier else {
                return nil
            }
            return NDKFilter(
                authors: [pubkey],
                kinds: [kind],
                tags: ["d": Set([identifier])]
            )
        } else {
            guard let eventId = extractEventId() else { return nil }
            return NDKFilter(ids: [eventId])
        }
    }

    private func retryWithRelays(_ relays: Set<String>) async {
        guard let ndk = ndk, let filter = buildFilter() else { return }

        await MainActor.run {
            isLoading = true
            triedRelays.append(contentsOf: relays)
        }

        let subscription = NDKSubscription(
            ndk: ndk,
            filter: filter,
            relays: relays,
            exclusiveRelays: true,
            closeOnEose: true
        )

        for await batch in subscription.events {
            if let firstEvent = batch.first {
                await MainActor.run {
                    self.event = firstEvent
                    self.isLoading = false
                }
                break
            }
        }

        await MainActor.run {
            if self.event == nil {
                self.isLoading = false
            }
        }
    }
}

// MARK: - Relay Selection Sheet

private struct RelaySelectionSheet: View {
    let eventId: String?
    let triedRelays: [String]
    let relayHints: [String]
    @Binding var manualRelayInput: String
    let onRetry: (Set<String>) -> Void

    var body: some View {
        NavigationStack {
            List {
                if let eventId {
                    Section("Event") {
                        Text(eventId)
                            .font(.caption)
                            .monospaced()
                            .textSelection(.enabled)
                    }
                }

                if !triedRelays.isEmpty {
                    Section("Tried Relays") {
                        ForEach(triedRelays, id: \.self) { relay in
                            HStack {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                                Text(relay)
                                    .font(.caption)
                            }
                        }
                    }
                }

                if !relayHints.isEmpty {
                    Section("Relay Hints") {
                        ForEach(relayHints, id: \.self) { relay in
                            Button {
                                onRetry(Set([relay]))
                            } label: {
                                HStack {
                                    Text(relay)
                                        .font(.caption)
                                    Spacer()
                                    Image(systemName: "arrow.clockwise")
                                }
                            }
                        }
                    }
                }

                Section("Try Custom Relay") {
                    TextField("wss://relay.example.com", text: $manualRelayInput)
                        #if !os(macOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                        .font(.caption)

                    Button("Try Relay") {
                        let relay = manualRelayInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !relay.isEmpty else { return }
                        onRetry(Set([relay]))
                    }
                    .disabled(manualRelayInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("Event Loader")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .presentationDetents([.medium])
    }
}
