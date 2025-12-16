import SwiftUI
import NDKSwiftCore

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

    public init(reference: Reference, onTap: EventTapHandler? = nil) {
        self.reference = reference
        self.onTap = onTap
    }

    public var body: some View {
        Group {
            if let event {
                Event(event: event, onTap: onTap)
            } else if isLoading {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading event...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
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

        for await fetchedEvents in dataSource.events {
            if let firstEvent = fetchedEvents.first {
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
}
