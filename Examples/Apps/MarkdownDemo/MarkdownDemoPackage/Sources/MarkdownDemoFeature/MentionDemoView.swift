import SwiftUI
import NDKSwiftCore
import NDKSwiftUI

/// Demo view showing mention renderers
public struct MentionDemoView: View {
    @State private var content = "Hey nostr:npub1l2vyh47mk2p0qlsku7hg0vn29faehy9hy34ygaclpn66ukqp3afqutajft, thanks for building NDK!"
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
                            .frame(height: 80)
                            .border(Color.gray.opacity(0.3), width: 1)
                        Text("Edit to change the npub reference and see it render with different styles")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)

                    Divider()

                    // Rendered variations
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Rendered Mentions")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .padding(.horizontal)

                        variationCard(title: "With Profile", description: "Loads user profile, shows display name and avatar") {
                            DefaultStyleRichText(content: content)
                                .ndk(ndk)
                                .onMentionTap { pubkey in
                                    lastTapped = "Mention: @\(pubkey.prefix(8))..."
                                }
                        }

                        variationCard(title: "Minimal", description: "Truncated npub, no profile loading") {
                            CompactStyleRichText(content: content)
                                .ndk(ndk)
                                .onMentionTap { pubkey in
                                    lastTapped = "Mention: @\(pubkey.prefix(8))..."
                                }
                        }

                        variationCard(title: "Badge Style", description: "Display name in colored pill with icon") {
                            PillStyleRichText(content: content)
                                .ndk(ndk)
                                .onMentionTap { pubkey in
                                    lastTapped = "Mention: @\(pubkey.prefix(8))..."
                                }
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Mentions")
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
struct MentionDemoView_Previews: PreviewProvider {
    static var previews: some View {
        MentionDemoView(ndk: NDK())
    }
}
#endif
