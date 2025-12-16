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

// MARK: - Article Helper

@MainActor
public extension ArticleCardRenderer {
    /// Get the NDKArticle wrapper for the event
    var article: NDKArticle {
        NDKArticle(event: event)
    }
}
