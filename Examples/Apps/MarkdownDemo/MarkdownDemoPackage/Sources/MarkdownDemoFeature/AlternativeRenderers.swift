import SwiftUI
import NDKSwiftCore
import NDKSwiftUI

// MARK: - Renderer Style

/// Available renderer style variations
public enum RendererStyle: String, CaseIterable, Identifiable {
    case `default` = "Default"
    case compact = "Compact"
    case pill = "Pill"

    public var id: String { rawValue }
}

// MARK: - Image/Media Utility Components

/// Media carousel - displays multiple images with horizontal scrolling
/// Note: This is a standalone utility component, not an ImageRenderer
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
/// Note: This is a standalone utility component, not an ImageRenderer
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

// MARK: - Type Aliases for Different Renderer Configurations

/// Default style - uses library defaults
public typealias DefaultStyleRichText = NDKUIRichTextView<
    DefaultMentionView,
    DefaultHashtagView,
    DefaultLinkView,
    DefaultImageView,
    DefaultVideoView,
    DefaultEventView
>

/// Compact style - minimal, muted renderers
public typealias CompactStyleRichText = NDKUIRichTextView<
    CompactMentionView,
    CompactHashtagView,
    DefaultLinkView,
    DefaultImageView,
    DefaultVideoView,
    DefaultEventView
>

/// Pill style - badge/pill renderers
public typealias PillStyleRichText = NDKUIRichTextView<
    PillMentionView,
    PillHashtagView,
    PillLinkView,
    DefaultImageView,
    DefaultVideoView,
    DefaultEventView
>

/// Default Markdown style
public typealias DefaultStyleMarkdown = NDKUIMarkdownView<
    DefaultMentionView,
    DefaultHashtagView,
    DefaultLinkView,
    DefaultImageView,
    DefaultVideoView,
    DefaultEventView
>

/// Compact Markdown style
public typealias CompactStyleMarkdown = NDKUIMarkdownView<
    CompactMentionView,
    CompactHashtagView,
    DefaultLinkView,
    DefaultImageView,
    DefaultVideoView,
    DefaultEventView
>

/// Pill Markdown style
public typealias PillStyleMarkdown = NDKUIMarkdownView<
    PillMentionView,
    PillHashtagView,
    PillLinkView,
    DefaultImageView,
    DefaultVideoView,
    DefaultEventView
>

/// Link embed style - OpenGraph preview
public typealias LinkEmbedRichText = NDKUIRichTextView<
    DefaultMentionView,
    DefaultHashtagView,
    LinkEmbedView,
    DefaultImageView,
    DefaultVideoView,
    DefaultEventView
>

/// Event card inline style
public typealias EventInlineRichText = NDKUIRichTextView<
    DefaultMentionView,
    DefaultHashtagView,
    DefaultLinkView,
    DefaultImageView,
    DefaultVideoView,
    EventCardInlineView
>

/// Event card compact style
public typealias EventCompactRichText = NDKUIRichTextView<
    DefaultMentionView,
    DefaultHashtagView,
    DefaultLinkView,
    DefaultImageView,
    DefaultVideoView,
    EventCardCompactView
>

/// Article card hero style
public typealias ArticleHeroRichText = NDKUIRichTextView<
    DefaultMentionView,
    DefaultHashtagView,
    DefaultLinkView,
    DefaultImageView,
    DefaultVideoView,
    ArticleCardHero
>

/// Article card compact style
public typealias ArticleCompactRichText = NDKUIRichTextView<
    DefaultMentionView,
    DefaultHashtagView,
    DefaultLinkView,
    DefaultImageView,
    DefaultVideoView,
    ArticleCardCompact
>

/// Article card portrait style
public typealias ArticlePortraitRichText = NDKUIRichTextView<
    DefaultMentionView,
    DefaultHashtagView,
    DefaultLinkView,
    DefaultImageView,
    DefaultVideoView,
    ArticleCardPortrait
>

/// Article Markdown with Hero card (maps to Default style)
public typealias ArticleHeroMarkdown = NDKUIMarkdownView<
    DefaultMentionView,
    DefaultHashtagView,
    DefaultLinkView,
    DefaultImageView,
    DefaultVideoView,
    ArticleCardHero
>

/// Article Markdown with Compact card
public typealias ArticleCompactMarkdown = NDKUIMarkdownView<
    CompactMentionView,
    CompactHashtagView,
    DefaultLinkView,
    DefaultImageView,
    DefaultVideoView,
    ArticleCardCompact
>

/// Article Markdown with Portrait card (maps to Pill style)
public typealias ArticlePortraitMarkdown = NDKUIMarkdownView<
    PillMentionView,
    PillHashtagView,
    DefaultLinkView,
    DefaultImageView,
    DefaultVideoView,
    ArticleCardPortrait
>
