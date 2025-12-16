import SwiftUI
import NDKSwiftCore
import NDKSwiftUI

/// Advanced demo allowing per-entity-type renderer selection
public struct EntityRendererDemoView: View {
    @State private var imageRenderer = ImageRendererType.placeholder
    @State private var mentionRenderer = MentionRendererType.inline
    @State private var eventRenderer = EventRendererType.reference
    @State private var linkRenderer = LinkRendererType.simple
    @State private var hashtagRenderer = HashtagRendererType.highlighted
    @State private var codeBlockRenderer = CodeBlockRendererType.standard
    @State private var selectedStyle = 0
    @State private var lastTappedItem = ""

    let ndk: NDK

    public init(ndk: NDK) {
        self.ndk = ndk
    }

    enum ImageRendererType: String, CaseIterable {
        case hidden = "Hidden"
        case placeholder = "Placeholder (🖼)"
        case asyncImage = "Async Image"
        case fullImage = "Full Image with Zoom"
    }

    enum MentionRendererType: String, CaseIterable {
        case hidden = "Hidden"
        case inline = "Inline (@user)"
        case highlighted = "Highlighted"
        case profileCard = "Profile Card"
    }

    enum EventRendererType: String, CaseIterable {
        case hidden = "Hidden"
        case reference = "Reference (note1...)"
        case quote = "Quote Card"
        case preview = "Event Preview"
    }

    enum LinkRendererType: String, CaseIterable {
        case hidden = "Hidden"
        case simple = "Simple Link"
        case preview = "Link Preview"
        case button = "Button Style"
    }

    enum HashtagRendererType: String, CaseIterable {
        case hidden = "Hidden"
        case plain = "Plain Text"
        case highlighted = "Highlighted #tag"
        case chip = "Chip Style"
    }

    enum CodeBlockRendererType: String, CaseIterable {
        case hidden = "Hidden"
        case standard = "Standard"
        case themed = "Syntax Themed"
        case minimal = "Minimal"
    }

    private let styles = [
        ("Default", MarkdownConfiguration()),
        ("Minimal", .minimal),
        ("Dark", .dark),
        ("Nostr", .nostr),
        ("Compact", .compact)
    ]

    public var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Configuration Panel
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Style selector
                        HStack {
                            Text("Overall Style:")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Picker("Style", selection: $selectedStyle) {
                                ForEach(0..<styles.count, id: \.self) { index in
                                    Text(styles[index].0).tag(index)
                                }
                            }
                            .pickerStyle(.menu)
                        }

                        Divider()

                        Text("Entity Renderers")
                            .font(.headline)

