import Foundation
import NDKSwiftCore

/// Protocol for article card renderers (kind:30023 long-form content)
/// Article cards show preview information (title, summary, image) rather than full content
public protocol ArticleCardRenderer: EventRenderer {}

// MARK: - Article Helper

@MainActor
public extension ArticleCardRenderer {
    /// Get the NDKArticle wrapper for the event
    var article: NDKArticle {
        NDKArticle(event: event)
    }
}
