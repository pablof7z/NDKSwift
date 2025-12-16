import SwiftUI

/// Pill link - shows URL in a colored pill
public struct PillLinkView: LinkRenderer {
    public let url: URL
    public let onTap: LinkTapHandler?

    @Environment(\.onLinkTap) private var envOnTap

    public init(url: URL, onTap: LinkTapHandler? = nil) {
        self.url = url
        self.onTap = onTap
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "link")
                .font(.caption2)
            Text(url.host ?? url.absoluteString)
                .font(.caption)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.green.opacity(0.15))
        .foregroundColor(.green)
        .cornerRadius(12)
        .onTapGesture {
            (onTap ?? envOnTap)?(url)
        }
    }
}
