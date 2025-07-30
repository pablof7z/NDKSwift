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

    private let ndk: NDK
    private let event: NDKEvent
    private let style: EventStyle
    private let showAuthor: Bool
    private let showTimestamp: Bool
    private let showInteractions: Bool
    private var eventTapAction: ((NDKEvent) -> Void)?
    private var authorTapAction: ((String) -> Void)?

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
    ///   - ndk: The NDK instance to use
    ///   - event: The NDKEvent to display
    ///   - style: The presentation style
    ///   - showAuthor: Whether to show author information
    ///   - showTimestamp: Whether to show the timestamp
    ///   - showInteractions: Whether to show interaction buttons
    public init(
        ndk: NDK,
        event: NDKEvent,
        style: EventStyle = .feed,
        showAuthor: Bool = true,
        showTimestamp: Bool = true,
        showInteractions: Bool = true
    ) {
        self.ndk = ndk
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
                    ndk: ndk,
                    event: event,
                    style: style,
                    showAuthor: showAuthor,
                    showTimestamp: showTimestamp,
                    showInteractions: showInteractions
                )
            case 20:
                NDKPictureEventView(
                    ndk: ndk,
                    event: event,
                    style: style,
                    showAuthor: showAuthor,
                    showTimestamp: showTimestamp
                )
            case EventKind.longFormContent:
                NDKLongFormArticleView(
                    ndk: ndk,
                    event: event,
                    style: style,
                    showAuthor: showAuthor,
                    showTimestamp: showTimestamp
                )
            case 9321:
                NDKCashuTokenView(
                    ndk: ndk,
                    event: event,
                    style: style,
                    showAuthor: showAuthor,
                    showTimestamp: showTimestamp
                )
            default:
                NDKGenericEventView(
                    ndk: ndk,
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
    let ndk: NDK
    let event: NDKEvent
    let style: NDKUIEventView.EventStyle
    let showAuthor: Bool
    let showTimestamp: Bool
    let showInteractions: Bool

    public var body: some View {
        VStack(alignment: .leading, spacing: NDKEventViewStyles.verticalSpacing(for: style)) {
            // Author header
            if showAuthor {
                NDKUIEventAuthorHeader(
                    ndk: ndk,
                    pubkey: event.pubkey,
                    timestamp: showTimestamp ? event.createdAt : nil,
                    style: NDKEventViewStyles.authorHeaderStyle(for: style)
                )
            }

            // Content
            NDKRichText(content: event.content)
                .font(NDKEventViewStyles.contentFont(for: style))
                .lineLimit(NDKEventViewStyles.contentLineLimit(for: style))

            // Media/URL previews would go here in full implementation

            // Interactions
            if showInteractions {
                NDKEventInteractionBar(event: event, style: NDKEventViewStyles.interactionBarStyle(for: style))
            }
        }
        .ndkEventViewStyle(style)
    }
}

// MARK: - NDKLongFormArticleView (Kind 30023)

/// Specialized view for long-form article events (kind:30023) - shows rich preview
public struct NDKLongFormArticleView: View {
    let ndk: NDK
    let event: NDKEvent
    let style: NDKUIEventView.EventStyle
    let showAuthor: Bool
    let showTimestamp: Bool

    public var body: some View {
        VStack(alignment: .leading, spacing: NDKEventViewStyles.verticalSpacing(for: style)) {
            // Author header
            if showAuthor {
                NDKUIEventAuthorHeader(
                    ndk: ndk,
                    pubkey: event.pubkey,
                    timestamp: showTimestamp ? event.createdAt : nil,
                    style: NDKEventViewStyles.authorHeaderStyle(for: style)
                )
            }

            // Article preview card
            VStack(alignment: .leading, spacing: NDKEventViewStyles.horizontalSpacing(for: style) / 2) {
                // Article image if available
                if let imageURL = extractImageURL() {
                    CachedAsyncImage(url: imageURL) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle()
                            .fill(Color.ndkGray5)
                    }
                    .frame(height: NDKEventViewStyles.imageHeight(for: style) * 0.6)
                    .clipShape(RoundedRectangle(cornerRadius: NDKEventViewStyles.cardCornerRadius(for: style) / 2))
                }

                // Title
                if let title = extractTitle() {
                    Text(title)
                        .font(NDKEventViewStyles.titleFont(for: style))
                        .fontWeight(.semibold)
                        .lineLimit(NDKEventViewStyles.titleLineLimit(for: style))
                }

                // Summary
                if let summary = extractSummary() {
                    Text(summary)
                        .font(NDKEventViewStyles.contentFont(for: style))
                        .foregroundStyle(.secondary)
                        .lineLimit(NDKEventViewStyles.contentLineLimit(for: style))
                }

                // Article metadata
                HStack {
                    Image(systemName: "doc.text")
                        .font(NDKEventViewStyles.captionFont(for: style))
                        .foregroundStyle(.secondary)

                    Text("Article")
                        .font(NDKEventViewStyles.captionFont(for: style))
                        .foregroundStyle(.secondary)

                    Spacer()

                    if let publishedAt = extractPublishedAt() {
                        NDKUIRelativeTime(timestamp: publishedAt)
                            .font(NDKEventViewStyles.captionFont(for: style))
                    }
                }
            }
            .ndkEventCardStyle(style)
        }
        .ndkEventViewStyle(style)
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
    let ndk: NDK
    let event: NDKEvent
    let style: NDKUIEventView.EventStyle
    let showAuthor: Bool
    let showTimestamp: Bool

