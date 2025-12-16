import SwiftUI
import NDKSwiftCore
import NDKSwiftUI

// MARK: - Compact Renderers (Minimal styling)

/// Compact mention - just shows truncated npub, no profile loading
public struct CompactMentionView: MentionRenderer {
    public let pubkey: String
    public let npub: String
    public let onTap: MentionTapHandler?

    @Environment(\.onMentionTap) private var envOnTap

    public init(pubkey: String, npub: String, onTap: MentionTapHandler? = nil) {
        self.pubkey = pubkey
        self.npub = npub
        self.onTap = onTap
    }

    public var body: some View {
        Text("@\(String(npub.prefix(12)))...")
            .font(.footnote.monospaced())
            .foregroundColor(.secondary)
            .onTapGesture {
                (onTap ?? envOnTap)?(pubkey)
            }
    }
}

/// Compact hashtag - smaller, muted styling
public struct CompactHashtagView: HashtagRenderer {
    public let tag: String
    public let onTap: HashtagTapHandler?

    @Environment(\.onHashtagTap) private var envOnTap

    public init(tag: String, onTap: HashtagTapHandler? = nil) {
        self.tag = tag
        self.onTap = onTap
    }

    public var body: some View {
        Text("#\(tag)")
            .font(.footnote)
            .foregroundColor(.secondary)
            .onTapGesture {
                (onTap ?? envOnTap)?(tag)
            }
    }
}

// MARK: - Pill/Badge Renderers (Styled with backgrounds)

/// Pill mention - shows name in a colored pill
public struct PillMentionView: MentionRenderer {
    public let pubkey: String
    public let npub: String
    public let onTap: MentionTapHandler?

    @Environment(\.ndk) private var ndk
    @Environment(\.onMentionTap) private var envOnTap

    public init(pubkey: String, npub: String, onTap: MentionTapHandler? = nil) {
        self.pubkey = pubkey
        self.npub = npub
        self.onTap = onTap
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "person.fill")
                .font(.caption2)
            Group {
                if let ndk = ndk {
                    NDKUIDisplayName(ndk: ndk, pubkey: pubkey)
                } else {
                    Text("@\(String(npub.prefix(8)))...")
                }
            }
            .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.blue.opacity(0.15))
        .foregroundColor(.blue)
        .cornerRadius(12)
        .onTapGesture {
            (onTap ?? envOnTap)?(pubkey)
        }
    }
}

/// Pill hashtag - shows tag in a colored pill
public struct PillHashtagView: HashtagRenderer {
    public let tag: String
    public let onTap: HashtagTapHandler?

    @Environment(\.onHashtagTap) private var envOnTap

    public init(tag: String, onTap: HashtagTapHandler? = nil) {
        self.tag = tag
        self.onTap = onTap
    }

    public var body: some View {
        Text("#\(tag)")
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.purple.opacity(0.15))
            .foregroundColor(.purple)
            .cornerRadius(12)
            .onTapGesture {
                (onTap ?? envOnTap)?(tag)
            }
    }
}

/// Pill link - shows URL in a colored pill
public struct PillLinkView: LinkRenderer {
    public let url: URL
    public let onTap: LinkTapHandler?

    @Environment(\.onLinkTap) private var envOnTap

    public init(url: URL, onTap: LinkTapHandler? = nil) {
        self.url = url
        self.onTap = onTap
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "link")
                .font(.caption2)
            Text(url.host ?? url.absoluteString)
                .font(.caption)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.green.opacity(0.15))
        .foregroundColor(.green)
        .cornerRadius(12)
        .onTapGesture {
            (onTap ?? envOnTap)?(url)
        }
    }
}

// MARK: - Typealiases for different configurations

/// Default style - uses library defaults
public typealias DefaultStyleRichText = NDKUIRichTextView<
    DefaultMentionView,
    DefaultHashtagView,
    DefaultLinkView,
    DefaultImageView,
    DefaultEventView
>

/// Compact style - minimal, muted renderers
public typealias CompactStyleRichText = NDKUIRichTextView<
    CompactMentionView,
    CompactHashtagView,
    DefaultLinkView,
    DefaultImageView,
    DefaultEventView
>

/// Pill style - badge/pill renderers
public typealias PillStyleRichText = NDKUIRichTextView<
    PillMentionView,
    PillHashtagView,
    PillLinkView,
    DefaultImageView,
    DefaultEventView
>

/// Default Markdown style
public typealias DefaultStyleMarkdown = NDKUIMarkdownView<
    DefaultMentionView,
    DefaultHashtagView,
    DefaultLinkView,
    DefaultImageView,
    DefaultEventView
>

/// Compact Markdown style
public typealias CompactStyleMarkdown = NDKUIMarkdownView<
    CompactMentionView,
    CompactHashtagView,
    DefaultLinkView,
    DefaultImageView,
    DefaultEventView
>

/// Pill Markdown style
public typealias PillStyleMarkdown = NDKUIMarkdownView<
    PillMentionView,
    PillHashtagView,
    PillLinkView,
    DefaultImageView,
    DefaultEventView
>

// MARK: - Renderer Style Enum

public enum RendererStyle: String, CaseIterable, Identifiable {
    case `default` = "Default"
    case compact = "Compact"
    case pill = "Pill"

    public var id: String { rawValue }

    public var description: String {
        switch self {
        case .default:
            return "Standard styling with profile loading"
        case .compact:
            return "Minimal styling, truncated IDs"
        case .pill:
            return "Badge/pill styling with icons"
        }
    }
}
