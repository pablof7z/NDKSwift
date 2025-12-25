import Kingfisher
import SwiftUI

/// Stacked gallery implementation of ImageRenderer that displays overlapping image cards
public struct StackedGalleryImageView: ImageRenderer {
    public let urls: [URL]
    public let onTap: ImageTapHandler?

    @Environment(\.onImageTap) private var envOnTap
    @State private var showFullscreen = false
    @State private var selectedIndex = 0

    private let maxVisibleCards = 3
    private let cardOffset: CGFloat = 8
    private let cornerRadius: CGFloat = 12

    public init(urls: [URL], onTap: ImageTapHandler? = nil) {
        self.urls = urls
        self.onTap = onTap
    }

    public var body: some View {
        Group {
            if urls.isEmpty {
                EmptyView()
            } else if urls.count == 1 {
                singleImage
            } else {
                stackedCards
            }
        }
        #if os(iOS) || os(tvOS) || os(visionOS)
        .fullScreenCover(isPresented: $showFullscreen) {
            FullscreenImageViewer(
                urls: urls,
                selectedIndex: $selectedIndex,
                isPresented: $showFullscreen
            )
        }
        #elseif os(macOS)
        .sheet(isPresented: $showFullscreen) {
            FullscreenImageViewer(
                urls: urls,
                selectedIndex: $selectedIndex,
                isPresented: $showFullscreen
            )
            .frame(minWidth: 600, minHeight: 400)
        }
        #endif
    }

    private var singleImage: some View {
        KFImage(urls[0])
            .resizable()
            .placeholder {
                Color.gray.opacity(0.2)
                    .frame(height: 200)
            }
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: .infinity)
            .cornerRadius(cornerRadius)
            .onTapGesture {
                handleTap(0)
            }
    }

    private var stackedCards: some View {
        ZStack(alignment: .bottomTrailing) {
            // Stacked cards (reversed so first is on top)
            ForEach(Array(urls.prefix(maxVisibleCards).enumerated().reversed()), id: \.offset) { index, url in
                cardView(url: url, index: index)
                    .offset(x: CGFloat(index) * -cardOffset, y: CGFloat(index) * -cardOffset)
            }

            // Count badge
            countBadge
        }
        .padding(.leading, CGFloat(min(urls.count, maxVisibleCards) - 1) * cardOffset)
        .padding(.top, CGFloat(min(urls.count, maxVisibleCards) - 1) * cardOffset)
    }

    private func cardView(url: URL, index: Int) -> some View {
        KFImage(url)
            .resizable()
            .placeholder {
                Color.gray.opacity(0.2)
            }
            .aspectRatio(contentMode: .fill)
            .frame(height: 200)
            .frame(maxWidth: .infinity)
            .clipped()
            .cornerRadius(cornerRadius)
            .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
            .onTapGesture {
                handleTap(index)
            }
    }

    private var countBadge: some View {
        Text("\(urls.count)")
            .font(.subheadline.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.black.opacity(0.6), in: Capsule())
            .padding(12)
    }

    private func handleTap(_ index: Int) {
        if let onTap {
            onTap(urls[index], index)
        } else if let envOnTap {
            envOnTap(urls[index], index)
        } else {
            selectedIndex = index
            showFullscreen = true
        }
    }
}
