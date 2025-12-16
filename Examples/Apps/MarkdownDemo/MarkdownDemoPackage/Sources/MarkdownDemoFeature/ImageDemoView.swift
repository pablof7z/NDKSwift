import SwiftUI
import NDKSwiftCore
import NDKSwiftUI

/// Demo view showing image/media rendering variations
public struct ImageDemoView: View {
    @State private var content = """
    Here's a cool image:
    https://blossom.primal.net/f7a062caeb2cb27401b452b2d97b46ed3e7cac97aef86becb60004c4f3c4fca5.jpg
    """
    @State private var lastTapped = ""

    let imageURLs = [
        URL(string: "https://blossom.primal.net/f7a062caeb2cb27401b452b2d97b46ed3e7cac97aef86becb60004c4f3c4fca5.jpg")!,
        URL(string: "https://r2a.primal.net/uploads2/d/f3/bd/df3bdd118f7db2cdf57821f958033db07dfd9de72248e6869734cbb9e2e8c130.png")!,
        URL(string: "https://blossom.primal.net/f7a062caeb2cb27401b452b2d97b46ed3e7cac97aef86becb60004c4f3c4fca5.jpg")!,
        URL(string: "https://r2a.primal.net/uploads2/d/f3/bd/df3bdd118f7db2cdf57821f958033db07dfd9de72248e6869734cbb9e2e8c130.png")!
    ]

    let ndk: NDK

    public init(ndk: NDK) {
        self.ndk = ndk
    }

    public var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Single image section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Single Image")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .padding(.horizontal)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Content")
                                .font(.headline)
                            TextEditor(text: $content)
                                .font(.system(.body, design: .monospaced))
                                .frame(height: 80)
                                .border(Color.gray.opacity(0.3), width: 1)
                            Text("Images display inline automatically")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)

                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Basic")
                                    .font(.headline)
                                Text("Standard image display with tap support")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            DefaultStyleRichText(content: content)
                                .ndk(ndk)
                                .onImageTap { url in
                                    lastTapped = "Image: \(url.lastPathComponent)"
                                }
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(8)
                        }
                        .padding(.horizontal)
                    }

                    Divider()
                        .padding(.horizontal)

                    // Multiple images section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Multiple Images")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .padding(.horizontal)

                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Carousel")
                                    .font(.headline)
                                Text("Swipeable carousel with page indicators")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            MediaCarouselView(urls: imageURLs) { url in
                                lastTapped = "Image: \(url.lastPathComponent)"
                            }
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(8)
                        }
                        .padding(.horizontal)

                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Bento Grid")
                                    .font(.headline)
                                Text("Pinterest-style masonry grid with varying heights")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            MediaBentoView(urls: imageURLs) { url in
                                lastTapped = "Image: \(url.lastPathComponent)"
                            }
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(8)
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Images")
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
}

#if DEBUG
struct ImageDemoView_Previews: PreviewProvider {
    static var previews: some View {
        ImageDemoView(ndk: NDK())
    }
}
#endif
