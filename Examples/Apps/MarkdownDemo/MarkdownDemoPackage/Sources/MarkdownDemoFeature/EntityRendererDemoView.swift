import SwiftUI
import NDKSwiftCore
import NDKSwiftUI

/// Demo showcasing the pluggable renderer system
public struct EntityRendererDemoView: View {
    @State private var lastTappedItem = ""
    @State private var editableContent: String
    @State private var selectedTab = 0

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
                        NDKRichText(
                            content: editableContent,
                            showLinkPreviews: true
                        )
                        .ndk(ndk)
                        .onMentionTap { pubkey in
                            lastTappedItem = "Mention: @\(pubkey.prefix(8))..."
                        }
                        .onHashtagTap { tag in
                            lastTappedItem = "Hashtag: #\(tag)"
                        }
                        .onLinkTap { url in
                            lastTappedItem = "Link: \(url.host ?? url.absoluteString)"
                        }
                        .onImageTap { url in
                            lastTappedItem = "Image: \(url.lastPathComponent)"
                        }
                        .onEventTap { event in
                            lastTappedItem = "Event: \(event.id.prefix(8))..."
                        }
                    }
                    .padding()
                }
                .navigationTitle("NDKRichText")
                .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label("Rich Text", systemImage: "text.bubble")
            }
            .tag(0)

            // Markdown Tab - Markdown rendering
            NavigationView {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        NDKMarkdown(
                            content: markdownContent,
                            blockConfig: .default
                        )
                        .ndk(ndk)
                        .onMentionTap { pubkey in
                            lastTappedItem = "Mention: @\(pubkey.prefix(8))..."
                        }
                        .onHashtagTap { tag in
                            lastTappedItem = "Hashtag: #\(tag)"
                        }
                        .onLinkTap { url in
                            lastTappedItem = "Link: \(url.host ?? url.absoluteString)"
                        }
                    }
                    .padding()
                }
                .navigationTitle("NDKMarkdown")
                .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label("Markdown", systemImage: "doc.richtext")
            }
            .tag(1)

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
            .tag(2)
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

    private static let defaultContent = """
        Just discovered this amazing Nostr library!

        Check out the docs at https://ndk.fyi for more info.

        Special thanks to nostr:npub1l2vyh47mk2p0qlsku7hg0vn29faehy9hy34ygaclpn66ukqp3afqutajft for building this!

        #nostr #bitcoin #decentralized

        Here's a cool image:
        https://r2a.primal.net/uploads2/d/f3/bd/df3bdd118f7db2cdf57821f958033db07dfd9de72248e6869734cbb9e2e8c130.png

        And here's a note worth checking out:
        nostr:nevent1qgsxu35yyt0mwjjh8pcz4zprhxegz69t4wr9t74vk6zne58wzh0waycppemhxue69uhkummn9ekx7mp0qqsq3zms08nzx3a72cgc0jtsd0g0g9fdx0f9jvp69kp05peuvmrpj5g0w639m
        """

    private var markdownContent: String {
        """
        # Pluggable Renderers Demo

        This demonstrates **NDKMarkdown** rendering with support for:

        ## Nostr Entities
        - Mentions: nostr:npub1l2vyh47mk2p0qlsku7hg0vn29faehy9hy34ygaclpn66ukqp3afqutajft
        - Hashtags: #nostr #bitcoin

        ## Links and Images
        Check out [NDK docs](https://ndk.fyi) for more info.

        ![Demo image](https://r2a.primal.net/uploads2/d/f3/bd/df3bdd118f7db2cdf57821f958033db07dfd9de72248e6869734cbb9e2e8c130.png)

        ## Code Blocks
        ```swift
        let ndk = NDK(relayURLs: ["wss://relay.damus.io"])
        ```

        > This is a blockquote showing markdown support

        1. First ordered item
        2. Second ordered item
        3. Third ordered item
        """
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
