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
        # Welcome to Nostr on NDK! ⚡

        **Nostr** is a *simple*, open protocol that enables truly **decentralized** and *censorship-resistant* social media.

        ## Connect with People

        Check out these amazing Nostr contributors:
        - @npub1sn0wdenkukak0d9dfczzeacvhkrgz92ak56egt7vdgzn8pv2wfqqhrjdv9 (Pablo)
        - @alice and @bob are joining too!

        ## Discover Content

        See this interesting note:
        > note1gmtnz6q2m55epmlpe3semjkwtj4av3jvx4emmjsa8g3s9x7tgjsq4tnvj

        Or browse events:
        nevent1qqsyx7v0hx5xvvjwxj5xvvjwxj5xvvjwxj5xvvjwxj5xvvjwxj5xvvjwxj5xv

        ## Popular Topics

        Trending on Nostr: #nostr #bitcoin #lightning #freedom #decentralization

        Join conversations: #introductions #plebchain #grownostr

        ## Learn More

        Visit [nostr.com](https://nostr.com) for guides and tutorials.

        Check out the protocol documentation at [github.com/nostr-protocol](https://github.com/nostr-protocol/nostr).

        ## Share Images

        ![Nostr Logo](https://nostr.build/i/nostr.build_6a36f5eb16b2c9f7a5d3d7e7b9dce58f7ce1ff0c7e3c8b4e2f7d1b5c6e9a0d3f.png)

        Beautiful landscapes:
        ![Mountain View](https://picsum.photos/400/300)

        ## Code Examples

        Connect to a relay:

        ```swift
        let ndk = NDK()
        await ndk.pool.connect(to: "wss://relay.nostr.com")
        ```

        Publish an event:

        ```javascript
        const event = {
          kind: 1,
          content: "Hello Nostr!",
          created_at: Math.floor(Date.now() / 1000)
        }
        await relay.publish(event)
        ```

        ## Get Involved

        Start building on Nostr today! Follow #asknostr for help.

        ---

        Made with ❤️ by the Nostr community
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
        // For now, use the standard renderer
        // In a full implementation, this would parse and render each entity type
        // according to the selected renderer
        NDKUIMarkdownRenderer(content, ndk: ndk)
            .markdownStyle(style)
            .onMentionTap { pubkey in
                onTap("Mention: @\(pubkey.prefix(8))... (using \(mentionRenderer.rawValue))")
            }
            .onHashtagTap { tag in
                onTap("Hashtag: #\(tag) (using \(hashtagRenderer.rawValue))")
            }
            .onLinkTap { url in
                onTap("Link: \(url.absoluteString) (using \(linkRenderer.rawValue))")
            }
            .onNostrEntityTap { entity in
                switch entity {
                case .npub, .nprofile:
                    onTap("Nostr User (using \(mentionRenderer.rawValue))")
                case .note, .nevent:
                    onTap("Nostr Event (using \(eventRenderer.rawValue))")
                default:
                    onTap("Nostr Entity: \(String(describing: entity))")
                }
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
