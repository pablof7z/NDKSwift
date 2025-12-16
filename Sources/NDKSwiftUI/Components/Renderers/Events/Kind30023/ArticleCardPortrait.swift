import SwiftUI
import NDKSwiftCore

/// Portrait/vertical article card renderer with tall cover image
/// Best for grid layouts and card-based UIs
public struct ArticleCardPortrait: ArticleCardRenderer {
    public let event: NDKEvent
    public let onTap: EventTapHandler?

    @Environment(\.ndk) private var ndk
    @Environment(\.onEventTap) private var envOnTap

    // MARK: - Metadata

    public static var supportedKinds: [Int] { [30023] }
    public static var variant: String { "portrait" }
    public static var category: String { "article" }
    public static var priority: Int { 6 }

    // MARK: - Initialization

    public init(event: NDKEvent, onTap: EventTapHandler? = nil) {
        self.event = event
        self.onTap = onTap
    }

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Cover Image (tall portrait aspect ratio)
            if let imageURL = extractImage(from: event) {
                CachedAsyncImage(url: imageURL) { image in
                    image
                        .resizable()
                        .aspectRatio(3/4, contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                }
                .frame(width: 240, height: 320)
                .clipped()
            }

            // Content section
            VStack(alignment: .leading, spacing: 6) {
                // Title
                if let title = extractTitle(from: event) {
                    Text(title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .lineLimit(3)
                }

                // Metadata
                if let ndk = ndk {
                    VStack(alignment: .leading, spacing: 4) {
                        NDKUIUsername(ndk: ndk, pubkey: event.pubkey)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        NDKUIRelativeTime(timestamp: event.createdAt)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
        }
        .frame(width: 240)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .onTapGesture {
            (onTap ?? envOnTap)?(event)
        }
    }
}
