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

// MARK: - Link Embed (OpenGraph Preview)

/// Link embed - shows rich preview card
public struct LinkEmbedView: LinkRenderer {
    public let url: URL
    public let onTap: LinkTapHandler?

    @Environment(\.onLinkTap) private var envOnTap

    public init(url: URL, onTap: LinkTapHandler? = nil) {
        self.url = url
        self.onTap = onTap
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(url.host ?? "Link")
                .font(.headline)
                .lineLimit(2)

            HStack(spacing: 4) {
                Image(systemName: "link")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(url.absoluteString)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .onTapGesture {
            (onTap ?? envOnTap)?(url)
        }
    }
}

// MARK: - Image/Media Variations

/// Media carousel - displays multiple images with horizontal scrolling
public struct MediaCarouselView: View {
    let urls: [URL]
    let onTap: ((URL) -> Void)?

    @State private var currentIndex = 0

    public init(urls: [URL], onTap: ((URL) -> Void)? = nil) {
        self.urls = urls
        self.onTap = onTap
    }

    public var body: some View {
        VStack(spacing: 8) {
            TabView(selection: $currentIndex) {
                ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        case .empty:
                            ProgressView()
                                .frame(height: 300)
                        case .failure:
                            Image(systemName: "photo")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                                .frame(height: 300)
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .tag(index)
                    .onTapGesture {
                        onTap?(url)
                    }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .frame(height: 300)

            if urls.count > 1 {
                Text("\(currentIndex + 1) / \(urls.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .cornerRadius(8)
    }
}

/// Media bento grid - displays multiple images in a Pinterest-style grid
public struct MediaBentoView: View {
    let urls: [URL]
    let onTap: ((URL) -> Void)?

    public init(urls: [URL], onTap: ((URL) -> Void)? = nil) {
        self.urls = urls
        self.onTap = onTap
    }

    public var body: some View {
        let columns = [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8)
        ]

        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: gridHeight(for: index))
                            .clipped()
                    case .empty:
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: gridHeight(for: index))
                    case .failure:
                        ZStack {
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                            Image(systemName: "photo")
                                .foregroundColor(.secondary)
                        }
                        .frame(height: gridHeight(for: index))
                    @unknown default:
                        EmptyView()
                    }
                }
                .cornerRadius(8)
                .onTapGesture {
                    onTap?(url)
                }
            }
        }
    }

    private func gridHeight(for index: Int) -> CGFloat {
        // Alternate heights for bento grid effect
        [160, 200, 180, 160, 200][index % 5]
    }
}

// MARK: - Event Card Variations

/// Event card inline - minimal inline presentation
public struct EventCardInlineView: EventRenderer {
    public let event: NDKEvent
    public let onTap: EventTapHandler?

    @Environment(\.ndk) private var ndk
    @Environment(\.onEventTap) private var envOnTap

    public init(event: NDKEvent, onTap: EventTapHandler? = nil) {
        self.event = event
        self.onTap = onTap
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let ndk = ndk {
                    NDKUIAvatar(ndk: ndk, pubkey: event.pubkey, size: 24)
                }

                if let ndk = ndk {
                    NDKUIDisplayName(ndk: ndk, pubkey: event.pubkey)
                        .font(.caption.weight(.medium))
                } else {
                    Text("@\(String(event.pubkey.prefix(8)))...")
                        .font(.caption.weight(.medium))
                }

                Spacer()

                NDKUIRelativeTime(timestamp: event.createdAt)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Text(event.content)
                .font(.caption)
                .lineLimit(3)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground).opacity(0.5))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .onTapGesture {
            (onTap ?? envOnTap)?(event)
        }
    }
}

/// Event card compact - compact presentation
public struct EventCardCompactView: EventRenderer {
    public let event: NDKEvent
    public let onTap: EventTapHandler?

    @Environment(\.ndk) private var ndk
    @Environment(\.onEventTap) private var envOnTap

    public init(event: NDKEvent, onTap: EventTapHandler? = nil) {
        self.event = event
        self.onTap = onTap
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if let ndk = ndk {
                    NDKUIAvatar(ndk: ndk, pubkey: event.pubkey, size: 32)
                }

                VStack(alignment: .leading, spacing: 2) {
                    if let ndk = ndk {
                        NDKUIDisplayName(ndk: ndk, pubkey: event.pubkey)
                            .font(.subheadline.weight(.semibold))
                    } else {
                        Text("@\(String(event.pubkey.prefix(8)))...")
                            .font(.subheadline.weight(.semibold))
                    }

                    NDKUIRelativeTime(timestamp: event.createdAt)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            Text(event.content)
                .font(.subheadline)
                .lineLimit(4)
        }
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .onTapGesture {
            (onTap ?? envOnTap)?(event)
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

// MARK: - Link variations

/// Link embed style - OpenGraph preview
public typealias LinkEmbedRichText = NDKUIRichTextView<
    DefaultMentionView,
    DefaultHashtagView,
    LinkEmbedView,
    DefaultImageView,
    DefaultEventView
>

// MARK: - Event card variations

/// Event card inline style
public typealias EventInlineRichText = NDKUIRichTextView<
    DefaultMentionView,
    DefaultHashtagView,
    DefaultLinkView,
    DefaultImageView,
    EventCardInlineView
>

/// Event card compact style
public typealias EventCompactRichText = NDKUIRichTextView<
    DefaultMentionView,
    DefaultHashtagView,
    DefaultLinkView,
    DefaultImageView,
    EventCardCompactView
>
