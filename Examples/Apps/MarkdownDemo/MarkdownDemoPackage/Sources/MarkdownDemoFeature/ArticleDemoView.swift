import SwiftUI
import NDKSwiftCore
import NDKSwiftUI

// Article card type aliases
typealias ArticleHeroView = NDKUIRichTextView<
    DefaultMentionView,
    DefaultHashtagView,
    DefaultLinkView,
    DefaultImageView,
    DefaultVideoView,
    ArticleCardHero
>

typealias ArticleCompactView = NDKUIRichTextView<
    DefaultMentionView,
    DefaultHashtagView,
    DefaultLinkView,
    DefaultImageView,
    DefaultVideoView,
    ArticleCardCompact
>

typealias ArticlePortraitView = NDKUIRichTextView<
    DefaultMentionView,
    DefaultHashtagView,
    DefaultLinkView,
    DefaultImageView,
    DefaultVideoView,
    ArticleCardPortrait
>

/// Demo view showing different article card (kind:30023) renderer variations
public struct ArticleDemoView: View {
    @State private var content = "Check out this article:\nnostr:naddr1qvzqqqr4gupzqmjxss3dld622uu8q25gywum9qtg4w4cv4064jmg20xsac2aam5nqythwumn8ghj7un9d3shjtnswf5k6ctv9ehx2ap0qqxnzd3cx5urjd35xg6rwwpee39928"
    @State private var lastTapped = ""

    let ndk: NDK

    public init(ndk: NDK) {
        self.ndk = ndk
    }

    public var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Content editor
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Content")
                            .font(.headline)
                        TextEditor(text: $content)
                            .font(.system(.body, design: .monospaced))
                            .frame(height: 120)
                            .border(Color.gray.opacity(0.3), width: 1)
                        Text("Note: Article references like nostr:naddr1... will be rendered as preview cards")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)

                    // Variations
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Article Card Variations")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .padding(.horizontal)

                        variationCard(
                            title: "Hero",
                            description: "Large hero image with gradient overlay, prominent title, summary, author with profile pic, and reading time estimate. Best for featured content."
                        ) {
                            ArticleHeroView(content: content)
                                .ndk(ndk)
                                .onEventTap { event in
                                    lastTapped = "Article: \(event.id.prefix(8))..."
                                }
                        }

                        variationCard(
                            title: "Compact",
                            description: "Small 80x80 thumbnail with 2-line title and summary. Best for feeds and list views where space is limited."
                        ) {
                            ArticleCompactView(content: content)
                                .ndk(ndk)
                                .onEventTap { event in
                                    lastTapped = "Article: \(event.id.prefix(8))..."
                                }
                        }

                        variationCard(
                            title: "Portrait",
                            description: "Vertical layout with tall 3:4 aspect cover image. Fixed 240px width, best for grid layouts and card-based UIs."
                        ) {
                            ArticlePortraitView(content: content)
                                .ndk(ndk)
                                .onEventTap { event in
                                    lastTapped = "Article: \(event.id.prefix(8))..."
                                }
                        }

                        // Technical note
                        VStack(alignment: .leading, spacing: 8) {
                            Text("How it works:")
                                .font(.headline)
                            Text("When the parser encounters nostr:naddr1..., it decodes the article reference (kind:30023), fetches the event from relays, and renders a preview card (NOT the full article content). The card extracts metadata from NIP-23 tags: title, summary, image, published_at, and estimates reading time from word count.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                        .padding(.horizontal)

                        // Note about universal usage
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Universal Renderers:")
                                .font(.headline)
                            Text("Article card renderers work the same whether used in RichText or Markdown content. A kind:1 note mentioning an article (\"check out nostr:naddr1...\") or a kind:30023 article mentioning another article both use the same ArticleCard renderer.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Articles (Kind:30023)")
            .navigationBarTitleDisplayMode(.inline)
        }
        .safeAreaInset(edge: .bottom) {
            if !lastTapped.isEmpty {
                HStack {
                    Image(systemName: "hand.tap.fill")
                        .foregroundColor(.blue)
                    Text(lastTapped)
                        .font(.caption)
                    Spacer()
                    Button("Clear") {
                        lastTapped = ""
                    }
                    .font(.caption)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
            }
        }
    }

    @ViewBuilder
    private func variationCard<Content: View>(
        title: String,
        description: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            content()
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(8)
        }
        .padding(.horizontal)
    }
}

#if DEBUG
struct ArticleDemoView_Previews: PreviewProvider {
    static var previews: some View {
        ArticleDemoView(ndk: NDK())
    }
}
#endif
