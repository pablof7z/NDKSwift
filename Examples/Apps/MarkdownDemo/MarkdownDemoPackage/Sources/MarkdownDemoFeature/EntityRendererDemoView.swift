import SwiftUI
import NDKSwiftCore
import NDKSwiftUI

/// Demo showcasing the pluggable renderer system with selectable renderer styles
public struct EntityRendererDemoView: View {
    @State private var lastTappedItem = ""
    @State private var editableContent: String
    @State private var selectedTab = 0
    @State private var rendererStyle: RendererStyle = .default

    let ndk: NDK

    public init(ndk: NDK) {
        self.ndk = ndk
        self._editableContent = State(initialValue: Self.defaultContent)
    }

    public var body: some View {
        TabView(selection: $selectedTab) {
            // Rich Text Tab - Plain content rendering
            NavigationView {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        richTextContent
                    }
                    .padding()
                }
                .navigationTitle("Rich Text")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        styleMenu
                    }
                }
            }
            .tabItem {
                Label("Rich Text", systemImage: "text.bubble")
            }
            .tag(0)

            // Markdown Tab - Markdown rendering
            NavigationView {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        markdownContent
                    }
                    .padding()
                }
                .navigationTitle("Markdown")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        styleMenu
                    }
                }
            }
            .tabItem {
                Label("Markdown", systemImage: "doc.richtext")
            }
            .tag(1)

            // Feed Tab - Kind:1 events from follows
            FeedTabView(ndk: ndk, rendererStyle: rendererStyle)
                .tabItem {
                    Label("Feed", systemImage: "list.bullet")
                }
                .tag(2)

            // Articles Tab - Kind:30023 events from follows
            ArticlesTabView(ndk: ndk, rendererStyle: rendererStyle)
                .tabItem {
                    Label("Articles", systemImage: "doc.text")
                }
                .tag(3)

            // Edit Tab
            NavigationView {
                VStack(spacing: 0) {
                    HStack {
                        Text("Edit Content")
                            .font(.headline)
                        Spacer()
                        Button("Reset") {
                            editableContent = Self.defaultContent
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()

                    TextEditor(text: $editableContent)
                        .font(.system(.body, design: .monospaced))
                        .padding(8)
                }
                .navigationTitle("Edit")
                .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label("Edit", systemImage: "pencil")
            }
            .tag(4)

            // Settings Tab
            SettingsView(ndk: ndk)
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(5)

            // Mentions Demo Tab
            MentionDemoView(ndk: ndk)
                .tabItem {
                    Label("Mentions", systemImage: "at")
                }
                .tag(6)

            // Hashtags Demo Tab
            HashtagDemoView(ndk: ndk)
                .tabItem {
                    Label("Hashtags", systemImage: "number")
                }
                .tag(7)

            // Links Demo Tab
            LinkDemoView(ndk: ndk)
                .tabItem {
                    Label("Links", systemImage: "link")
                }
                .tag(8)

            // Images Demo Tab
            ImageDemoView(ndk: ndk)
                .tabItem {
                    Label("Images", systemImage: "photo")
                }
                .tag(9)

            // Events Demo Tab
            EventDemoView(ndk: ndk)
                .tabItem {
                    Label("Events", systemImage: "note.text")
                }
                .tag(10)

            // Articles Demo Tab
            ArticleDemoView(ndk: ndk)
                .tabItem {
                    Label("Articles", systemImage: "doc.text")
                }
                .tag(11)
        }
        .safeAreaInset(edge: .bottom) {
            if !lastTappedItem.isEmpty {
                HStack {
                    Image(systemName: "hand.tap.fill")
                        .foregroundColor(.blue)
                    Text(lastTappedItem)
                        .font(.caption)
                    Spacer()
                    Button("Clear") {
                        lastTappedItem = ""
                    }
                    .font(.caption)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
            }
        }
    }

    // MARK: - Style Menu

    private var styleMenu: some View {
        Menu {
            ForEach(RendererStyle.allCases) { style in
                Button {
                    rendererStyle = style
                } label: {
                    HStack {
                        Text(style.rawValue)
                        if rendererStyle == style {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Label("Style", systemImage: "paintbrush")
        }
    }

    // MARK: - Rich Text Content

    @ViewBuilder
    private var richTextContent: some View {
        switch rendererStyle {
        case .default:
            DefaultStyleRichText(content: editableContent)
            .ndk(ndk)
            .onMentionTap { pubkey in lastTappedItem = "Mention: @\(pubkey.prefix(8))..." }
            .onHashtagTap { tag in lastTappedItem = "Hashtag: #\(tag)" }
            .onLinkTap { url in lastTappedItem = "Link: \(url.host ?? url.absoluteString)" }
            .onImageTap { url in lastTappedItem = "Image: \(url.lastPathComponent)" }
            .onEventTap { event in lastTappedItem = "Event: \(event.id.prefix(8))..." }

        case .compact:
            CompactStyleRichText(content: editableContent)
            .ndk(ndk)
            .onMentionTap { pubkey in lastTappedItem = "Mention: @\(pubkey.prefix(8))..." }
            .onHashtagTap { tag in lastTappedItem = "Hashtag: #\(tag)" }
            .onLinkTap { url in lastTappedItem = "Link: \(url.host ?? url.absoluteString)" }
            .onImageTap { url in lastTappedItem = "Image: \(url.lastPathComponent)" }
            .onEventTap { event in lastTappedItem = "Event: \(event.id.prefix(8))..." }

        case .pill:
            PillStyleRichText(content: editableContent)
            .ndk(ndk)
            .onMentionTap { pubkey in lastTappedItem = "Mention: @\(pubkey.prefix(8))..." }
            .onHashtagTap { tag in lastTappedItem = "Hashtag: #\(tag)" }
            .onLinkTap { url in lastTappedItem = "Link: \(url.host ?? url.absoluteString)" }
            .onImageTap { url in lastTappedItem = "Image: \(url.lastPathComponent)" }
            .onEventTap { event in lastTappedItem = "Event: \(event.id.prefix(8))..." }
        }
    }

    // MARK: - Markdown Content

    @ViewBuilder
    private var markdownContent: some View {
        switch rendererStyle {
        case .default:
            DefaultStyleMarkdown(
                content: editableContent,
                blockConfig: .default
            )
            .ndk(ndk)
            .onMentionTap { pubkey in lastTappedItem = "Mention: @\(pubkey.prefix(8))..." }
            .onHashtagTap { tag in lastTappedItem = "Hashtag: #\(tag)" }
            .onLinkTap { url in lastTappedItem = "Link: \(url.host ?? url.absoluteString)" }

        case .compact:
            CompactStyleMarkdown(
                content: editableContent,
                blockConfig: .default
            )
            .ndk(ndk)
            .onMentionTap { pubkey in lastTappedItem = "Mention: @\(pubkey.prefix(8))..." }
            .onHashtagTap { tag in lastTappedItem = "Hashtag: #\(tag)" }
            .onLinkTap { url in lastTappedItem = "Link: \(url.host ?? url.absoluteString)" }

        case .pill:
            PillStyleMarkdown(
                content: editableContent,
                blockConfig: .default
            )
            .ndk(ndk)
            .onMentionTap { pubkey in lastTappedItem = "Mention: @\(pubkey.prefix(8))..." }
            .onHashtagTap { tag in lastTappedItem = "Hashtag: #\(tag)" }
            .onLinkTap { url in lastTappedItem = "Link: \(url.host ?? url.absoluteString)" }
        }
    }

    private static let defaultContent = """
        Just discovered this amazing Nostr library!

        Check out the docs at https://ndk.fyi for more info.

        Special thanks to nostr:npub1l2vyh47mk2p0qlsku7hg0vn29faehy9hy34ygaclpn66ukqp3afqutajft for building this!

        #nostr #bitcoin #decentralized

        Here's a cool image:
        https://blossom.primal.net/f7a062caeb2cb27401b452b2d97b46ed3e7cac97aef86becb60004c4f3c4fca5.jpg

        And here's a note worth checking out:
        nostr:nevent1qgsxu35yyt0mwjjh8pcz4zprhxegz69t4wr9t74vk6zne58wzh0waycppemhxue69uhkummn9ekx7mp0qqsq3zms08nzx3a72cgc0jtsd0g0g9fdx0f9jvp69kp05peuvmrpj5g0w639m
        """
}

// MARK: - Preview

#if DEBUG
struct EntityRendererDemoView_Previews: PreviewProvider {
    static var previews: some View {
        EntityRendererDemoView(ndk: NDK())
    }
}
#endif
