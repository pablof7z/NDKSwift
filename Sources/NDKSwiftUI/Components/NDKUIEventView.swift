import SwiftUI
import NDKSwift

#if canImport(UIKit)
import UIKit
#endif

// MARK: - NDKUIEventView

/// A composable SwiftUI component that renders different Nostr event kinds with appropriate styling.
///
/// This component provides:
/// - Multi-kind event rendering (kind:1, kind:20, kind:30023, kind:9321, etc.)
/// - Embeddable design suitable for feeds, threads, and previews
/// - Progressive loading with streaming data
/// - Customizable presentation styles
/// - Built-in interaction support
///
/// ## Usage
///
/// ```swift
/// // Simple event display
/// NDKUIEventView(event: event)
///
/// // Customized for preview contexts
/// NDKUIEventView(event: event, style: .compact)
///     .onEventTapped { event in
///         // Handle event tap
///     }
///
/// // In a feed
/// ForEach(events, id: \.id) { event in
///     NDKUIEventView(event: event, style: .feed)
/// }
/// ```
public struct NDKUIEventView: View {

    // MARK: - Properties

    private let event: NDKEvent
    private let style: EventStyle
    private let showAuthor: Bool
    private let showTimestamp: Bool
    private let showInteractions: Bool
    private var eventTapAction: ((NDKEvent) -> Void)?
    private var authorTapAction: ((String) -> Void)?

    @Environment(\.ndk) private var ndk

    // MARK: - Supporting Types

    public enum EventStyle {
        case full           // Full event display with all details
        case feed           // Optimized for feed scrolling
        case compact        // Minimal display for previews
        case thread         // Optimized for thread views
        case embedded       // For embedding in other content
    }

    // MARK: - Initialization

    /// Initialize with an event
    /// - Parameters:
    ///   - event: The NDKEvent to display
    ///   - style: The presentation style
    ///   - showAuthor: Whether to show author information
    ///   - showTimestamp: Whether to show the timestamp
    ///   - showInteractions: Whether to show interaction buttons
    public init(
        event: NDKEvent,
        style: EventStyle = .feed,
        showAuthor: Bool = true,
        showTimestamp: Bool = true,
        showInteractions: Bool = true
    ) {
        self.event = event
        self.style = style
        self.showAuthor = showAuthor
        self.showTimestamp = showTimestamp
        self.showInteractions = showInteractions
    }

    // MARK: - Body

    public var body: some View {
        Group {
            switch event.kind {
            case 1:
                NDKTextNoteView(
                    event: event,
                    style: style,
                    showAuthor: showAuthor,
                    showTimestamp: showTimestamp,
                    showInteractions: showInteractions
                )
            case 20:
                NDKPictureEventView(
                    event: event,
                    style: style,
                    showAuthor: showAuthor,
                    showTimestamp: showTimestamp
                )
            case EventKind.longFormContent:
                NDKLongFormArticleView(
                    event: event,
                    style: style,
                    showAuthor: showAuthor,
                    showTimestamp: showTimestamp
                )
            case 9321:
                NDKCashuTokenView(
                    event: event,
                    style: style,
                    showAuthor: showAuthor,
                    showTimestamp: showTimestamp
                )
            default:
                NDKGenericEventView(
                    event: event,
                    style: style,
                    showAuthor: showAuthor,
                    showTimestamp: showTimestamp
                )
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            eventTapAction?(event)
        }
    }

    // MARK: - Modifiers

    /// Handle event tap gestures
    public func onEventTapped(_ action: @escaping (NDKEvent) -> Void) -> NDKUIEventView {
        var copy = self
        copy.eventTapAction = action
        return copy
    }

    /// Handle author tap gestures
    public func onAuthorTapped(_ action: @escaping (String) -> Void) -> NDKUIEventView {
        var copy = self
        copy.authorTapAction = action
        return copy
    }
}

// MARK: - NDKTextNoteView (Kind 1)

/// Specialized view for text note events (kind:1)
public struct NDKTextNoteView: View {
    let event: NDKEvent
    let style: NDKUIEventView.EventStyle
    let showAuthor: Bool
    let showTimestamp: Bool
    let showInteractions: Bool

