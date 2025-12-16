import SwiftUI
import NDKSwiftCore
import NDKSwiftUI

/// Demo view showing hashtag renderers
public struct HashtagDemoView: View {
    @State private var content = "Loving #nostr and #bitcoin! The future is #decentralized and #freedom-focused."
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
                        Text("Edit to add more hashtags and see them render")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)

                    Divider()

                    // Rendered variations
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Rendered Hashtags")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .padding(.horizontal)

                        variationCard(title: "Standard", description: "Clickable blue text") {
                            DefaultStyleRichText(content: content)
                                .ndk(ndk)
                                .onHashtagTap { tag in
                                    lastTapped = "Hashtag: #\(tag)"
                                }
                        }

                        variationCard(title: "Minimal", description: "Smaller, muted styling") {
                            CompactStyleRichText(content: content)
                                .ndk(ndk)
                                .onHashtagTap { tag in
                                    lastTapped = "Hashtag: #\(tag)"
                                }
                        }

                        variationCard(title: "Badge Style", description: "Colored pill background") {
                            PillStyleRichText(content: content)
                                .ndk(ndk)
                                .onHashtagTap { tag in
                                    lastTapped = "Hashtag: #\(tag)"
                                }
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Hashtags")
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
struct HashtagDemoView_Previews: PreviewProvider {
    static var previews: some View {
        HashtagDemoView(ndk: NDK())
    }
}
#endif
