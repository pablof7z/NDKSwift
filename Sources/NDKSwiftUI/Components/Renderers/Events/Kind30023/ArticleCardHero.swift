import SwiftUI
import NDKSwiftCore

/// Hero article card renderer with large image and prominent title
/// Best for featured content or detail views
public struct ArticleCardHero: ArticleCardRenderer {
    public let event: NDKEvent
    public let onTap: EventTapHandler?

    @Environment(\.ndk) private var ndk
    @Environment(\.onEventTap) private var envOnTap

    // MARK: - Metadata

    public static var supportedKinds: [Int] { [30023] }
    public static var variant: String { "hero" }
    public static var category: String { "article" }
    public static var priority: Int { 10 }

    // MARK: - Initialization

    public init(event: NDKEvent, onTap: EventTapHandler? = nil) {
        self.event = event
        self.onTap = onTap
    }

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Hero Image with gradient overlay
            if let imageURL = extractImage(from: event) {
                ZStack(alignment: .bottomLeading) {
                    CachedAsyncImage(url: imageURL) { image in
                        image
                            .resizable()
                            .aspectRatio(16/9, contentMode: .fill)
                    } placeholder: {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                    }
                    .frame(height: 200)
                    .clipped()

                    // Subtle gradient overlay for better text readability
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.3)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .frame(height: 200)
            }

            // Content section
            VStack(alignment: .leading, spacing: 8) {
                // Title
                if let title = extractTitle(from: event) {
                    Text(title)
                        .font(.title2)
                        .fontWeight(.bold)
                        .lineLimit(2)
                }

                // Summary
                if let summary = extractSummary(from: event) {
                    Text(summary)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                // Metadata row
                if let ndk = ndk {
                    HStack(spacing: 8) {
                        // Author with profile picture
                        HStack(spacing: 6) {
                            NDKUIProfilePicture(ndk: ndk, pubkey: event.pubkey, size: 20)

                            NDKUIUsername(ndk: ndk, pubkey: event.pubkey)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text("•")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        NDKUIRelativeTime(timestamp: event.createdAt)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        // Reading time estimate
                        if let readingTime = estimateReadingTime(from: event) {
                            Text("•")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text("\(readingTime) min read")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .onTapGesture {
            (onTap ?? envOnTap)?(event)
        }
    }
}
