import SwiftUI
import NDKSwiftCore
import NDKSwiftUI

/// Demo view showing inline entities (mentions, hashtags, links, images) rendering
public struct InlineEntitiesDemoView: View {
    @State private var content = """
    Just discovered this amazing Nostr library!

    Special thanks to nostr:npub1l2vyh47mk2p0qlsku7hg0vn29faehy9hy34ygaclpn66ukqp3afqutajft for building this!

    Topics: #nostr #bitcoin #decentralized

    Check out the docs at https://ndk.fyi for more info.

    Here's a cool image:
    https://blossom.primal.net/f7a062caeb2cb27401b452b2d97b46ed3e7cac97aef86becb60004c4f3c4fca5.jpg
    """
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
                            .frame(height: 200)
                            .border(Color.gray.opacity(0.3), width: 1)
                        Text("Edit to see mentions (@npub), hashtags (#tag), links (https://), and images render inline")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)

                    Divider()

                    // Rendered output
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Rendered Output")
                            .font(.title2)
                            .fontWeight(.semibold)

                        DefaultStyleRichText(content: content)
                            .ndk(ndk)
                            .onMentionTap { pubkey in
                                lastTapped = "Mention: @\(pubkey.prefix(8))..."
                            }
                            .onHashtagTap { tag in
                                lastTapped = "Hashtag: #\(tag)"
                            }
                            .onLinkTap { url in
                                lastTapped = "Link: \(url.host ?? url.absoluteString)"
                            }
                            .onImageTap { url in
                                lastTapped = "Image: \(url.lastPathComponent)"
                            }
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(8)
                    }
                    .padding(.horizontal)

                    // Legend
                    VStack(alignment: .leading, spacing: 12) {
                        Text("What's Rendered:")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 8) {
                            legendItem(icon: "at", title: "Mentions", description: "nostr:npub... → Fetches profile and shows name/avatar")
                            legendItem(icon: "number", title: "Hashtags", description: "#tag → Clickable hashtag")
                            legendItem(icon: "link", title: "Links", description: "https://... → Clickable link with optional preview")
                            legendItem(icon: "photo", title: "Images", description: "Image URLs → Displayed inline")
                        }
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle("Inline Entities")
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
    private func legendItem(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#if DEBUG
struct InlineEntitiesDemoView_Previews: PreviewProvider {
    static var previews: some View {
        InlineEntitiesDemoView(ndk: NDK())
    }
}
#endif
