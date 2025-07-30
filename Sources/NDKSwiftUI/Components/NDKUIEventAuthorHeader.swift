import SwiftUI
import NDKSwift

// MARK: - NDKUIEventAuthorHeader

/// A reusable component that displays event author information with profile picture, name, and timestamp.
///
/// This component provides:
/// - Author profile picture with progressive loading
/// - Display name with fallbacks
/// - Timestamp with relative time formatting
/// - Multiple presentation styles
/// - Tap gesture support for navigation
///
/// ## Usage
///
/// ```swift
/// NDKUIEventAuthorHeader(
///     pubkey: event.pubkey,
///     timestamp: event.createdAt,
///     style: .standard
/// )
/// .onAuthorTapped { pubkey in
///     // Navigate to profile
/// }
/// ```
public struct NDKUIEventAuthorHeader: View {

    // MARK: - Properties

    private let ndk: NDK
    private let pubkey: String
    private let timestamp: Timestamp?
    private let style: Style
    private var authorTapAction: ((String) -> Void)?

    // MARK: - Supporting Types

    public enum Style {
        case minimal    // Small avatar, name only
        case standard   // Medium avatar, name + timestamp
        case detailed   // Large avatar, name + username + timestamp
    }

    // MARK: - Initialization

    /// Initialize with author information
    /// - Parameters:
    ///   - ndk: The NDK instance
    ///   - pubkey: The author's public key
    ///   - timestamp: Optional timestamp to display
    ///   - style: The presentation style
    public init(
        ndk: NDK,
        pubkey: String,
        timestamp: Timestamp? = nil,
        style: Style = .standard
    ) {
        self.ndk = ndk
        self.pubkey = pubkey
        self.timestamp = timestamp
        self.style = style
    }

    // MARK: - Body

