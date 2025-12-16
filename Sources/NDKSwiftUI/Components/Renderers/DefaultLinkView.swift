import SwiftUI

/// Default implementation of LinkRenderer that displays URLs with tap support
public struct DefaultLinkView: LinkRenderer {
    public let url: URL
    public let onTap: LinkTapHandler?

    @Environment(\.onLinkTap) private var envOnTap

    public init(url: URL, onTap: LinkTapHandler? = nil) {
        self.url = url
        self.onTap = onTap
    }

    public var body: some View {
        Text(url.absoluteString)
            .foregroundColor(.accentColor)
            .underline()
            .onTapGesture {
                (onTap ?? envOnTap)?(url)
            }
    }
}
