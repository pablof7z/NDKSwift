import Foundation
import NDKSwiftCore

/// Protocol for article card renderers (kind:30023 long-form content)
/// Article cards show preview information (title, summary, image) rather than full content
public protocol ArticleCardRenderer: EventRenderer, EventRendererMetadata {
    /// Article cards support kind:30023 (long-form content)
    static var supportedKinds: [Int] { get }

    /// Category is always "article" for article card renderers
    static var category: String { get }
}

// MARK: - Default Metadata

public extension ArticleCardRenderer {
    static var supportedKinds: [Int] { [30023] }
    static var category: String { "article" }
}

// MARK: - Metadata Extraction Helpers

public extension ArticleCardRenderer {
    /// Extract article title from 'title' tag
    func extractTitle(from event: NDKEvent) -> String? {
        event.tagValue("title")
    }

    /// Extract article summary from 'summary' tag
    func extractSummary(from event: NDKEvent) -> String? {
        event.tagValue("summary")
    }

    /// Extract cover image URL from 'image' tag
    func extractImage(from event: NDKEvent) -> URL? {
        guard let imageStr = event.tagValue("image") else { return nil }
        return URL(string: imageStr)
    }

    /// Extract publication date from 'published_at' tag
    func extractPublishedAt(from event: NDKEvent) -> Date? {
        guard let timestamp = event.tagValue("published_at"),
              let timeInterval = TimeInterval(timestamp) else { return nil }
        return Date(timeIntervalSince1970: timeInterval)
    }

    /// Calculate estimated reading time based on word count
    /// Assumes average reading speed of 200 words per minute
    func estimateReadingTime(from event: NDKEvent) -> Int? {
        let wordCount = event.content.split(separator: " ").count
        guard wordCount > 0 else { return nil }
        let minutes = Int(ceil(Double(wordCount) / 200.0))
        return max(1, minutes) // Minimum 1 minute
    }
}