    public var body: some View {
        VStack(alignment: .leading, spacing: NDKEventViewStyles.verticalSpacing(for: style)) {
            // Author header
            if showAuthor {
                NDKUIEventAuthorHeader(
                    ndk: ndk,
                    pubkey: event.pubkey,
                    timestamp: showTimestamp ? event.createdAt : nil,
                    style: NDKEventViewStyles.authorHeaderStyle(for: style)
                )
            }

            // Token preview card
            HStack(spacing: NDKEventViewStyles.horizontalSpacing(for: style)) {
                // Cashu icon
                Image(systemName: "bitcoinsign.circle.fill")
                    .font(NDKEventViewStyles.titleFont(for: style))
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Cashu Token")
                        .font(NDKEventViewStyles.contentFont(for: style))
                        .fontWeight(.medium)

                    if let memo = extractMemo() {
                        Text(memo)
                            .font(NDKEventViewStyles.captionFont(for: style))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("Tap to view token")
                            .font(NDKEventViewStyles.captionFont(for: style))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Token value indicator
                VStack(alignment: .trailing, spacing: 2) {
                    if let amount = extractAmount() {
                        Text("\(amount) sats")
                            .font(NDKEventViewStyles.captionFont(for: style))
                            .fontWeight(.medium)
                    }

                    Text("Token")
                        .font(NDKEventViewStyles.captionFont(for: style))
                        .foregroundStyle(.secondary)
                }
            }
            .ndkEventCardStyle(style)
            .overlay(
                RoundedRectangle(cornerRadius: NDKEventViewStyles.cardCornerRadius(for: style))
                    .stroke(Color.orange.opacity(OpacityConstants.border), lineWidth: 1)
            )
        }
        .ndkEventViewStyle(style)
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
    let ndk: NDK
    let event: NDKEvent
    let style: NDKUIEventView.EventStyle
    let showAuthor: Bool
    let showTimestamp: Bool

    public var body: some View {
        VStack(alignment: .leading, spacing: NDKEventViewStyles.verticalSpacing(for: style)) {
            // Author header
            if showAuthor {
                NDKUIEventAuthorHeader(
                    ndk: ndk,
                    pubkey: event.pubkey,
                    timestamp: showTimestamp ? event.createdAt : nil,
                    style: NDKEventViewStyles.authorHeaderStyle(for: style)
                )
            }

            // Title if available
            if let title = extractTitle() {
                Text(title)
                    .font(NDKEventViewStyles.titleFont(for: style))
                    .fontWeight(.semibold)
                    .lineLimit(NDKEventViewStyles.titleLineLimit(for: style))
            }

            // Images from imeta tags
            let imageURLs = extractImageURLs()
            if !imageURLs.isEmpty {
                PictureGrid(imageURLs: imageURLs, style: style)
            }

            // Description content
            if !event.content.isEmpty {
                NDKRichText(content: event.content)
                    .font(NDKEventViewStyles.contentFont(for: style))
                    .lineLimit(NDKEventViewStyles.contentLineLimit(for: style))
            }

            // Location if available
            if let location = extractLocation() {
                HStack(spacing: 4) {
                    Image(systemName: "location")
                        .font(NDKEventViewStyles.captionFont(for: style))
                        .foregroundStyle(.secondary)

                    Text(location)
                        .font(NDKEventViewStyles.captionFont(for: style))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .ndkEventViewStyle(style)
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
                    CachedAsyncImage(url: url) { image in
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
        return NDKEventViewStyles.imageHeight(for: style)
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
        CachedAsyncImage(url: url) { image in
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
        return NDKEventViewStyles.imageHeight(for: style)
    }
}

// MARK: - GridImageView

private struct GridImageView: View {
    let urls: [URL]
    let style: NDKUIEventView.EventStyle

    var body: some View {
        LazyVGrid(columns: gridColumns, spacing: 4) {
            ForEach(Array(urls.enumerated()), id: \.offset) { _, url in
                CachedAsyncImage(url: url) { image in
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
        return NDKEventViewStyles.gridImageHeight(for: style)
    }
}

// MARK: - NDKGenericEventView

/// Fallback view for unknown or unsupported event kinds
public struct NDKGenericEventView: View {
    let ndk: NDK
    let event: NDKEvent
    let style: NDKUIEventView.EventStyle
    let showAuthor: Bool
    let showTimestamp: Bool

    public var body: some View {
        VStack(alignment: .leading, spacing: NDKEventViewStyles.verticalSpacing(for: style)) {
            // Author header
            if showAuthor {
                NDKUIEventAuthorHeader(
                    ndk: ndk,
                    pubkey: event.pubkey,
                    timestamp: showTimestamp ? event.createdAt : nil,
                    style: NDKEventViewStyles.authorHeaderStyle(for: style)
                )
            }

            // Generic event card
            HStack(spacing: NDKEventViewStyles.horizontalSpacing(for: style)) {
                Image(systemName: "doc.text")
                    .font(NDKEventViewStyles.titleFont(for: style))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Event")
                        .font(NDKEventViewStyles.contentFont(for: style))
                        .fontWeight(.medium)

                    Text("Kind \(event.kind)")
                        .font(NDKEventViewStyles.captionFont(for: style))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .ndkEventCardStyle(style, backgroundColor: Color.ndkTertiaryBackground)

            // Show alt tag content if available
            if let altContent = event.tagValue("alt") {
                Text(altContent)
                    .font(NDKEventViewStyles.contentFont(for: style))
                    .lineLimit(NDKEventViewStyles.contentLineLimit(for: style))
            }
        }
        .ndkEventViewStyle(style)
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