    public var body: some View {
        HStack(spacing: horizontalSpacing) {
            // Profile picture
            NDKUIProfilePicture(ndk: ndk, pubkey: pubkey, size: avatarSize)
                .onTapGesture {
                    authorTapAction?(pubkey)
                }

            // Author info
            VStack(alignment: .leading, spacing: nameSpacing) {
                // Display name
                NDKUIDisplayName(ndk: ndk, pubkey: pubkey)
                    .font(nameFont)
                    .fontWeight(.medium)
                    .onTapGesture {
                        authorTapAction?(pubkey)
                    }

                // Username (detailed style only)
                if style == .detailed {
                    NDKUIUsername(ndk: ndk, pubkey: pubkey)
                        .font(usernameFont)
                        .foregroundStyle(.secondary)
                        .onTapGesture {
                            authorTapAction?(pubkey)
                        }
                }

                // Timestamp (if provided and not minimal)
                if let timestamp = timestamp, style != .minimal {
                    NDKUIRelativeTime(timestamp: timestamp)
                        .font(timestampFont)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Timestamp (minimal style, on the right)
            if let timestamp = timestamp, style == .minimal {
                NDKUIRelativeTime(timestamp: timestamp)
                    .font(timestampFont)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Style Properties

    private var avatarSize: CGFloat {
        switch style {
        case .minimal: return 24
        case .standard: return 32
        case .detailed: return 40
        }
    }

    private var horizontalSpacing: CGFloat {
        switch style {
        case .minimal: return 8
        case .standard: return 10
        case .detailed: return 12
        }
    }

    private var nameSpacing: CGFloat {
        switch style {
        case .minimal: return 0
        case .standard: return 2
        case .detailed: return 3
        }
    }

    private var nameFont: Font {
        switch style {
        case .minimal: return .caption
        case .standard: return .subheadline
        case .detailed: return .body
        }
    }

    private var usernameFont: Font {
        switch style {
        case .minimal: return .caption2
        case .standard: return .caption
        case .detailed: return .callout
        }
    }

    private var timestampFont: Font {
        switch style {
        case .minimal: return .caption2
        case .standard: return .caption
        case .detailed: return .caption
        }
    }

    // MARK: - Modifiers

    /// Handle author tap gestures
    public func onAuthorTapped(_ action: @escaping (String) -> Void) -> NDKUIEventAuthorHeader {
        var copy = self
        copy.authorTapAction = action
        return copy
    }
}

// MARK: - NDKEventInteractionBar

/// A component that displays interaction buttons for events (like, reply, repost, zap).
///
/// Features:
/// - Reaction buttons with counts
/// - Customizable button sets
/// - Different presentation styles
/// - Tap gesture handling
///
/// ## Usage
///
/// ```swift
/// NDKEventInteractionBar(event: event, style: .standard)
///     .onReplyTapped { event in
///         // Handle reply
///     }
///     .onLikeTapped { event in
///         // Handle like
///     }
/// ```
public struct NDKEventInteractionBar: View {

    // MARK: - Properties

    private let event: NDKEvent
    private let style: Style
    private var replyAction: ((NDKEvent) -> Void)?
    private var likeAction: ((NDKEvent) -> Void)?
    private var repostAction: ((NDKEvent) -> Void)?
    private var zapAction: ((NDKEvent) -> Void)?

    @Environment(\.ndk) private var ndk
    @State private var reactionCounts: ReactionCounts = ReactionCounts()

    // MARK: - Supporting Types

    public enum Style {
        case minimal    // Icons only, no counts
        case standard   // Icons with counts
        case detailed   // Icons with counts and labels
    }

    private struct ReactionCounts {
        var replies: Int = 0
        var likes: Int = 0
        var reposts: Int = 0
        var zaps: Int = 0
    }

    // MARK: - Initialization

    public init(event: NDKEvent, style: Style = .standard) {
        self.event = event
        self.style = style
    }

    // MARK: - Body

    public var body: some View {
        HStack(spacing: buttonSpacing) {
            // Reply button
            InteractionButton(
                icon: "bubble.left",
                count: reactionCounts.replies,
                style: style,
                color: .primary
            ) {
                replyAction?(event)
            }

            // Repost button
            InteractionButton(
                icon: "arrow.2.squarepath",
                count: reactionCounts.reposts,
                style: style,
                color: .green
            ) {
                repostAction?(event)
            }

            // Like button
            InteractionButton(
                icon: "heart",
                count: reactionCounts.likes,
                style: style,
                color: .red
            ) {
                likeAction?(event)
            }

            // Zap button
            InteractionButton(
                icon: "bolt",
                count: reactionCounts.zaps,
                style: style,
                color: .orange
            ) {
                zapAction?(event)
            }

            Spacer()
        }
    }

    // MARK: - Style Properties

    private var buttonSpacing: CGFloat {
        switch style {
        case .minimal: return 16
        case .standard: return 20
        case .detailed: return 24
        }
    }

    // MARK: - Modifiers

    public func onReplyTapped(_ action: @escaping (NDKEvent) -> Void) -> NDKEventInteractionBar {
        var copy = self
        copy.replyAction = action
        return copy
    }

    public func onLikeTapped(_ action: @escaping (NDKEvent) -> Void) -> NDKEventInteractionBar {
        var copy = self
        copy.likeAction = action
        return copy
    }

    public func onRepostTapped(_ action: @escaping (NDKEvent) -> Void) -> NDKEventInteractionBar {
        var copy = self
        copy.repostAction = action
        return copy
    }

    public func onZapTapped(_ action: @escaping (NDKEvent) -> Void) -> NDKEventInteractionBar {
        var copy = self
        copy.zapAction = action
        return copy
    }
}

// MARK: - InteractionButton

/// A private component for individual interaction buttons
private struct InteractionButton: View {
    let icon: String
    let count: Int
    let style: NDKEventInteractionBar.Style
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(iconFont)
                    .foregroundStyle(color.opacity(OpacityConstants.secondary))

                if style != .minimal && count > 0 {
                    Text("\(count)")
                        .font(countFont)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var iconFont: Font {
        switch style {
        case .minimal: return .caption
        case .standard: return .subheadline
        case .detailed: return .body
        }
    }

    private var countFont: Font {
        switch style {
        case .minimal: return .caption2
        case .standard: return .caption
        case .detailed: return .callout
        }
    }
}

// MARK: - Preview

#if DEBUG
struct NDKUIEventAuthorHeader_Previews: PreviewProvider {
    static var previews: some View {
        // Create a mock NDK for preview
        let mockNDK = NDK(relayUrls: [])
        
        VStack(spacing: 20) {
            NDKUIEventAuthorHeader(
                ndk: mockNDK,
                pubkey: "sample_pubkey",
                timestamp: 1640995200,
                style: .minimal
            )

            NDKUIEventAuthorHeader(
                ndk: mockNDK,
                pubkey: "sample_pubkey",
                timestamp: 1640995200,
                style: .standard
            )

            NDKUIEventAuthorHeader(
                ndk: mockNDK,
                pubkey: "sample_pubkey",
                timestamp: 1640995200,
                style: .detailed
            )

            Divider()

            // Mock interaction bar
            // NDKEventInteractionBar(event: mockEvent, style: .standard)
        }
        .padding()
    }
}
#endif