    @Environment(\.ndk) private var ndk

    public var body: some View {
        VStack(alignment: .leading, spacing: verticalSpacing) {
            // Author header
            if showAuthor {
                NDKEventAuthorHeader(
                    pubkey: event.pubkey,
                    timestamp: showTimestamp ? event.createdAt : nil,
                    style: authorHeaderStyle
                )
            }

            // Content
            NDKRichText(content: event.content)
                .font(contentFont)
                .lineLimit(contentLineLimit)

            // Media/URL previews would go here in full implementation

            // Interactions
            if showInteractions {
                NDKEventInteractionBar(event: event, style: interactionStyle)
            }
        }
        .padding(containerPadding)
        .background(backgroundColor)
        .cornerRadius(cornerRadius)
    }

    // MARK: - Style Properties

    private var verticalSpacing: CGFloat {
        switch style {
        case .full: return 12
        case .feed: return 8
        case .compact: return 6
        case .thread: return 10
        case .embedded: return 6
        }
    }

    private var contentFont: Font {
        switch style {
        case .full: return .body
        case .feed: return .body
        case .compact: return .callout
        case .thread: return .body
        case .embedded: return .callout
        }
    }

    private var contentLineLimit: Int? {
        switch style {
        case .full: return nil
        case .feed: return 6
        case .compact: return 3
        case .thread: return nil
        case .embedded: return 3
        }
    }

    private var authorHeaderStyle: NDKEventAuthorHeader.Style {
        switch style {
        case .full: return .detailed
        case .feed: return .standard
        case .compact: return .minimal
        case .thread: return .standard
        case .embedded: return .minimal
        }
    }

    private var interactionStyle: NDKEventInteractionBar.Style {
        switch style {
        case .full: return .detailed
        case .feed: return .standard
        case .compact: return .minimal
        case .thread: return .standard
        case .embedded: return .minimal
        }
    }

    private var containerPadding: EdgeInsets {
        switch style {
        case .full: return EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
        case .feed: return EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
        case .compact: return EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
        case .thread: return EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
        case .embedded: return EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .embedded, .compact: return Color.ndkSecondaryBackground
        default: return Color.clear
        }
    }

    private var cornerRadius: CGFloat {
        switch style {
        case .embedded, .compact: return 12
        default: return 0
        }
    }
}

// MARK: - NDKLongFormArticleView (Kind 30023)

/// Specialized view for long-form article events (kind:30023) - shows rich preview
public struct NDKLongFormArticleView: View {
    let event: NDKEvent
    let style: NDKUIEventView.EventStyle
    let showAuthor: Bool
    let showTimestamp: Bool

    @Environment(\.ndk) private var ndk

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Author header
            if showAuthor {
                NDKEventAuthorHeader(
                    pubkey: event.pubkey,
                    timestamp: showTimestamp ? event.createdAt : nil,
                    style: .standard
                )
            }

