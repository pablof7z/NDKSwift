import Kingfisher
import SwiftUI

/// Default implementation of ImageRenderer that displays images as a carousel
public struct DefaultImageView: ImageRenderer {
    public let urls: [URL]
    public let onTap: ImageTapHandler?

    @Environment(\.onImageTap) private var envOnTap

    public init(urls: [URL], onTap: ImageTapHandler? = nil) {
        self.urls = urls
        self.onTap = onTap
    }

    public var body: some View {
        if urls.isEmpty {
            EmptyView()
        } else if urls.count == 1 {
            singleImage(urls[0], index: 0)
        } else {
            carousel
        }
    }

    @ViewBuilder
    private var carousel: some View {
        #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
            TabView {
                ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                    singleImage(url, index: index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .frame(height: 300)
            .cornerRadius(12)
        #else
            // macOS fallback: vertical stack
            VStack(spacing: 8) {
                ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                    singleImage(url, index: index)
                }
            }
        #endif
    }

    private func singleImage(_ url: URL, index: Int) -> some View {
        KFImage(url)
            .resizable()
            .placeholder {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
            }
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: .infinity)
            .cornerRadius(8)
            .onTapGesture {
                if let onTap {
                    onTap(url, index)
                } else if let envOnTap {
                    envOnTap(url, index)
                }
            }
    }
}
