import SwiftUI
import NDKSwiftCore
import NDKSwiftUI

/// Demo view showing link renderers
public struct LinkDemoView: View {
    @State private var content = "Check out https://ndk.fyi for documentation and https://github.com/nostr-protocol/nips for specs."
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
                            .frame(height: 100)
                            .border(Color.gray.opacity(0.3), width: 1)
                        Text("Edit to add more URLs and see them render")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)

                    Divider()

                    // Rendered variations
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Rendered Links")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .padding(.horizontal)

                        variationCard(title: "Inline Basic", description: "Blue underlined hyperlink") {
                            DefaultStyleRichText(content: content)
                                .ndk(ndk)
                                .onLinkTap { url in
                                    lastTapped = "Link: \(url.host ?? url.absoluteString)"
                                }
                        }

                        variationCard(title: "Link Embed", description: "Rich preview card with metadata (OpenGraph-style)") {
                            LinkEmbedRichText(content: content)
                                .ndk(ndk)
                                .onLinkTap { url in
                                    lastTapped = "Link: \(url.host ?? url.absoluteString)"
                                }
                        }

                        variationCard(title: "Badge Style", description: "Link in colored pill with icon") {
                            PillStyleRichText(content: content)
                                .ndk(ndk)
                                .onLinkTap { url in
                                    lastTapped = "Link: \(url.host ?? url.absoluteString)"
                                }
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Links")
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
struct LinkDemoView_Previews: PreviewProvider {
    static var previews: some View {
        LinkDemoView(ndk: NDK())
    }
}
#endif
