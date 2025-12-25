import SwiftUI

/// Pill view for trending hashtags in the horizontal scroll
struct HashtagPill: View {
    let hashtag: String
    let noteCount: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("#\(hashtag)")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)

            if let count = noteCount {
                Text(formatCount(count))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground))
        .clipShape(Capsule())
    }

    private func formatCount(_ count: Int) -> String {
        if count >= 1000 {
            let k = Double(count) / 1000.0
            return String(format: "%.1fk notes", k)
        } else {
            return "\(count) notes"
        }
    }
}

/// Model for a trending hashtag
struct TrendingHashtag: Identifiable, Sendable {
    let id: String
    let hashtag: String
    let noteCount: Int?

    init(hashtag: String, noteCount: Int? = nil) {
        self.id = hashtag
        self.hashtag = hashtag
        self.noteCount = noteCount
    }
}
