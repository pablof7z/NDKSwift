import SwiftUI
import NDKSwiftCore

/// Compact article card renderer showing title, summary, and thumbnail
/// Best for feed/list views where space is limited
public struct ArticleCardCompact: ArticleCardRenderer {
    public let event: NDKEvent
    public let onTap: EventTapHandler?

    @Environment(\.ndk) private var ndk
    @Environment(\.onEventTap) private var envOnTap

    // MARK: - Metadata

    public static var supportedKinds: [Int] { [30023] }
    public static var variant: String { "compact" }
    public static var category: String { "article" }
    public static var priority: Int { 5 }

    // MARK: - Initialization

    public init(event: NDKEvent, onTap: EventTapHandler? = nil) {
        self.event = event
        self.onTap = onTap
    }

    // MARK: - Body

    public var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            if let imageURL = extractImage(from: event) {
                CachedAsyncImage(url: imageURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                }
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Content
            VStack(alignment: .leading, spacing: 4) {
                // Title
                if let title = extractTitle(from: event) {
                    Text(title)
                        .font(.headline)
                        .lineLimit(2)
                }

                // Summary
                if let summary = extractSummary(from: event) {
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                // Metadata
                if let ndk = ndk {
                    HStack(spacing: 4) {
                        NDKUIUsername(ndk: ndk, pubkey: event.pubkey)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("•")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        NDKUIRelativeTime(timestamp: event.createdAt)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .onTapGesture {
            (onTap ?? envOnTap)?(event)
        }
    }
}
