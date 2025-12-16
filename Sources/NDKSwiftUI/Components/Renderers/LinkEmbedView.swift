import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Link embed - shows rich preview card
public struct LinkEmbedView: LinkRenderer {
    public let url: URL
    public let onTap: LinkTapHandler?

    @Environment(\.onLinkTap) private var envOnTap

    public init(url: URL, onTap: LinkTapHandler? = nil) {
        self.url = url
        self.onTap = onTap
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(url.host ?? "Link")
                .font(.headline)
                .lineLimit(2)

            HStack(spacing: 4) {
                Image(systemName: "link")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(url.absoluteString)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .background(Color.ndkSecondaryBackground)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .onTapGesture {
            (onTap ?? envOnTap)?(url)
        }
    }
}