                        // Entity type renderers
                        rendererPicker("Images:", selection: $imageRenderer)
                        rendererPicker("Mentions:", selection: $mentionRenderer)
                        rendererPicker("Events:", selection: $eventRenderer)
                        rendererPicker("Links:", selection: $linkRenderer)
                        rendererPicker("Hashtags:", selection: $hashtagRenderer)
                        rendererPicker("Code Blocks:", selection: $codeBlockRenderer)
                    }
                    .padding()
                    .background(Color.gray.opacity(0.05))
                }
                .frame(maxHeight: 280)

                Divider()

                // Last tapped item indicator
                if !lastTappedItem.isEmpty {
                    HStack {
                        Image(systemName: "hand.tap.fill")
                            .foregroundColor(.blue)
                        Text("Tapped: \(lastTappedItem)")
                            .font(.caption)
                        Spacer()
                        Button("Clear") {
                            lastTappedItem = ""
                        }
                        .font(.caption)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.1))
                }

                Divider()

                // Content display
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        renderContent()
                            .padding()

                        // Source markdown
                        DisclosureGroup("View Source Markdown") {
                            Text(comprehensiveContent)
                                .font(.system(.caption, design: .monospaced))
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                        }
                        .padding(.horizontal)
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("Entity Renderer Demo")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private func rendererPicker<T: RawRepresentable & CaseIterable & Hashable>(
        _ label: String,
        selection: Binding<T>
    ) -> some View where T.RawValue == String {
        HStack {
            Text(label)
                .font(.caption)
                .frame(width: 90, alignment: .leading)

            Picker(label, selection: selection) {
                ForEach(Array(T.allCases), id: \.self) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.menu)
        }
    }

    @ViewBuilder
    private func renderContent() -> some View {
        // Use custom renderer based on settings
        CustomEntityRenderer(
            content: comprehensiveContent,
            ndk: ndk,
            style: styles[selectedStyle].1,
            imageRenderer: imageRenderer,
            mentionRenderer: mentionRenderer,
            eventRenderer: eventRenderer,
            linkRenderer: linkRenderer,
            hashtagRenderer: hashtagRenderer,
            codeBlockRenderer: codeBlockRenderer,
            onTap: { item in
                lastTappedItem = item
            }
        )
    }

    private var comprehensiveContent: String {
        """
        Just discovered this amazing Nostr library! 🚀

        Check out the docs at https://ndk.fyi for more info.

        Special thanks to nostr:npub1l2vyh47mk2p0qlsku7hg0vn29faehy9hy34ygaclpn66ukqp3afqutajft for building this!

        #nostr #bitcoin #decentralized

        Here's a cool image to go with it:
        https://r2a.primal.net/uploads2/d/f3/bd/df3bdd118f7db2cdf57821f958033db07dfd9de72248e6869734cbb9e2e8c130.png

        This is an article:
        nostr:naddr1qvzqqqr4gupzqmjxss3dld622uu8q25gywum9qtg4w4cv4064jmg20xsac2aam5nqythwumn8ghj7un9d3shjtnswf5k6ctv9ehx2ap0qqxnzd3cx5urjd35xg6rwwpee39928

        And here's a note worth checking out:
        nostr:nevent1qgsxu35yyt0mwjjh8pcz4zprhxegz69t4wr9t74vk6zne58wzh0waycppemhxue69uhkummn9ekx7mp0qqsq3zms08nzx3a72cgc0jtsd0g0g9fdx0f9jvp69kp05peuvmrpj5g0w639m
        """
    }
}

// MARK: - Custom Entity Renderer

struct CustomEntityRenderer: View {
    let content: String
    let ndk: NDK
    let style: MarkdownConfiguration
    let imageRenderer: EntityRendererDemoView.ImageRendererType
    let mentionRenderer: EntityRendererDemoView.MentionRendererType
    let eventRenderer: EntityRendererDemoView.EventRendererType
    let linkRenderer: EntityRendererDemoView.LinkRendererType
    let hashtagRenderer: EntityRendererDemoView.HashtagRendererType
    let codeBlockRenderer: EntityRendererDemoView.CodeBlockRendererType
    let onTap: (String) -> Void

    var body: some View {
        // Use NDKUIRichTextView which properly loads and displays user profiles for mentions
        NDKUIRichTextView(
            ndk: ndk,
            content: content,
            showLinkPreviews: linkRenderer == .preview,
            style: richTextStyle
        )
        .onMentionTapped { pubkey in
            onTap("Mention: @\(pubkey.prefix(8))... (using \(mentionRenderer.rawValue))")
        }
        .onHashtagTapped { tag in
            onTap("Hashtag: #\(tag) (using \(hashtagRenderer.rawValue))")
        }
        .onLinkTapped { url in
            onTap("Link: \(url.absoluteString) (using \(linkRenderer.rawValue))")
        }
        .onEventTapped { eventId in
            onTap("Event: \(eventId.prefix(8))... (using \(eventRenderer.rawValue))")
        }
    }

    private var richTextStyle: NDKUIRichTextView.Style {
        switch mentionRenderer {
        case .inline:
            return .compact
        case .profileCard:
            return .full
        case .highlighted:
            return .full
        case .hidden:
            return .minimal
        }
    }
}

// MARK: - Preview

#if DEBUG
struct EntityRendererDemoView_Previews: PreviewProvider {
    static var previews: some View {
        EntityRendererDemoView(ndk: NDK())
    }
}
#endif
