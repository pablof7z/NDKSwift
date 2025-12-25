import Kingfisher
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
                (onTap ?? envOnTap)?(url)
            }
    }
}
