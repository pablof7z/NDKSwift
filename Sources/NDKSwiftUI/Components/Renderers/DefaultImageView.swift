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
        AsyncImage(url: url) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity)
                .onTapGesture {
                    (onTap ?? envOnTap)?(url)
                }
        } placeholder: {
            ProgressView()
                .frame(maxWidth: .infinity)
                .frame(height: 200)
        }
        .cornerRadius(8)
    }
}
