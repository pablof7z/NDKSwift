import Kingfisher
import NDKSwiftCore
import SwiftUI

/// Hero article card renderer with large image and prominent title
/// Best for featured content or detail views
public struct ArticleCardHero: ArticleCardRenderer {
    public let event: NDKEvent
    public let onTap: EventTapHandler?

    @Environment(\.ndk) private var ndk
    @Environment(\.onEventTap) private var envOnTap

    // MARK: - Initialization

    public init(event: NDKEvent, onTap: EventTapHandler? = nil) {
        self.event = event
        self.onTap = onTap
    }

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Hero Image with gradient overlay
            if let imageURL = article.imageURL {
                ZStack(alignment: .bottomLeading) {
                    KFImage(imageURL)
                        .resizable()
                        .placeholder { Rectangle().fill(Color.gray.opacity(0.2)) }
                        .aspectRatio(16/9, contentMode: .fill)
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
                if let title = article.title {
                    Text(title)
                        .font(.title2)
                        .fontWeight(.bold)
                        .lineLimit(2)
                }

                // Summary
                if let summary = article.summary {
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
                            NDKUIProfilePicture(ndk: ndk, pubkey: article.pubkey, size: 20)

                            Text(ndk.profile(for: article.pubkey).displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text("•")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        NDKUIRelativeTime(timestamp: article.createdAt)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("•")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("\(article.readingTime) min read")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(16)
        }
        .background(Color.ndkSecondaryBackground)
        .cornerRadius(12)
        .onTapGesture {
            (onTap ?? envOnTap)?(event)
        }
    }
}
