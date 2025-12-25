import NDKSwiftCore
import SwiftUI

/// Default implementation of EventRenderer that displays embedded events as simple cards.
///
/// This is a chrome-free fallback renderer for embedded event references.
/// Apps should create their own EventRenderer with kind-specific dispatch for richer previews.
///
/// ## Custom EventRenderer Example
///
/// ```swift
/// struct AppEventRenderer: EventRenderer {
///     let event: NDKEvent
///     let onTap: EventTapHandler?
///
///     @ViewBuilder
///     var body: some View {
///         switch event.kind {
///         case 30023, 30024:
///             ArticleCardCompact(event: event, onTap: onTap)
///         case 39089:
///             FollowPackCard(event: event, onTap: onTap)
///         default:
///             DefaultEventView(event: event, onTap: onTap)
///         }
///     }
/// }
/// ```
public struct DefaultEventView: EventRenderer {
    public let event: NDKEvent
    public let onTap: EventTapHandler?

    @Environment(\.onEventTap) private var envOnTap

    public init(event: NDKEvent, onTap: EventTapHandler? = nil) {
        self.event = event
        self.onTap = onTap
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Kind indicator
            HStack(spacing: 4) {
                Image(systemName: iconForKind(event.kind))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(labelForKind(event.kind))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(event.id.prefix(8) + "...")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospaced()
            }

            // Content preview
            if let displayContent = displayContent {
                Text(displayContent)
                    .font(.subheadline)
                    .lineLimit(3)
            }
        }
        .padding(12)
        .background(Color.ndkSecondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture {
            (onTap ?? envOnTap)?(event)
        }
    }

    private var displayContent: String? {
        // For articles, show title if available
        if let title = event.tagValue("title"), !title.isEmpty {
            return title
        }

        // For events with alt tag, prefer that
        if let alt = event.tagValue("alt"), !alt.isEmpty {
            return alt
        }

        // Fall back to content
        let content = event.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if content.isEmpty {
            return nil
        }

        // Truncate long content
        if content.count > 150 {
            return String(content.prefix(150)) + "..."
        }
        return content
    }

    private func iconForKind(_ kind: Int) -> String {
        switch kind {
        case 0: return "person.circle"
        case 1: return "text.bubble"
        case 3: return "person.2"
        case 4: return "lock"
        case 6: return "arrow.2.squarepath"
        case 7: return "heart"
        case 20: return "photo"
        case 30023, 30024: return "doc.text"
        case 39089: return "person.3"
        case 9321: return "bitcoinsign.circle"
        default: return "doc"
        }
    }

    private func labelForKind(_ kind: Int) -> String {
        switch kind {
        case 0: return "Profile"
        case 1: return "Note"
        case 3: return "Contacts"
        case 4: return "DM"
        case 6: return "Repost"
        case 7: return "Reaction"
        case 20: return "Picture"
        case 30023: return "Article"
        case 30024: return "Draft"
        case 39089: return "Follow Pack"
        case 9321: return "Cashu Token"
        default: return "Kind \(kind)"
        }
    }
}
