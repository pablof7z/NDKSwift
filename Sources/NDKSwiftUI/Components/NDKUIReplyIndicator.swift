import NDKSwiftCore
import SwiftUI

/// A SwiftUI component that displays "Replying to @username" when an event is a reply.
///
/// The component features:
/// - NIP-10 compliant reply tag detection
/// - Automatic parent event loading from NDK
/// - Progressive loading (shows fallback immediately, updates when loaded)
/// - Optional tap gesture support for navigation to parent event
///
/// ## Usage
///
/// ```swift
/// // Simple usage
/// NDKUIReplyIndicator(ndk: ndk, event: event)
///
/// // With navigation
/// NDKUIReplyIndicator(ndk: ndk, event: event)
///     .onTap { parentEvent in
///         navigateToThread(parentEvent)
///     }
/// ```
@MainActor
public struct NDKUIReplyIndicator: View {
    // MARK: - Properties

    private let ndk: NDK
    private let event: NDKEvent
    private var tapAction: ((NDKEvent) -> Void)?

    @State private var replyToEvent: NDKEvent?
    @State private var isLoading = true

    // MARK: - Initialization

    /// Initialize with NDK instance and event
    /// - Parameters:
    ///   - ndk: The NDK instance
    ///   - event: The event to check for reply status
    public init(ndk: NDK, event: NDKEvent) {
        self.ndk = ndk
        self.event = event
    }

    // MARK: - Body

    public var body: some View {
        Group {
            if findReplyTag() != nil {
                if let replyToEvent {
                    replyIndicatorContent(replyToEvent: replyToEvent)
                } else {
                    Text("Replying to event")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task {
            if let eventId = findReplyEventId() {
                await loadReplyToEvent(eventId: eventId)
            }
        }
    }

    // MARK: - Modifiers

    /// Add a tap gesture to navigate to the parent event
    /// - Parameter action: The action to perform when tapped, receiving the parent event
    public func onTap(_ action: @escaping (NDKEvent) -> Void) -> NDKUIReplyIndicator {
        var copy = self
        copy.tapAction = action
        return copy
    }

    // MARK: - Private Views

    @ViewBuilder
    private func replyIndicatorContent(replyToEvent: NDKEvent) -> some View {
        HStack(spacing: 4) {
            Text("Replying to")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let tapAction {
                Button {
                    tapAction(replyToEvent)
                } label: {
                    HStack(spacing: 2) {
                        Text("@")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(ndk.profile(for: replyToEvent.pubkey).displayName)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: 2) {
                    Text("@")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(ndk.profile(for: replyToEvent.pubkey).displayName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Private Helpers

    /// Find the reply tag following NIP-10 spec
    private func findReplyTag() -> [String]? {
        // First, check for explicit 'reply' marker (NIP-10)
        let replyTag = event.tags.first { tag in
            tag.count > 3 && tag.first == "e" && tag[safe: 3] == "reply"
        }

        if replyTag != nil {
            return replyTag
        }

        // Check for 'root' marker as fallback
        let rootTag = event.tags.first { tag in
            tag.count > 3 && tag.first == "e" && tag[safe: 3] == "root"
        }

        if rootTag != nil {
            return rootTag
        }

        // If there's only a single 'e' tag with no marker, it's likely a reply to that event
        let eTags = event.tags.filter { $0.first == "e" }
        if eTags.count == 1 {
            return eTags.first
        }

        return nil
    }

    /// Extract the event ID from the reply tag
    private func findReplyEventId() -> String? {
        guard let replyTag = findReplyTag(),
              let eventId = replyTag[safe: 1]
        else {
            return nil
        }
        return eventId
    }

    private func loadReplyToEvent(eventId: String) async {
        isLoading = true
        defer { isLoading = false }

        let filter = NDKFilter(ids: [eventId])
        let events = await ndk.fetchEvents(filter: filter, cachePolicy: .cacheWithNetwork, timeout: 5.0)
        replyToEvent = events.first
    }
}

// MARK: - Preview

#if DEBUG
    struct NDKUIReplyIndicator_Previews: PreviewProvider {
        static var previews: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text("Reply indicator would appear here if event has reply tags")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
#endif
