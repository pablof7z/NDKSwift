import Kingfisher
import SwiftUI

/// Bento grid implementation of ImageRenderer that displays images in an adaptive grid layout
public struct BentoGridImageView: ImageRenderer {
    public let urls: [URL]
    public let onTap: ImageTapHandler?

    @Environment(\.onImageTap) private var envOnTap
    @State private var showFullscreen = false
    @State private var selectedIndex = 0

    private let spacing: CGFloat = 2
    private let cornerRadius: CGFloat = 8

    public init(urls: [URL], onTap: ImageTapHandler? = nil) {
        self.urls = urls
        self.onTap = onTap
    }

    public var body: some View {
        Group {
            if urls.isEmpty {
                EmptyView()
            } else {
                gridLayout
                    .cornerRadius(cornerRadius)
                    .clipped()
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

    @ViewBuilder
    private var gridLayout: some View {
        switch urls.count {
        case 1:
            imageCell(0)
                .aspectRatio(16 / 9, contentMode: .fit)

        case 2:
            HStack(spacing: spacing) {
                imageCell(0)
                imageCell(1)
            }
            .aspectRatio(2 / 1, contentMode: .fit)

        case 3:
            HStack(spacing: spacing) {
                imageCell(0)
                    .aspectRatio(1, contentMode: .fill)
                VStack(spacing: spacing) {
                    imageCell(1)
                    imageCell(2)
                }
                .aspectRatio(0.5, contentMode: .fill)
            }
            .aspectRatio(1.5, contentMode: .fit)

        case 4:
            VStack(spacing: spacing) {
                HStack(spacing: spacing) {
                    imageCell(0)
                    imageCell(1)
                }
                HStack(spacing: spacing) {
                    imageCell(2)
                    imageCell(3)
                }
            }
            .aspectRatio(1, contentMode: .fit)

        default:
            // 5+ images: 2x2 grid with overlay on last cell
            VStack(spacing: spacing) {
                HStack(spacing: spacing) {
                    imageCell(0)
                    imageCell(1)
                }
                HStack(spacing: spacing) {
                    imageCell(2)
                    imageCellWithOverlay(3, remaining: urls.count - 4)
                }
            }
            .aspectRatio(1, contentMode: .fit)
        }
    }

    private func imageCell(_ index: Int) -> some View {
        KFImage(urls[index])
            .resizable()
            .placeholder {
                Color.gray.opacity(0.2)
            }
            .aspectRatio(contentMode: .fill)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture {
                handleTap(index)
            }
    }

    private func imageCellWithOverlay(_ index: Int, remaining: Int) -> some View {
        ZStack {
            imageCell(index)

            if remaining > 0 {
                Color.black.opacity(0.5)
                Text("+\(remaining)")
                    .font(.title.bold())
                    .foregroundStyle(.white)
            }
        }
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
