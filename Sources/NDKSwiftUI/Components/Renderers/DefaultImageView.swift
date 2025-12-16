import SwiftUI

/// Default implementation of ImageRenderer that displays images with tap support
public struct DefaultImageView: ImageRenderer {
    public let url: URL
    public let onTap: ImageTapHandler?

    @Environment(\.onImageTap) private var envOnTap

    public init(url: URL, onTap: ImageTapHandler? = nil) {
        self.url = url
        self.onTap = onTap
    }

    public var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .empty:
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .onTapGesture {
                        (onTap ?? envOnTap)?(url)
                    }
            case .failure:
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 100)
            @unknown default:
                EmptyView()
            }
        }
        .cornerRadius(8)
    }
}
