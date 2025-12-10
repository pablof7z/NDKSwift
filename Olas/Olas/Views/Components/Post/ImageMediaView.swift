import SwiftUI
import NDKSwift

struct ImageMediaView: View {
    let event: NDKEvent
    @Binding var showLikeAnimation: Bool
    let onDoubleTap: () -> Void
    let onTap: () -> Void

    private var image: NDKImage {
        NDKImage(event: event)
    }

    var body: some View {
        GeometryReader { geometry in
            let maxHeight = geometry.size.width * 1.25

            ZStack {
                imageContent(geometry: geometry, maxHeight: maxHeight)
                    .frame(width: geometry.size.width, height: min(imageHeight(for: geometry.size.width), maxHeight))
                    .clipped()
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { onDoubleTap() }
                    .onTapGesture(count: 1) { onTap() }

                LikeAnimation(isAnimating: $showLikeAnimation)
            }
        }
        .frame(height: imageDisplayHeight)
    }

    @ViewBuilder
    private func imageContent(geometry: GeometryProxy, maxHeight: CGFloat) -> some View {
        if let imageURL = image.primaryImageURL, let url = URL(string: imageURL) {
            CachedAsyncImage(
                url: url,
                blurhash: image.primaryBlurhash,
                aspectRatio: image.primaryAspectRatio
            ) { loadedImage in
                loadedImage
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                imagePlaceholder
            }
            .accessibilityLabel(image.primaryAlt ?? "Post image")
        } else {
            missingImagePlaceholder
        }
    }

    private var imagePlaceholder: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.1))
            .overlay(
                ProgressView()
                    .tint(OlasTheme.Colors.brandPrimary)
            )
    }

    private var missingImagePlaceholder: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.1))
            .overlay(
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            )
            .accessibilityLabel("Image not available")
    }

    private func imageHeight(for width: CGFloat) -> CGFloat {
        if let aspectRatio = image.primaryAspectRatio, aspectRatio > 0 {
            return width / aspectRatio
        }
        return width
    }

    private var imageDisplayHeight: CGFloat {
        let screenWidth = UIScreen.main.bounds.width
        let maxHeight = screenWidth * 1.25
        return min(imageHeight(for: screenWidth), maxHeight)
    }
}