            // Article preview card
            VStack(alignment: .leading, spacing: 8) {
                // Article image if available
                if let imageURL = extractImageURL() {
                    AsyncImage(url: imageURL) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle()
                            .fill(Color.ndkGray5)
                    }
                    .frame(height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                // Title
                if let title = extractTitle() {
                    Text(title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                }

                // Summary
                if let summary = extractSummary() {
                    Text(summary)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                // Article metadata
                HStack {
                    Image(systemName: "doc.text")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Article")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    if let publishedAt = extractPublishedAt() {
                        NDKRelativeTime(timestamp: publishedAt)
                            .font(.caption)
                    }
                }
            }
            .padding(12)
            .background(Color.ndkSecondaryBackground)
            .cornerRadius(12)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Helper Methods

    private func extractTitle() -> String? {
        event.tagValue("title")
    }

    private func extractSummary() -> String? {
        event.tagValue("summary") ?? event.tagValue("alt")
    }

    private func extractImageURL() -> URL? {
        if let imageTag = event.tagValue("image") {
            return URL(string: imageTag)
        }
        return nil
    }

    private func extractPublishedAt() -> Timestamp? {
        if let publishedAtString = event.tagValue("published_at"),
           let timestamp = Timestamp(publishedAtString) {
            return timestamp
        }
        return nil
    }
}

// MARK: - NDKCashuTokenView (Kind 9321)

/// Specialized view for Cashu token events (kind:9321)
public struct NDKCashuTokenView: View {
    let event: NDKEvent
    let style: NDKUIEventView.EventStyle
    let showAuthor: Bool
    let showTimestamp: Bool

    @Environment(\.ndk) private var ndk

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Author header
            if showAuthor {
                NDKEventAuthorHeader(
                    pubkey: event.pubkey,
                    timestamp: showTimestamp ? event.createdAt : nil,
                    style: .minimal
                )
            }

            // Token preview card
            HStack(spacing: 12) {
                // Cashu icon
                Image(systemName: "bitcoinsign.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Cashu Token")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    if let memo = extractMemo() {
                        Text(memo)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("Tap to view token")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Token value indicator
                VStack(alignment: .trailing, spacing: 2) {
                    if let amount = extractAmount() {
                        Text("\(amount) sats")
                            .font(.caption)
                            .fontWeight(.medium)
                    }

                    Text("Token")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(Color.ndkSecondaryBackground)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.orange.opacity(OpacityConstants.border), lineWidth: 1)
            )
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Helper Methods

    private func extractMemo() -> String? {
        // Parse the token to extract memo if possible
        // This would require implementing Cashu token parsing
        return nil
    }

    private func extractAmount() -> Int? {
        // Parse the token to extract amount if possible
        // This would require implementing Cashu token parsing
        return nil
    }
}

// MARK: - NDKPictureEventView (Kind 20)

/// Specialized view for picture events (kind:20) - NIP-68 picture-first feeds
public struct NDKPictureEventView: View {
    let event: NDKEvent
    let style: NDKUIEventView.EventStyle
    let showAuthor: Bool
    let showTimestamp: Bool

    @Environment(\.ndk) private var ndk

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Author header
            if showAuthor {
                NDKEventAuthorHeader(
                    pubkey: event.pubkey,
                    timestamp: showTimestamp ? event.createdAt : nil,
                    style: .standard
                )
            }

            // Title if available
            if let title = extractTitle() {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .lineLimit(2)
            }

            // Images from imeta tags
            let imageURLs = extractImageURLs()
            if !imageURLs.isEmpty {
                PictureGrid(imageURLs: imageURLs, style: style)
            }

            // Description content
            if !event.content.isEmpty {
                NDKRichText(content: event.content)
                    .font(.body)
                    .lineLimit(style == .compact ? 3 : nil)
            }

            // Location if available
            if let location = extractLocation() {
                HStack(spacing: 4) {
                    Image(systemName: "location")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(location)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Helper Methods

    private func extractTitle() -> String? {
        event.tagValue("title")
    }

    private func extractImageURLs() -> [URL] {
        var urls: [URL] = []

        // Extract URLs from imeta tags
        for tag in event.tags {
            if tag.count >= 2 && tag[0] == "imeta" {
                // Look for url parameter in imeta tag
                for parameter in tag.dropFirst() {
                    if parameter.hasPrefix("url ") {
                        let urlString = String(parameter.dropFirst(4))
                        if let url = URL(string: urlString) {
                            urls.append(url)
                        }
                    }
                }
            }
        }

        return urls
    }

    private func extractLocation() -> String? {
        event.tagValue("location")
    }
}

// MARK: - PictureGrid

/// Helper view for displaying picture grids
private struct PictureGrid: View {
    let imageURLs: [URL]
    let style: NDKUIEventView.EventStyle

    var body: some View {
        switch imageURLs.count {
        case 1:
            SingleImageView(url: imageURLs[0], style: style)
        case 2:
            HStack(spacing: 4) {
                ForEach(Array(imageURLs.enumerated()), id: \.offset) { _, url in
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle()
                            .fill(Color.ndkGray5)
                    }
                    .frame(height: imageHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        case 3...4:
            GridImageView(urls: Array(imageURLs.prefix(4)), style: style)
        default:
            GridImageView(urls: Array(imageURLs.prefix(4)), style: style)
                .overlay(
                    // Show "+N more" overlay for >4 images
                    overlayForExtraImages(count: imageURLs.count - 4),
                    alignment: .bottomTrailing
                )
        }
    }

    private var imageHeight: CGFloat {
        switch style {
        case .compact: return 120
        case .embedded: return 150
        default: return 200
        }
    }

    private func overlayForExtraImages(count: Int) -> some View {
        if count > 0 {
            return AnyView(
                Rectangle()
                    .fill(Color.black.opacity(OpacityConstants.overlay))
                    .frame(width: UIConstants.MediaThumbnail.width, height: UIConstants.MediaThumbnail.height)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        Text("+\(count)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                    )
                    .padding(8)
            )
        } else {
            return AnyView(EmptyView())
        }
    }
}

// MARK: - SingleImageView

private struct SingleImageView: View {
    let url: URL
    let style: NDKUIEventView.EventStyle

    var body: some View {
        AsyncImage(url: url) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fit)
        } placeholder: {
            Rectangle()
                .fill(Color.ndkGray5)
                .frame(height: imageHeight)
        }
        .frame(maxHeight: imageHeight)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var imageHeight: CGFloat {
        switch style {
        case .compact: return UIConstants.EventImageHeight.compact
        case .embedded: return UIConstants.EventImageHeight.embedded
        default: return UIConstants.EventImageHeight.default
        }
    }
}

// MARK: - GridImageView

private struct GridImageView: View {
    let urls: [URL]
    let style: NDKUIEventView.EventStyle

    var body: some View {
        LazyVGrid(columns: gridColumns, spacing: 4) {
            ForEach(Array(urls.enumerated()), id: \.offset) { _, url in
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.ndkGray5)
                }
                .frame(height: gridImageHeight)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var gridColumns: [GridItem] {
        [GridItem(.flexible()), GridItem(.flexible())]
    }

    private var gridImageHeight: CGFloat {
        switch style {
        case .compact: return 80
        case .embedded: return 100
        default: return 120
        }
    }
}

// MARK: - NDKGenericEventView

/// Fallback view for unknown or unsupported event kinds
public struct NDKGenericEventView: View {
    let event: NDKEvent
    let style: NDKUIEventView.EventStyle
    let showAuthor: Bool
    let showTimestamp: Bool

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Author header
            if showAuthor {
                NDKEventAuthorHeader(
                    pubkey: event.pubkey,
                    timestamp: showTimestamp ? event.createdAt : nil,
                    style: .minimal
                )
            }

            // Generic event card
            HStack(spacing: 12) {
                Image(systemName: "doc.text")
                    .font(.title2)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Event")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text("Kind \(event.kind)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(12)
            .background(Color.ndkTertiaryBackground)
            .cornerRadius(8)

            // Show alt tag content if available
            if let altContent = event.tagValue("alt") {
                Text(altContent)
                    .font(.body)
                    .lineLimit(3)
            }
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Preview

#if DEBUG
struct NDKUIEventView_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Mock events for preview
                // Note: These would need actual NDKEvent instances in real usage
            }
            .padding()
        }
    }
}
#endif